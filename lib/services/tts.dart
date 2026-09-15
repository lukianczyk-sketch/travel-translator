import 'dart:async';
import 'dart:io';

import 'package:flutter_tts/flutter_tts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'diag.dart';
import 'native_stt.dart';

/// Phone's built-in voices. Plays to whatever the phone is routed to
/// (earbuds if connected, otherwise the speaker).
class Speaker {
  final FlutterTts _tts = FlutterTts();
  Completer<void>? _done;
  bool _ready = false;

  double rate = 0.55; // a touch quicker than default, still clear

  /// 0..1. At 1.0 the phone's own volume is pushed to max while speaking.
  double earVolume = 1.0; // their side → your earbud / default output
  double speakerVolume = 1.0; // your side → phone speaker, for them

  Future<void> loadVolumes() async {
    final p = await SharedPreferences.getInstance();
    earVolume = p.getDouble('vol_ear') ?? 1.0;
    speakerVolume = p.getDouble('vol_speaker') ?? 1.0;
  }

  Future<void> saveVolumes() async {
    final p = await SharedPreferences.getInstance();
    await p.setDouble('vol_ear', earVolume);
    await p.setDouble('vol_speaker', speakerVolume);
  }

  Future<void> init() async {
    if (_ready) return;
    await loadVolumes();
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
    final vol = forceSpeaker ? speakerVolume : earVolume;
    if (NativeStt.isSupportedPlatform && await NativeStt.hasExternalOutput()) {
      // Earbuds/headset connected: play through our own player so each side
      // is pinned to the right device (yours → speaker, theirs → earbuds).
      final route = await _sayViaNative(text, vol, speaker: forceSpeaker);
      if (route != null) {
        Diag.instance.log('voice → ${forceSpeaker ? 'phone speaker' : 'earbuds'} ($route)');
        return;
      }
      Diag.instance.log('voice → ${forceSpeaker ? 'speaker' : 'earbud'} routing FAILED, using default output');
    }
    await _tts.setVolume(vol.clamp(0.05, 1.0));
    final boost = vol >= 0.99 && NativeStt.isSupportedPlatform;
    if (boost) await NativeStt.boost('media', true);
    _done = Completer<void>();
    try {
      await _tts.speak(text);
      await _done!.future.timeout(
        Duration(milliseconds: 1500 + text.length * 90),
        onTimeout: () {},
      );
    } finally {
      if (boost) await NativeStt.boost('media', false);
    }
  }

  Future<String?> _sayViaNative(String text, double vol, {required bool speaker}) async {
    try {
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/say_${DateTime.now().millisecondsSinceEpoch % 7}.wav';
      await _tts.awaitSynthCompletion(true);
      await _tts.setVolume(1.0);
      final r = await _tts.synthesizeToFile(text, path, true);
      if (r != 1) {
        Diag.instance.log('voice: synthesizeToFile returned $r');
        return null;
      }
      return await NativeStt.play(path, speaker: speaker, volume: vol);
    } catch (e) {
      Diag.instance.log('voice: speaker path error $e');
      return null;
    }
  }

  Future<void> stop() async {
    await _tts.stop();
    await NativeStt.stopPlay();
    _finish();
  }
}
