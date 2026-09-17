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

  static bool _same(String a, String b) {
    String n(String s) => s.toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), '');
    return n(a) == n(b);
  }

  static bool _looksLikeNameOrNumber(String t) {
    final w = t.trim();
    if (RegExp(r'^\W*\d').hasMatch(w)) return true;
    // Single capitalised word that isn't sentence-initial noise — likely a name; leave it.
    return RegExp(r'^[A-Z][a-z]+$').hasMatch(w.replaceAll(RegExp(r'[^\p{L}]', unicode: true), '')) && w.split(' ').length == 1 && !w.endsWith('.');
  }

  /// True if the text's alphabet belongs to English or one of the languages in play.
  bool _scriptFits(String text) {
    final cyr = RegExp(r'[\u0400-\u04FF]').hasMatch(text);
    if (cyr && !others.any((l) => const {'ru', 'uk', 'bg', 'sr', 'mk', 'be'}.contains(l.code))) return false;
    final greek = RegExp(r'[\u0370-\u03FF]').hasMatch(text);
    if (greek && !others.any((l) => l.code == 'el')) return false;
    final cjk = RegExp(r'[\u3040-\u30FF\u4E00-\u9FFF]').hasMatch(text);
    if (cjk && !others.any((l) => const {'ja', 'zh', 'ko'}.contains(l.code))) return false;
    return true;
  }

  /// Volume test: their side into the earpiece (English), or your side out the phone speaker (their language).
  Future<void> testVoice({required bool earpiece}) async {
    _listener.muted = true; // don't translate our own test phrase
    try {
      if (earpiece) {
        await _speaker.test(speaker: false, locale: english.ttsLocale, phrase: 'Testing your earpiece. This is how they will sound.');
      } else {
        await _speaker.test(speaker: speakerForThem, locale: other.ttsLocale, phrase: 'Test. Test. Test.');
      }
    } finally {
      _listener.muted = false;
    }
  }
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

  /// True when the fast ears (Parakeet) are on and cover every language in play.
  bool _parakeet = false;
  String _lastLang = '';
  int _pendingSpeech = 0;

  Future<void> start() async {
    final mm = ModelManager.instance;
    _parakeet = mm.activeFastEars && others.every((l) => ModelManager.fastEarsLangs.contains(l.code));
    _log('pipeline start: languages=${others.map((l) => l.code).join(',')} (${_parakeet ? 'Parakeet TDT 0.6B v3' : '${mm.activeEarsName}, ${mm.activeEarsPlus ? 'single pass' : 'decode in every language'}'})');
    await WakelockPlus.enable();
    await _speaker.init();
    if (!NativeStt.isSupportedPlatform) {
      status = 'iPhone arrives in the next build';
      notifyListeners();
      return;
    }
    status = 'Warming up the ears…';
    notifyListeners();
    if (_parakeet) {
      final tw = DateTime.now();
      try {
        await mm.mlkit.parakeetLoad(mm.fastEarsPath);
        _log('parakeet loaded in ${DateTime.now().difference(tw).inMilliseconds} ms');
      } catch (e) {
        _log('ERROR parakeet failed to load ($e) — falling back to Whisper');
        _parakeet = false;
      }
    }
    if (!_parakeet) {
      _stt = SpeechToText(
        modelPath: mm.filePath(mm.activeEarsFile),
        vadModelPath: await _vadPath(),
        threads: 6,
        singlePass: mm.activeEarsPlus,
      );
      final tw = DateTime.now();
      final warmErr = await _stt!.warmUp(await ensureSilentWav(mm.modelsPath));
      _log('whisper warm in ${DateTime.now().difference(tw).inMilliseconds} ms${warmErr != null ? ' (note: $warmErr)' : ''}');
    }
    if (mm.activeBrainPlus && others.any((l) => l.code == 'pl')) {
      final tb = DateTime.now();
      try {
        await mm.mlkit.marianLoad('pl>en', mm.brainPlusPath);
        _log('brain: opus-mt pl→en loaded in ${DateTime.now().difference(tb).inMilliseconds} ms');
      } catch (e) {
        _log('ERROR brain: opus-mt failed to load ($e) — using ML Kit for pl→en');
      }
    }
    _earbudsOn = NativeStt.isSupportedPlatform && await NativeStt.hasExternalOutput();
    _log('earbuds/headset connected: $_earbudsOn');
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
        var pcm = _queue.removeAt(0);
        // Fell behind? Merge what's waiting into one clip (up to ~8 s) so one
        // decode catches up instead of the backlog snowballing.
        while (_queue.isNotEmpty && (pcm.length + _queue.first.length) <= Listener.sampleRate * 8) {
          final next = _queue.removeAt(0);
          final merged = Float32List(pcm.length + next.length);
          merged.setAll(0, pcm);
          merged.setAll(pcm.length, next);
          pcm = merged;
          _log('backlog: merged the next clip (now ${(pcm.length / Listener.sampleRate).toStringAsFixed(1)} s)');
        }
        await _handle(pcm);
      }
    } finally {
      _busy = false;
    }
  }

  Future<void> _speakChain = Future.value();
  bool _earbudsOn = false;

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
      if (_parakeet) {
        final r = await ModelManager.instance.mlkit.parakeetTranscribe(path);
        final text = (r['text'] as String? ?? '').trim();
        final conf = (r['confidence'] as num?)?.toDouble() ?? 0.0;
        // Parakeet hears 25 languages in one pass but doesn't say which — spelling
        // settles it; with no evidence either way, stay with the last sentence's language.
        String lang;
        if (others.length == 1) {
          final en = LangGuess.isEnglishOrUnknown(text, others.first);
          if (en == null) {
            lang = _lastLang.isEmpty ? 'en' : _lastLang;
            _log('language unclear from spelling — staying with $lang');
          } else {
            lang = en ? 'en' : others.first.code;
          }
        } else {
          lang = LangGuess.detect(text, others)?.code ?? (_lastLang.isEmpty ? 'en' : _lastLang);
        }
        heard = Heard(text, lang, null, conf > 0 ? math.log(conf) : null, null, const []);
        _log('parakeet timing: features ${r['msFeatures']} ms, encoder ${r['msEncoder']} ms, decode ${r['msDecode']} ms');
      } else {
        heard = await _stt!.transcribe(path, seconds: seconds, allowedLangs: ['en', ...others.map((l) => l.code)]);
      }
    } catch (e) {
      _log('ERROR ears: $e');
      turn = Turn.listening;
      status = 'Listening';
      notifyListeners();
      return;
    }
    if (_stopped) {
      _log('decode finished after stop — dropped');
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
    _log('${_parakeet ? 'parakeet' : 'whisper'} (${heard.lang} ${conf}%${heard.margin != null ? ', margin ${heard.margin!.toStringAsFixed(2)}' : ''}): "$text" in ${t1.difference(t0).inMilliseconds} ms');
    if (heard.candidates.length > 1) {
      _log('  decodes${heard.candidates.length > 1 && mmActive.activeEarsPlus ? ' (second look)' : ''}: ${heard.candidates.map((c) => '${c.lang} ${(math.exp(c.logprob) * 100).toStringAsFixed(0)}% "${SpeechToText.collapseRepeats(c.text)}"').join(' | ')}');
    }
    if (SpeechToText.looksHallucinated(text)) {
      _log('ignored (hallucination pattern)');
      turn = Turn.listening;
      status = 'Listening';
      notifyListeners();
      return;
    }
    if (SpeechToText.looksLikeNoise(text) || SpeechToText.isFragment(text, heard.confidence)) {
      _log('ignored (noise/fragment)');
      turn = Turn.listening;
      status = 'Listening';
      notifyListeners();
      return;
    }
    // Never speak a guess: below this the words are more likely wrong than right.
    // One- or two-word results need to be surer still (they're usually shouts and half-words).
    final wordCount = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
    var needed = wordCount <= 2 ? 0.55 : minConfidence;
    // A phrasebook match ("Dzień dobry", "dziękuję") is a known phrase — let it through at a lower bar.
    final guessSrc = heard.lang != 'en' ? heard.lang : 'en';
    final guessTgt = guessSrc == 'en' ? (others.isNotEmpty ? others.first.code : 'en') : 'en';
    if (Glossary.lookup(text, guessSrc, guessTgt) != null) needed = 0.30;
    if (heard.confidence < needed) {
      _log('not sure enough (${conf}% < ${(needed * 100).round()}%) — not speaking it');
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
    // Wrong alphabet for the languages in play (e.g. a Cyrillic guess) → drop it.
    if (!_scriptFits(text)) {
      _log('ignored (script not in play): "$text"');
      turn = Turn.listening;
      status = 'Listening';
      notifyListeners();
      return;
    }
    var src = fromThem ? other.code : 'en';
    var tgt = fromThem ? 'en' : other.code;
    // "English" that the translator hands back unchanged wasn't English (a lone
    // Polish word without accents). Flip it to their language.
    if (!fromThem && others.length == 1 && !_looksLikeNameOrNumber(text)) {
      try {
        final probe = await ModelManager.instance.mlkit.translate(text, 'en', other.code);
        if (_same(probe, text)) {
          _log('"$text" unchanged by en→${other.code} — treating it as ${other.code}');
          fromThem = true;
          src = other.code;
          tgt = 'en';
        }
      } catch (_) {}
    }
    _stt?.prevLang = src; // a sentence we're about to act on — remember its language
    _lastLang = src;
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
        final mm = ModelManager.instance;
        var engine = 'mlkit';
        if (mm.activeBrainPlus && src == 'pl' && tgt == 'en') {
          try {
            tr = await mm.mlkit.marianTranslate('pl>en', text);
            engine = 'opus-mt';
          } catch (e) {
            _log('ERROR opus-mt: $e — falling back to ML Kit');
            tr = await mm.mlkit.translate(text, src, tgt);
          }
        } else {
          tr = await mm.mlkit.translate(text, src, tgt);
        }
        if (src == 'pl') {
          final notes = Glossary.foodNotes(text, tr);
          if (notes.isNotEmpty) {
            tr = '$tr$notes';
            _log('food glossary added$notes');
          }
        }
        _log('translated ($src→$tgt, $engine): "$tr" in ${DateTime.now().difference(t1).inMilliseconds} ms');
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
      final locale = last!.speakLocale;
      final toSpeaker = !fromThem && speakerForThem;
      // Their side going into your earbuds can't be heard by the mic, so keep
      // listening and let the next clip decode while this one is still playing.
      final privateRoute = fromThem && _earbudsOn;
      final ts = DateTime.now();
      _pendingSpeech++;
      final myTicket = _pendingSpeech;
      _speakChain = _speakChain.then((_) async {
        if (_stopped) return;
        // Fell more than two lines behind in your ear? Skip the stale ones (they stay on screen).
        if (privateRoute && _pendingSpeech - myTicket >= 2) {
          _log('speech backlog — skipped a stale line');
          return;
        }
        if (!privateRoute) _listener.muted = true; // don't hear ourselves
        try {
          await _speaker.say(tr, locale, forceSpeaker: toSpeaker);
          _log('spoke ($locale) for ${DateTime.now().difference(ts).inMilliseconds} ms${privateRoute ? ' (mic stayed open)' : ''}');
        } catch (e) {
          _log('ERROR tts: $e');
        } finally {
          if (!privateRoute) _listener.muted = false;
        }
      });
      if (!privateRoute) await _speakChain;
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
    try { await _speakChain.timeout(const Duration(seconds: 2)); } catch (_) {}
    await _uttSub?.cancel();
    await _lvlSub?.cancel();
    await _listener.stop();
    _listener.dispose();
    await _speaker.stop();
    await _stt?.dispose();
    await ModelManager.instance.mlkit.marianUnload('pl>en');
    if (_parakeet) await ModelManager.instance.mlkit.parakeetUnload();
    await WakelockPlus.disable();
  }
}
