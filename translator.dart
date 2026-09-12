// ignore_for_file: implementation_imports
import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:onnxruntime/onnxruntime.dart';
import 'package:onnxruntime/src/bindings/onnxruntime_bindings_generated.dart' as bg;

import 'tokenizer.dart';

/// Public handle used by the main isolate. All ONNX work happens in a worker
/// isolate so the UI never stutters while a sentence is being translated.
class Translator {
  Isolate? _isolate;
  SendPort? _port;
  final _pending = <int, Completer<String>>{};
  int _seq = 0;
  final ReceivePort _rx = ReceivePort();

  bool get ready => _port != null;

  Future<void> start({
    required String encoderPath,
    required String decoderPath,
    required String tokenizerPath,
    int threads = 4,
  }) async {
    if (_port != null) return;
    final ready = Completer<void>();
    _rx.listen((msg) {
      if (msg is SendPort) {
        _port = msg;
        return;
      }
      final m = msg as Map;
      if (m['type'] == 'ready') {
        if (m['error'] != null) {
          ready.completeError(StateError(m['error'] as String));
        } else {
          ready.complete();
        }
        return;
      }
      final c = _pending.remove(m['id'] as int);
      if (c == null) return;
      if (m['error'] != null) {
        c.completeError(StateError(m['error'] as String));
      } else {
        c.complete(m['text'] as String);
      }
    });
    _isolate = await Isolate.spawn(_workerMain, {
      'port': _rx.sendPort,
      'encoder': encoderPath,
      'decoder': decoderPath,
      'tokenizer': tokenizerPath,
      'threads': threads,
    });
    await ready.future;
  }

  Future<String> translate(String text, String srcNllb, String tgtNllb) {
    final port = _port;
    if (port == null) throw StateError('Translator not started');
    final id = _seq++;
    final c = Completer<String>();
    _pending[id] = c;
    port.send({'id': id, 'text': text, 'src': srcNllb, 'tgt': tgtNllb});
    return c.future;
  }

  void dispose() {
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _port = null;
    _rx.close();
  }
}

// ---------------------------------------------------------------------------
// Worker isolate
// ---------------------------------------------------------------------------

void _workerMain(Map init) {
  final SendPort out = init['port'] as SendPort;
  final rx = ReceivePort();
  out.send(rx.sendPort);

  _NllbEngine? engine;
  try {
    engine = _NllbEngine(
      encoderPath: init['encoder'] as String,
      decoderPath: init['decoder'] as String,
      tokenizerPath: init['tokenizer'] as String,
      threads: init['threads'] as int,
    );
    out.send({'type': 'ready'});
  } catch (e) {
    out.send({'type': 'ready', 'error': e.toString()});
    return;
  }

  rx.listen((msg) {
    final m = msg as Map;
    final id = m['id'] as int;
    try {
      final text = engine!.translate(m['text'] as String, m['src'] as String, m['tgt'] as String);
      out.send({'id': id, 'text': text});
    } catch (e) {
      out.send({'id': id, 'error': e.toString()});
    }
  });
}

class _NllbEngine {
  late final NllbTokenizer tok;
  late final OrtSession encoder;
  late final OrtSession decoder;
  late final OrtSessionOptions _opts;
  late final List<String> _pastInputs; // past_key_values.N.decoder.key ...
  final int maxTokens = 160;

  static const int heads = 16;
  static const int headDim = 64;

  _NllbEngine({
    required String encoderPath,
    required String decoderPath,
    required String tokenizerPath,
    required int threads,
  }) {
    OrtEnv.instance.init();
    tok = NllbTokenizer.load(tokenizerPath);
    _opts = OrtSessionOptions()
      ..setIntraOpNumThreads(threads)
      ..setInterOpNumThreads(1)
      ..setSessionGraphOptimizationLevel(GraphOptimizationLevel.ortEnableAll);
    encoder = OrtSession.fromFile(File(encoderPath), _opts);
    decoder = OrtSession.fromFile(File(decoderPath), _opts);
    _pastInputs = decoder.inputNames.where((n) => n.startsWith('past_key_values.')).toList();
  }

  String translate(String text, String src, String tgt) {
    final ids = tok.encode(text, src);
    final n = ids.length;
    final run = OrtRunOptions();

    // ---- Encoder ----
    final inputIds = OrtValueTensor.createTensorWithDataList(Int64List.fromList(ids), [1, n]);
    final mask = OrtValueTensor.createTensorWithDataList(Int64List.fromList(List.filled(n, 1)), [1, n]);
    final encOut = encoder.run(run, {'input_ids': inputIds, 'attention_mask': mask});
    final hidden = encOut[0]!; // last_hidden_state [1, n, 1024]

    // ---- Decoder (greedy, KV cache) ----
    final tgtId = tok.langId(tgt);
    final generated = <int>[];
    Map<String, OrtValue> past = {};
    var releasable = <OrtValue>[];
    var step = 0;
    try {
      while (generated.length < maxTokens) {
        final List<int> stepIds = step == 0 ? [tok.eosId, tgtId] : [generated.last];
        final decIds =
            OrtValueTensor.createTensorWithDataList(Int64List.fromList(stepIds), [1, stepIds.length]);
        final useCache = OrtValueTensor.createTensorWithDataList([step != 0], [1]);

        if (step == 0) {
          // The no-cache branch ignores these, but ORT still wants them present.
          past = {
            for (final name in _pastInputs)
              name: OrtValueTensor.createTensorWithDataList(
                  Float32List(heads * headDim), [1, heads, 1, headDim]),
          };
          releasable = past.values.toList();
        }
        final inputs = <String, OrtValue>{
          'input_ids': decIds,
          'encoder_attention_mask': mask,
          'encoder_hidden_states': hidden,
          'use_cache_branch': useCache,
          for (final name in _pastInputs) name: past[name]!,
        };

        final outs = decoder.run(run, inputs);
        decIds.release();
        useCache.release();

        // logits: [1, T, V] — read only the last row, straight from native memory.
        final logitsIdx = decoder.outputNames.indexOf('logits');
        final logits = outs[logitsIdx < 0 ? 0 : logitsIdx]!;
        final next = _argmaxLastRow(logits);
        logits.release();

        // Wire present.* → past_key_values.* for the next step (no copies).
        final newPast = <String, OrtValue>{};
        final keep = <OrtValue>{};
        for (var i = 0; i < outs.length; i++) {
          if (i == (logitsIdx < 0 ? 0 : logitsIdx)) continue;
          final v = outs[i];
          if (v == null) continue;
          final outName = decoder.outputNames[i];
          if (!outName.startsWith('present.')) {
            v.release();
            continue;
          }
          final inName = 'past_key_values.${outName.substring('present.'.length)}';
          if (_pastInputs.contains(inName)) {
            newPast[inName] = v;
            keep.add(v);
          } else {
            v.release();
          }
        }
        // Inputs the cache branch didn't re-emit (e.g. encoder K/V) carry over.
        for (final name in _pastInputs) {
          newPast[name] ??= past[name]!;
          keep.add(newPast[name]!);
        }
        for (final v in releasable) {
          if (!keep.contains(v)) v.release();
        }
        releasable = keep.toList();
        past = newPast;
        step++;

        if (next == tok.eosId) break;
        generated.add(next);
        if (_isLooping(generated)) break;
      }
    } finally {
      for (final v in releasable) {
        v.release();
      }
      hidden.release();
      inputIds.release();
      mask.release();
      run.release();
    }
    return tok.decode(generated);
  }

  /// Read only the final vocab row of a [1, T, V] float tensor via FFI.
  int _argmaxLastRow(OrtValue logits) {
    final api = OrtEnv.instance.ortApiPtr.ref;
    final infoPP = calloc<ffi.Pointer<bg.OrtTensorTypeAndShapeInfo>>();
    var st = api.GetTensorTypeAndShape.asFunction<
        bg.OrtStatusPtr Function(ffi.Pointer<bg.OrtValue>,
            ffi.Pointer<ffi.Pointer<bg.OrtTensorTypeAndShapeInfo>>)>()(logits.ptr, infoPP);
    OrtStatus.checkOrtStatus(st);
    final countP = calloc<ffi.Size>();
    st = api.GetTensorShapeElementCount.asFunction<
        bg.OrtStatusPtr Function(
            ffi.Pointer<bg.OrtTensorTypeAndShapeInfo>, ffi.Pointer<ffi.Size>)>()(infoPP.value, countP);
    OrtStatus.checkOrtStatus(st);
    final dimsCountP = calloc<ffi.Size>();
    st = api.GetDimensionsCount.asFunction<
        bg.OrtStatusPtr Function(
            ffi.Pointer<bg.OrtTensorTypeAndShapeInfo>, ffi.Pointer<ffi.Size>)>()(infoPP.value, dimsCountP);
    OrtStatus.checkOrtStatus(st);
    final dimsP = calloc<ffi.Int64>(dimsCountP.value);
    st = api.GetDimensions.asFunction<
        bg.OrtStatusPtr Function(ffi.Pointer<bg.OrtTensorTypeAndShapeInfo>, ffi.Pointer<ffi.Int64>,
            int)>()(infoPP.value, dimsP, dimsCountP.value);
    OrtStatus.checkOrtStatus(st);
    final vocab = dimsP[dimsCountP.value - 1];
    final total = countP.value;
    api.ReleaseTensorTypeAndShapeInfo
        .asFunction<void Function(ffi.Pointer<bg.OrtTensorTypeAndShapeInfo>)>()(infoPP.value);

    final dataPP = calloc<ffi.Pointer<ffi.Void>>();
    st = api.GetTensorMutableData.asFunction<
        bg.OrtStatusPtr Function(ffi.Pointer<bg.OrtValue>, ffi.Pointer<ffi.Pointer<ffi.Void>>)>()(
        logits.ptr, dataPP);
    OrtStatus.checkOrtStatus(st);
    final data = dataPP.value.cast<ffi.Float>().asTypedList(total);
    final start = total - vocab;
    var best = 0;
    var bestVal = double.negativeInfinity;
    for (var i = 0; i < vocab; i++) {
      final v = data[start + i];
      if (v > bestVal) {
        bestVal = v;
        best = i;
      }
    }
    calloc.free(dataPP);
    calloc.free(dimsP);
    calloc.free(dimsCountP);
    calloc.free(countP);
    calloc.free(infoPP);
    return best;
  }

  /// Greedy decoders occasionally get stuck repeating; cut it off.
  bool _isLooping(List<int> g) {
    if (g.length < 12) return false;
    final tail = g.sublist(g.length - 4);
    final prev = g.sublist(g.length - 8, g.length - 4);
    final prev2 = g.sublist(g.length - 12, g.length - 8);
    bool same(List<int> a, List<int> b) {
      for (var i = 0; i < a.length; i++) {
        if (a[i] != b[i]) return false;
      }
      return true;
    }
    return same(tail, prev) && same(prev, prev2);
  }
}
