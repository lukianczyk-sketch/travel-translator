import 'dart:async';
import 'dart:io';

import 'package:flutter_tts/flutter_tts.dart';
import 'package:path_provider/path_provider.dart';

import 'native_stt.dart';

/// Phone's built-in voices. Plays to whatever the phone is routed to
/// (earbuds if connected, otherwise the speaker).
class Speaker {
  final FlutterTts _tts = FlutterTts();
  Completer<void>? _done;
  bool _ready = false;

  double rate = 0.55; // a touch quicker than default, still clear

  Future<void> init() async {
    if (_ready) return;
    if (Platform.isIOS) {
      await _tts.setSharedInstance(true);
      await _tts.setIosAudioCategory(
        IosTextToSpeechAudioCategory.playAndRecord,
        [
          IosTextToSpeechAudioCategoryOptions.defaultToSpeaker,
          IosTextToSpeechAudioCategoryOptions.allowBluetooth,
          IosTextToSpeechAudioCategoryOptions.allowBluetoothA2DP,
          IosTextToSpeechAudioCategoryOptions.mixWithOthers,
        ],
        IosTextToSpeechAudioMode.spokenAudio,
      );
    }
    await _tts.awaitSpeakCompletion(true);
    await _tts.setSpeechRate(rate);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
    _tts.setCompletionHandler(() => _finish());
    _tts.setCancelHandler(() => _finish());
    _tts.setErrorHandler((_) => _finish());
    _ready = true;
  }

  void _finish() {
    final d = _done;
    if (d != null && !d.isCompleted) d.complete();
  }

  Future<bool> hasVoice(String locale) async {
    try {
      final r = await _tts.isLanguageAvailable(locale);
      return r == true || r == 1;
    } catch (_) {
      return false;
    }
  }

  /// Speaks and completes when playback has finished.
  /// [forceSpeaker] plays through the phone speaker even with earbuds
  /// connected (Android) — for the other person to hear.
  Future<void> say(String text, String locale, {bool forceSpeaker = false}) async {
    if (text.trim().isEmpty) return;
    await init();
    await _tts.setLanguage(locale);
    if (forceSpeaker && NativeStt.isSupportedPlatform) {
      final ok = await _sayViaSpeaker(text);
      if (ok) return;
    }
    _done = Completer<void>();
    await _tts.speak(text);
    await _done!.future.timeout(
      Duration(milliseconds: 1500 + text.length * 90),
      onTimeout: () {},
    );
  }

  Future<bool> _sayViaSpeaker(String text) async {
    try {
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/say_${DateTime.now().millisecondsSinceEpoch % 7}.wav';
      await _tts.awaitSynthCompletion(true);
      final r = await _tts.synthesizeToFile(text, path, true);
      if (r != 1) return false;
      return await NativeStt.play(path, speaker: true);
    } catch (_) {
      return false;
    }
  }

  Future<void> stop() async {
    await _tts.stop();
    await NativeStt.stopPlay();
    _finish();
  }
}
