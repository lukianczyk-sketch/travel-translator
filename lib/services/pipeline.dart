import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models/language.dart';
import 'book_store.dart';
import 'diag.dart';
import 'lang_guess.dart';
import 'model_manager.dart';
import 'native_stt.dart';
import 'tts.dart';

enum Turn { listening, talking, them, you, thinking, speaking }

class Latency {
  final int translateMs; // final text → translation
  final int totalMs; // final text → voice starts
  const Latency(this.translateMs, this.totalMs);
}

class Exchange {
  final bool fromThem;
  final String original;
  final String translated;
  final String speakLocale;
  const Exchange(this.fromThem, this.original, this.translated, this.speakLocale);
}

/// Live conversation: phone recognizer (streaming) → ML Kit → phone voice.
class Pipeline extends ChangeNotifier {
  final List<Language> others;
  Language other;
  Pipeline(this.others) : other = others.first;

  final Speaker _speaker = Speaker();
  StreamSubscription? _sub;

  Turn turn = Turn.listening;
  String status = 'Starting…';
  bool ready = false;
  bool speakMySide = true;

  /// Your side out the phone speaker (for them) even when earbuds are in.
  bool speakerForThem = true;
  double level = 0;
  Latency? lastLatency;
  Exchange? last;
  final List<Exchange> history = [];

  /// Words arriving while someone is still talking.
  String live = '';
  bool liveFromThem = false;
  String? _detectedLocale;
  final _queue = <String>[];
  bool _busy = false;
  bool _stopped = false;
  bool _speaking = false;

  void _log(String m) => Diag.instance.log(m);

  Future<void> start() async {
    final mm = ModelManager.instance;
    _log('pipeline start: languages=${others.map((l) => l.code).join(',')}');
    await WakelockPlus.enable();
    await _speaker.init();
    if (!NativeStt.isSupportedPlatform) {
      status = 'iPhone ears arrive in the next build';
      notifyListeners();
      return;
    }
    _sub = NativeStt.events.listen(_onEvent);
    final langs = ['en-US', ...others.map((l) => l.ttsLocale)];
    await NativeStt.start(langs, others.first.ttsLocale);
    if (!mm.speechAvailable) _log('note: on-device recognizer not reported available; using system recognizer');
    ready = true;
    status = 'Listening';
    notifyListeners();
  }

  void _onEvent(SttEvent e) {
    switch (e.type) {
      case 'rms':
        final v = (e.data['value'] as num).toDouble(); // roughly -2..10 dB
        level = ((v + 2) / 12).clamp(0.0, 1.0);
        notifyListeners();
      case 'speech':
        if (_speaking) return;
        final on = e.data['on'] == true;
        if (on && turn == Turn.listening) turn = Turn.talking;
        if (!on && turn == Turn.talking) turn = Turn.listening;
        notifyListeners();
      case 'lang':
        _detectedLocale = e.lang;
        _log('recognizer detected language: ${e.lang} (conf ${e.data['confidence']}, switch ${e.data['switch']})');
      case 'partial':
        if (_speaking) return;
        live = e.text ?? '';
        liveFromThem = _isFromThem(live, e.lang);
        if (turn == Turn.listening) turn = Turn.talking;
        notifyListeners();
      case 'final':
        if (_speaking) return;
        final t = (e.text ?? '').trim();
        _log('heard: "$t" (lang ${e.lang ?? _detectedLocale ?? '?'})');
        live = '';
        if (t.isNotEmpty) {
          _queue.add(t);
          _drain();
        }
      case 'error':
        _log('ERROR recognizer: ${e.data['message']}');
        status = 'Ears: ${e.data['message']}';
        notifyListeners();
      case 'status':
        break;
    }
  }

  bool _isFromThem(String text, String? locale) {
    final loc = (locale ?? _detectedLocale ?? '').toLowerCase();
    if (loc.isNotEmpty) {
      if (loc.startsWith('en')) return false;
      final code = loc.split('-').first;
      final match = others.where((l) => l.code == code || l.ttsLocale.toLowerCase().startsWith(code));
      if (match.isNotEmpty) {
        other = match.first;
        return true;
      }
    }
    final detected = others.length == 1
        ? (LangGuess.isEnglish(text, other) ? null : other)
        : LangGuess.detect(text, others);
    if (detected != null) other = detected;
    return detected != null;
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

  Future<void> _handle(String text) async {
    final t0 = DateTime.now();
    final fromThem = _isFromThem(text, _detectedLocale);
    _detectedLocale = null;
    final src = fromThem ? other.code : 'en';
    final tgt = fromThem ? 'en' : other.code;
    turn = fromThem ? Turn.them : Turn.you;
    status = 'Translating…';
    last = Exchange(fromThem, text, '…', fromThem ? english.ttsLocale : other.ttsLocale);
    notifyListeners();

    String tr;
    try {
      tr = await ModelManager.instance.mlkit.translate(text, src, tgt);
      _log('translated ($src→$tgt): "$tr" in ${DateTime.now().difference(t0).inMilliseconds} ms');
    } catch (e) {
      _log('ERROR translate: $e');
      tr = '[translation error]';
    }
    final t1 = DateTime.now();
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
      lastLatency = Latency(t1.difference(t0).inMilliseconds, DateTime.now().difference(t0).inMilliseconds);
      turn = Turn.speaking;
      status = fromThem ? 'In your ear…' : 'Speaking for you…';
      notifyListeners();
      _speaking = true;
      await NativeStt.pause(); // don't hear ourselves
      try {
        await _speaker.say(tr, last!.speakLocale, forceSpeaker: !fromThem && speakerForThem);
      } catch (e) {
        _log('ERROR tts: $e');
      }
      _speaking = false;
      if (!_stopped) await NativeStt.resume();
    } else {
      lastLatency = Latency(t1.difference(t0).inMilliseconds, t1.difference(t0).inMilliseconds);
    }
    turn = Turn.listening;
    status = 'Listening';
    notifyListeners();
  }

  Future<void> replay() async {
    final e = last;
    if (e == null || e.translated.isEmpty || e.translated == '…') return;
    _speaking = true;
    await NativeStt.pause();
    await _speaker.say(e.translated, e.speakLocale, forceSpeaker: !e.fromThem && speakerForThem);
    _speaking = false;
    if (!_stopped) await NativeStt.resume();
  }

  Future<void> stop() async {
    _log('pipeline stop');
    _stopped = true;
    await _sub?.cancel();
    if (NativeStt.isSupportedPlatform) await NativeStt.stop();
    await _speaker.stop();
    await WakelockPlus.disable();
  }
}
