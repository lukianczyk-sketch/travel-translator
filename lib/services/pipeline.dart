import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models/language.dart';
import 'book_store.dart';
import 'diag.dart';
import 'glossary.dart';
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
  Speaker get speaker => _speaker;
  SpeechToText? _stt;
  int _wavSeq = 0;

  /// Words below this confidence are shown as "didn't catch that", never spoken.
  static const minConfidence = 0.35;

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
  ModelManager get mmActive => ModelManager.instance;

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
    _log('pipeline start: languages=${others.map((l) => l.code).join(',')} (${mm.activeEarsName}, ${mm.activeEarsPlus ? 'single pass' : 'decode in every language'})');
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
      modelPath: mm.filePath(mm.activeEarsFile),
      vadModelPath: await _vadPath(),
      threads: 6,
      singlePass: mm.activeEarsPlus,
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
      heard = await _stt!.transcribe(path, seconds: seconds, allowedLangs: ['en', ...others.map((l) => l.code)]);
    } catch (e) {
      _log('ERROR whisper: $e');
      turn = Turn.listening;
      status = 'Listening';
      notifyListeners();
      return;
    }
    final t1 = DateTime.now();
    // The winning decode may be a bracketed "[blank]" tag that cleans to
    // nothing — if so, fall back to the best decode that has real words.
    if (heard.candidates.length > 1) {
      final live = heard.candidates.where((c) => !SpeechToText.looksLikeNoise(SpeechToText.collapseRepeats(c.text))).toList();
      if (live.isNotEmpty) {
        live.sort((a, b) => b.score.compareTo(a.score));
        if (live.first.lang != heard.lang || live.first.text != heard.text) {
          _log('  winner "${heard.text}" cleans to nothing → using ${live.first.lang} decode');
          heard = Heard(live.first.text, live.first.lang, heard.langProb, live.first.logprob,
              live.length > 1 ? live.first.score - live[1].score : heard.margin, heard.candidates);
        }
      }
    }
    final text = SpeechToText.collapseRepeats(heard.text);
    final conf = (heard.confidence * 100).toStringAsFixed(0);
    _log('whisper (${heard.lang} ${conf}%${heard.margin != null ? ', margin ${heard.margin!.toStringAsFixed(2)}' : ''}): "$text" in ${t1.difference(t0).inMilliseconds} ms');
    if (heard.candidates.length > 1) {
      _log('  decodes${heard.candidates.length > 1 && mmActive.activeEarsPlus ? ' (second look)' : ''}: ${heard.candidates.map((c) => '${c.lang} ${(math.exp(c.logprob) * 100).toStringAsFixed(0)}% "${SpeechToText.collapseRepeats(c.text)}"').join(' | ')}');
    }
    if (SpeechToText.looksLikeNoise(text) || SpeechToText.isFragment(text, heard.confidence)) {
      _log('ignored (noise/fragment)');
      turn = Turn.listening;
      status = 'Listening';
      notifyListeners();
      return;
    }
    // Never speak a guess: below this the words are more likely wrong than right.
    if (heard.confidence < minConfidence) {
      _log('not sure enough (${conf}%) — not speaking it');
      final guessFromThem = heard.lang != 'en';
      last = Exchange(guessFromThem, text, "Didn't catch that — say it again?", guessFromThem ? english.ttsLocale : other.ttsLocale);
      turn = Turn.listening;
      status = "Didn't catch that";
      notifyListeners();
      return;
    }
    // Direction: the sentence was decoded in every language in play and the
    // most confident decode won — that decode's language IS the direction.
    var fromThem = heard.lang != 'en';
    if (fromThem) {
      final match = others.where((l) => l.code == heard.lang);
      if (match.isNotEmpty) {
        other = match.first;
      } else if (others.length == 1) {
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
      final fixed = Glossary.lookup(text, src, tgt);
      if (fixed != null) {
        tr = fixed;
        _log('phrasebook ($src→$tgt): "$tr"');
      } else {
        tr = await ModelManager.instance.mlkit.translate(text, src, tgt);
        _log('translated ($src→$tgt): "$tr" in ${DateTime.now().difference(t1).inMilliseconds} ms');
      }
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
