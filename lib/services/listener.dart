import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:onnxruntime/onnxruntime.dart';
import 'package:record/record.dart';

import 'diag.dart';

/// Listens to the mic at 16 kHz mono and slices it into utterances using
/// Silero VAD. Tuned for conversation: fires ~350 ms after the speaker pauses.
class Listener {
  static const int sampleRate = 16000;
  static const int window = 512; // Silero v5 frame at 16 kHz (32 ms)
  static const int context = 64; // Silero v5 wants the previous 64 samples prepended

  // Tunables
  final double threshold = 0.5;
  final int silenceMs = 350; // pause that ends an utterance
  final int minSpeechMs = 300; // ignore blips shorter than this
  final int preRollMs = 240; // audio kept from before speech was detected
  final int maxUtteranceMs = 12000; // force a cut on very long monologues

  final AudioRecorder _rec = AudioRecorder();
  OrtSession? _vad;
  OrtSessionOptions? _vadOpts;
  List<List<Float32List>> _state = _zeroState();
  Float32List _context = Float32List(context);
  StreamSubscription<Uint8List>? _sub;
  final _pending = <int>[]; // leftover int16 samples not yet a full window

  final _preRoll = <Float32List>[];
  final _utterance = <Float32List>[];
  bool _inSpeech = false;
  int _silenceRun = 0;
  int _speechSamples = 0;

  /// While true the mic is ignored (used while the phone itself is talking).
  bool muted = false;

  final _utterances = StreamController<Float32List>.broadcast();
  final _level = StreamController<double>.broadcast();

  /// Complete utterances (float PCM, 16 kHz mono).
  Stream<Float32List> get utterances => _utterances.stream;

  /// Speech probability for UI meters (0..1), ~30 Hz.
  Stream<double> get level => _level.stream;

  bool get speaking => _inSpeech;

  static List<List<Float32List>> _zeroState() =>
      List.generate(2, (_) => [Float32List(128)]);

  Future<void> start(String vadModelPath) async {
    OrtEnv.instance.init();
    _vadOpts = OrtSessionOptions()
      ..setIntraOpNumThreads(1)
      ..setInterOpNumThreads(1)
      ..setSessionGraphOptimizationLevel(GraphOptimizationLevel.ortEnableAll);
    _vad = OrtSession.fromFile(File(vadModelPath), _vadOpts!);
    _state = _zeroState();
    _context = Float32List(context);
    _reset();

    // Always use the phone's own microphone: Bluetooth headset mics are
    // narrow phone-call quality and confuse the recognizer. Earbuds stay
    // for listening only.
    InputDevice? builtIn;
    try {
      final devs = await _rec.listInputDevices();
      Diag.instance.log('mic devices: ${devs.map((d) => d.label).join(' | ')}');
      for (final d in devs) {
        final l = d.label.toLowerCase();
        if (l.contains('bluetooth') || l.contains('ble') || l.contains('headset') || l.contains('usb')) continue;
        builtIn = d;
        if (l.contains('built') || l.contains('mic')) break;
      }
    } catch (_) {}
    final stream = await _rec.startStream(RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: sampleRate,
      numChannels: 1,
      autoGain: true,
      echoCancel: true,
      noiseSuppress: true,
      device: builtIn,
      androidConfig: const AndroidRecordConfig(manageBluetooth: false),
    ));
    Diag.instance.log('mic: using ${builtIn?.label ?? 'default'} (bluetooth mic off)');
    _sub = stream.listen(_onAudio);
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    await _rec.cancel();
    _vad?.release();
    _vadOpts?.release();
    _vad = null;
    _vadOpts = null;
  }

  void dispose() {
    _utterances.close();
    _level.close();
    _rec.dispose();
  }

  void _reset() {
    _inSpeech = false;
    _silenceRun = 0;
    _speechSamples = 0;
    _utterance.clear();
    _preRoll.clear();
    _pending.clear();
  }

  int? _carry; // odd trailing byte from the previous chunk
  int _chunks = 0;
  double _peakProb = 0;
  double _peakLevel = 0;
  int _framesSinceReport = 0;

  void _onAudio(Uint8List bytes) {
    if (_chunks++ == 0) Diag.instance.log('mic: audio flowing (${bytes.length} bytes/chunk)');
    // Chunks can start at odd offsets and have odd lengths; read byte-wise.
    var data = bytes;
    if (_carry != null) {
      data = Uint8List(bytes.length + 1)
        ..[0] = _carry!
        ..setRange(1, bytes.length + 1, bytes);
      _carry = null;
    }
    final even = data.length & ~1;
    if (even != data.length) _carry = data[data.length - 1];
    final bd = ByteData.sublistView(data, 0, even);
    for (var i = 0; i < even; i += 2) {
      _pending.add(bd.getInt16(i, Endian.little));
    }
    while (_pending.length >= window) {
      final frame = Float32List(window);
      for (var i = 0; i < window; i++) {
        frame[i] = _pending[i] / 32768.0;
      }
      _pending.removeRange(0, window);
      _process(frame);
    }
  }

  void _process(Float32List frame) {
    if (muted) {
      if (_inSpeech) _reset();
      return;
    }
    final p = _predict(frame);
    if (!_level.isClosed) _level.add(p);
    // Every ~2 s: how loud was the mic and how sure was the voice detector?
    var peak = 0.0;
    for (final v in frame) {
      final a = v.abs();
      if (a > peak) peak = a;
    }
    if (peak > _peakLevel) _peakLevel = peak;
    if (p > _peakProb) _peakProb = p;
    if (++_framesSinceReport >= 62) {
      Diag.instance.log('mic: peak level ${(_peakLevel * 100).toStringAsFixed(0)}%  voice score ${(_peakProb * 100).toStringAsFixed(0)}%${_inSpeech ? '  (in speech)' : ''}');
      _framesSinceReport = 0;
      _peakLevel = 0;
      _peakProb = 0;
    }

    final frameMs = window * 1000 ~/ sampleRate;
    if (!_inSpeech) {
      _preRoll.add(frame);
      final keep = preRollMs ~/ frameMs;
      if (_preRoll.length > keep) _preRoll.removeAt(0);
      if (p >= threshold) {
        _inSpeech = true;
        _utterance
          ..clear()
          ..addAll(_preRoll);
        _speechSamples = 0;
        _silenceRun = 0;
      }
      return;
    }

    _utterance.add(frame);
    _speechSamples += window;
    if (p >= threshold - 0.15) {
      _silenceRun = 0;
    } else {
      _silenceRun += frameMs;
    }
    final utteranceMs = _utterance.length * frameMs;
    if (_silenceRun >= silenceMs || utteranceMs >= maxUtteranceMs) {
      final speechMs = utteranceMs - _silenceRun;
      if (speechMs >= minSpeechMs) _emit();
      _inSpeech = false;
      _utterance.clear();
      _preRoll.clear();
    }
  }

  void _emit() {
    final total = _utterance.fold<int>(0, (a, f) => a + f.length);
    final out = Float32List(total);
    var o = 0;
    for (final f in _utterance) {
      out.setRange(o, o + f.length, f);
      o += f.length;
    }
    if (!_utterances.isClosed) _utterances.add(out);
  }

  double _predict(Float32List frame) {
    final session = _vad;
    if (session == null) return 0;
    // Silero v5: input = [last 64 samples of previous window] + [this window].
    final withCtx = Float32List(context + window)
      ..setRange(0, context, _context)
      ..setRange(context, context + window, frame);
    _context = Float32List.sublistView(frame, window - context);
    final input = OrtValueTensor.createTensorWithDataList(withCtx, [1, context + window]);
    final state = OrtValueTensor.createTensorWithDataList(_state, [2, 1, 128]);
    final sr = OrtValueTensor.createTensorWithDataList(Int64List.fromList([sampleRate]), []);
    final run = OrtRunOptions();
    final outs = session.run(run, {'input': input, 'state': state, 'sr': sr});
    input.release();
    state.release();
    sr.release();
    run.release();
    final prob = (outs[0]!.value as List<List<double>>)[0][0];
    final st = outs[1]!.value as List<List<List<double>>>;
    _state = st.map((a) => a.map((b) => Float32List.fromList(b)).toList()).toList();
    for (final o in outs) {
      o?.release();
    }
    return prob;
  }
}

/// 16-bit mono WAV writer for handing utterances to Whisper.
Future<String> writeWav(Float32List pcm, String path) async {
  final n = pcm.length;
  final bytes = ByteData(44 + n * 2);
  void str(int off, String s) {
    for (var i = 0; i < s.length; i++) {
      bytes.setUint8(off + i, s.codeUnitAt(i));
    }
  }

  str(0, 'RIFF');
  bytes.setUint32(4, 36 + n * 2, Endian.little);
  str(8, 'WAVE');
  str(12, 'fmt ');
  bytes.setUint32(16, 16, Endian.little);
  bytes.setUint16(20, 1, Endian.little); // PCM
  bytes.setUint16(22, 1, Endian.little); // mono
  bytes.setUint32(24, Listener.sampleRate, Endian.little);
  bytes.setUint32(28, Listener.sampleRate * 2, Endian.little);
  bytes.setUint16(32, 2, Endian.little);
  bytes.setUint16(34, 16, Endian.little);
  str(36, 'data');
  bytes.setUint32(40, n * 2, Endian.little);
  for (var i = 0; i < n; i++) {
    final v = (pcm[i] * 32767).clamp(-32768, 32767).toInt();
    bytes.setInt16(44 + i * 2, v, Endian.little);
  }
  await File(path).writeAsBytes(bytes.buffer.asUint8List(), flush: true);
  return path;
}
