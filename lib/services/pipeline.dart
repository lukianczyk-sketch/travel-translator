import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models/language.dart';
import 'book_store.dart';
import 'diag.dart';
import 'lang_guess.dart';
import 'listener.dart';
import 'model_manager.dart';
import 'stt.dart';
import 'translator.dart';
import 'tts.dart';

enum Turn { listening, talking, them, you, thinking, speaking }

class Latency {
  final int hearMs; // speech end → text
  final int translateMs; // text → translation
  final int totalMs; // speech end → voice starts
  const Latency(this.hearMs, this.translateMs, this.totalMs);
}

class Exchange {
  final bool fromThem;
  final String original;
  final String translated;
  final String speakLocale;
  const Exchange(this.fromThem, this.original, this.translated, this.speakLocale);
}

/// Owns the live conversation. One instance per TALK session.
class Pipeline extends ChangeNotifier {
  /// Languages that may be spoken to us (one or several).
  final List<Language> others;

  /// The language we currently answer in — the last one spoken to us.
  Language other;
  Pipeline(this.others) : other = others.first;

  final Listener _listener = Listener();
  final Translator _translator = Translator();
  final Speaker _speaker = Speaker();
  SpeechToText? _stt;

  Turn turn = Turn.listening;
  String status = 'Loading engines…';
  bool ready = false;
  bool speakMySide = true; // say my English aloud in their language
  double level = 0;
  Latency? lastLatency;
  Exchange? last;
  final List<Exchange> history = [];

  StreamSubscription? _uttSub, _lvlSub;
  final _queue = <Float32List>[];
  bool _busy = false;
  int _wavSeq = 0;
  bool _stopped = false;

  void _log(String m) => Diag.instance.log(m);

  Future<void> start() async {
    final mm = ModelManager.instance;
    _log('pipeline start: languages=${others.map((l) => l.code).join(',')}');
    _stt = SpeechToText(
      modelPath: mm.filePath('ggml-large-v3-turbo-q8_0.bin'),
      vadModelPath: mm.filePath('silero_vad.onnx'),
      threads: Diag.instance.whisperThreads,
    )..fast = Diag.instance.fastWhisper;
    await WakelockPlus.enable();

    status = 'Waking up the brain…';
    notifyListeners();
    _log('loading NLLB…');
    final tb = DateTime.now();
    await _translator.start(
      encoderPath: mm.filePath('nllb_encoder.onnx'),
      decoderPath: mm.filePath('nllb_decoder.onnx'),
      tokenizerPath: mm.filePath('nllb_tokenizer.json'),
    );

    _log('NLLB ready in ${DateTime.now().difference(tb).inMilliseconds} ms');
    status = 'Warming up the ears…';
    notifyListeners();
    final warm = await ensureSilentWav(mm.modelsPath);
    final tw = DateTime.now();
    await _stt!.warmUp(warm);
    _log('Whisper warm in ${DateTime.now().difference(tw).inMilliseconds} ms (fast=${_stt!.fast}, threads=${_stt!.threads})');
    await _speaker.init();
    _log('TTS ready');

    status = 'Listening';
    ready = true;
    notifyListeners();

    await _listener.start(mm.filePath('silero_vad.onnx'));
    _log('mic + VAD listening');
    _lvlSub = _listener.level.listen((p) {
      level = p;
      if (turn == Turn.listening && _listener.speaking) {
        turn = Turn.talking;
      } else if (turn == Turn.talking && !_listener.speaking) {
        turn = Turn.listening;
      }
      notifyListeners();
    });
    _uttSub = _listener.utterances.listen((pcm) {
      _log('utterance captured: ${(pcm.length / Listener.sampleRate).toStringAsFixed(2)} s');
      _queue.add(pcm);
      _drain();
    });
  }

  Future<void> _drain() async {
    if (_busy) return;
    _busy = true;
    try {
      while (_queue.isNotEmpty && !_stopped) {
        final pcm = _queue.removeAt(0);
        await _handle(pcm);
      }
    } finally {
      _busy = false;
    }
  }

  Future<void> _handle(Float32List pcm) async {
    final t0 = DateTime.now();
    turn = Turn.thinking;
    status = 'Hearing…';
    notifyListeners();

    final path = '${ModelManager.instance.modelsPath}/utt_${_wavSeq++ % 4}.wav';
    await writeWav(pcm, path);
    _log('whisper: transcribing…');
    String text;
    try {
      text = await _stt!.transcribe(path);
      _log('whisper: "${text.length > 80 ? '${text.substring(0, 80)}…' : text}" in ${DateTime.now().difference(t0).inMilliseconds} ms');
    } catch (e) {
      _log('ERROR whisper: $e');
      status = 'Ears error: $e';
      turn = Turn.listening;
      notifyListeners();
      return;
    }
    final t1 = DateTime.now();
    if (SpeechToText.looksLikeNoise(text)) {
      _log('whisper: ignored as noise');
      turn = Turn.listening;
      status = 'Listening';
      notifyListeners();
      return;
    }

    final detected = others.length == 1
        ? (LangGuess.isEnglish(text, other) ? null : other)
        : LangGuess.detect(text, others);
    final fromThem = detected != null;
    if (fromThem && detected != other) other = detected;
    _log('direction: ${fromThem ? '${other.code} → en' : 'en → ${other.code}'}');
    final src = fromThem ? other.nllbCode : english.nllbCode;
    final tgt = fromThem ? english.nllbCode : other.nllbCode;
    turn = fromThem ? Turn.them : Turn.you;
    status = 'Translating…';
    last = Exchange(fromThem, text, '…', fromThem ? english.ttsLocale : other.ttsLocale);
    notifyListeners();

    // Sentence by sentence so the voice can start before the whole thing is done.
    final sentences = _split(text);
    final outParts = <String>[];
    var spokenStarted = false;
    var t2 = t1;
    var voiceAt = t1;
    for (final s in sentences) {
      String tr;
      final tm = DateTime.now();
      try {
        tr = await _translator.translate(s, src, tgt);
        _log('nllb: "${tr.length > 80 ? '${tr.substring(0, 80)}…' : tr}" in ${DateTime.now().difference(tm).inMilliseconds} ms');
      } catch (e) {
        _log('ERROR nllb: $e');
        tr = '[translation error]';
      }
      if (!spokenStarted) t2 = DateTime.now();
      outParts.add(tr);
      last = Exchange(fromThem, text, outParts.join(' '), last!.speakLocale);
      notifyListeners();

      final shouldSpeak = fromThem || speakMySide;
      if (shouldSpeak && tr.isNotEmpty && !tr.startsWith('[')) {
        if (!spokenStarted) {
          spokenStarted = true;
          voiceAt = DateTime.now();
          lastLatency = Latency(
            t1.difference(t0).inMilliseconds,
            t2.difference(t1).inMilliseconds,
            voiceAt.difference(t0).inMilliseconds,
          );
        }
        turn = Turn.speaking;
        status = fromThem ? 'In your ear…' : 'Speaking for you…';
        _listener.muted = true; // don't hear ourselves
        notifyListeners();
        _log('tts: speaking (${last!.speakLocale})');
        try {
          await _speaker.say(tr, last!.speakLocale);
        } catch (e) {
          _log('ERROR tts: $e');
        }
        _log('tts: done');
      }
    }
    if (!spokenStarted) {
      lastLatency = Latency(
        t1.difference(t0).inMilliseconds,
        DateTime.now().difference(t1).inMilliseconds,
        DateTime.now().difference(t0).inMilliseconds,
      );
    }
    history.add(last!);
    BookStore.instance.addHistory(Entry(
      time: DateTime.now().millisecondsSinceEpoch,
      fromThem: last!.fromThem,
      original: last!.original,
      translated: last!.translated,
      speakLocale: last!.speakLocale,
      langCode: other.code,
    ));
    _listener.muted = false;
    turn = Turn.listening;
    status = 'Listening';
    notifyListeners();
  }

  List<String> _split(String text) {
    final parts = text
        .split(RegExp(r'(?<=[.!?。！？])\s+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    return parts.isEmpty ? [text] : parts;
  }

  Future<void> replay() async {
    final e = last;
    if (e == null || e.translated.isEmpty || e.translated == '…') return;
    _listener.muted = true;
    await _speaker.say(e.translated, e.speakLocale);
    _listener.muted = false;
  }

  Future<void> stop() async {
    _log('pipeline stop');
    _stopped = true;
    await _uttSub?.cancel();
    await _lvlSub?.cancel();
    await _listener.stop();
    _listener.dispose();
    await _speaker.stop();
    _translator.dispose();
    await _stt?.dispose();
    await WakelockPlus.disable();
  }
}
