import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models/language.dart';
import 'book_store.dart';
import 'diag.dart';
import 'lang_guess.dart';
import 'listener.dart';
import 'model_manager.dart';
import 'native_stt.dart';
import 'stt.dart';
import 'tts.dart';

enum Turn { listening, talking, them, you, thinking, speaking }

class Latency {
  final int hearMs; // sentence end → text
  final int translateMs; // text → translation
  final int totalMs; // sentence end → voice starts
  const Latency(this.hearMs, this.translateMs, this.totalMs);
}

class Exchange {
  final bool fromThem;
  final String original;
  final String translated;
  final String speakLocale;
  const Exchange(this.fromThem, this.original, this.translated, this.speakLocale);
}

/// Live conversation, no turn-guessing:
/// mic + voice detector (ours) → one sentence → Whisper (hears any language,
/// tells us which) → ML Kit → phone voice.
class Pipeline extends ChangeNotifier {
  final List<Language> others;
  Language other;
  Pipeline(this.others) : other = others.first;

  final Listener _listener = Listener();
  final Speaker _speaker = Speaker();
  SpeechToText? _stt;
  int _wavSeq = 0;

  Turn turn = Turn.listening;
  String status = 'Starting…';
  bool ready = false;
  bool speakMySide = true;
  bool speakerForThem = true;
  double level = 0;
  Latency? lastLatency;
  Exchange? last;
  final List<Exchange> history = [];
  String live = '';
  bool liveFromThem = false;
  bool expectThem = false; // kept for the UI tag; no longer drives listening

  StreamSubscription? _uttSub, _lvlSub;
  final _queue = <Float32List>[];
  bool _busy = false;
  bool _stopped = false;

  void _log(String m) => Diag.instance.log(m);

  Future<String> _vadPath() async {
    final dir = await getApplicationSupportDirectory();
    final f = File('${dir.path}/silero_vad.onnx');
    if (!await f.exists()) {
      final data = await rootBundle.load('assets/silero_vad.onnx');
      await f.writeAsBytes(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes), flush: true);
    }
    return f.path;
  }

  Future<void> start() async {
    final mm = ModelManager.instance;
    _log('pipeline start: languages=${others.map((l) => l.code).join(',')} (whisper small)');
    await WakelockPlus.enable();
    await _speaker.init();
    if (!NativeStt.isSupportedPlatform) {
      status = 'iPhone arrives in the next build';
      notifyListeners();
      return;
    }
    status = 'Warming up the ears…';
    notifyListeners();
    _stt = SpeechToText(
      modelPath: mm.filePath(ModelManager.earsFile),
      vadModelPath: await _vadPath(),
      threads: 6,
    );
    final tw = DateTime.now();
    final warmErr = await _stt!.warmUp(await ensureSilentWav(mm.modelsPath));
    _log('whisper warm in ${DateTime.now().difference(tw).inMilliseconds} ms${warmErr != null ? ' (note: $warmErr)' : ''}');
    await _listener.start(await _vadPath());
    _lvlSub = _listener.level.listen((p) {
      level = p;
      if (turn == Turn.listening && _listener.speaking) turn = Turn.talking;
      if (turn == Turn.talking && !_listener.speaking) turn = Turn.listening;
      notifyListeners();
    });
    _uttSub = _listener.utterances.listen((pcm) {
      _log('utterance: ${(pcm.length / Listener.sampleRate).toStringAsFixed(1)} s');
      _queue.add(pcm);
      _drain();
    });
    ready = true;
    status = 'Listening';
    _log('mic + voice detector live');
    notifyListeners();
  }

  Future<void> _drain() async {
    if (_busy) return;
    _busy = true;
    try {
      while (_queue.isNotEmpty && !_stopped) {
        await _handle(_queue.removeAt(0));
      }
    } finally {
      _busy = false;
    }
  }

  Uint8List _toPcm16(Float32List f) {
    final out = ByteData(f.length * 2);
    for (var i = 0; i < f.length; i++) {
      out.setInt16(i * 2, (f[i] * 32767).clamp(-32768, 32767).toInt(), Endian.little);
    }
    return out.buffer.asUint8List();
  }

  Future<void> _handle(Float32List pcm) async {
    final t0 = DateTime.now();
    turn = Turn.thinking;
    status = 'Hearing…';
    notifyListeners();

    final seconds = pcm.length / Listener.sampleRate;
    final path = '${ModelManager.instance.modelsPath}/utt_${_wavSeq++ % 4}.wav';
    await writeWav(pcm, path);
    Heard heard;
    try {
      heard = await _stt!.transcribe(path, seconds: seconds);
    } catch (e) {
      _log('ERROR whisper: $e');
      turn = Turn.listening;
      status = 'Listening';
      notifyListeners();
      return;
    }
    final t1 = DateTime.now();
    final text = SpeechToText.collapseRepeats(heard.text);
    _log('whisper (${heard.lang}): "$text" in ${t1.difference(t0).inMilliseconds} ms');
    if (SpeechToText.looksLikeNoise(text)) {
      _log('ignored as noise');
      turn = Turn.listening;
      status = 'Listening';
      notifyListeners();
      return;
    }
    // Direction: Whisper's language, checked against the languages in play.
    var fromThem = heard.lang != 'en';
    if (fromThem) {
      final match = others.where((l) => l.code == heard.lang || (heard.lang == 'no' && l.code == 'no'));
      if (match.isNotEmpty) {
        other = match.first;
      } else if (others.length == 1) {
        // Whisper heard a language we're not set up for — go by spelling.
        fromThem = !LangGuess.isEnglish(text, other);
        _log('note: whisper said ${heard.lang}; using spelling → ${fromThem ? other.code : 'en'}');
      } else {
        final d = LangGuess.detect(text, others);
        fromThem = d != null;
        if (d != null) other = d;
      }
    }
    final src = fromThem ? other.code : 'en';
    final tgt = fromThem ? 'en' : other.code;
    turn = fromThem ? Turn.them : Turn.you;
    expectThem = !fromThem;
    status = 'Translating…';
    last = Exchange(fromThem, text, '…', fromThem ? english.ttsLocale : other.ttsLocale);
    notifyListeners();

    String tr;
    try {
      tr = await ModelManager.instance.mlkit.translate(text, src, tgt);
      _log('translated ($src→$tgt): "$tr" in ${DateTime.now().difference(t1).inMilliseconds} ms');
    } catch (e) {
      _log('ERROR translate: $e');
      tr = '[translation error]';
    }
    final t2 = DateTime.now();
    last = Exchange(fromThem, text, tr, last!.speakLocale);
    history.add(last!);
    BookStore.instance.addHistory(Entry(
      time: DateTime.now().millisecondsSinceEpoch,
      fromThem: fromThem,
      original: text,
      translated: tr,
      speakLocale: last!.speakLocale,
      langCode: other.code,
    ));
    notifyListeners();

    if ((fromThem || speakMySide) && !tr.startsWith('[')) {
      lastLatency = Latency(t1.difference(t0).inMilliseconds, t2.difference(t1).inMilliseconds,
          DateTime.now().difference(t0).inMilliseconds);
      turn = Turn.speaking;
      status = fromThem ? 'In your ear…' : 'Speaking for you…';
      notifyListeners();
      _listener.muted = true; // don't hear ourselves
      final ts = DateTime.now();
      try {
        await _speaker.say(tr, last!.speakLocale, forceSpeaker: !fromThem && speakerForThem);
        _log('spoke (${last!.speakLocale}) for ${DateTime.now().difference(ts).inMilliseconds} ms');
      } catch (e) {
        _log('ERROR tts: $e');
      }
      _listener.muted = false;
    } else {
      lastLatency = Latency(t1.difference(t0).inMilliseconds, t2.difference(t1).inMilliseconds,
          t2.difference(t0).inMilliseconds);
    }
    turn = Turn.listening;
    status = 'Listening';
    notifyListeners();
  }

  /// Kept for the panel tap; with dual recognition there's nothing to force.
  Future<void> expect(bool them) async {}

  Future<void> replay() async {
    final e = last;
    if (e == null || e.translated.isEmpty || e.translated == '…') return;
    _listener.muted = true;
    await _speaker.say(e.translated, e.speakLocale, forceSpeaker: !e.fromThem && speakerForThem);
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
    await _stt?.dispose();
    await WakelockPlus.disable();
  }
}
