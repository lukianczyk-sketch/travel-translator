import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';

/// Event from the phone's on-device recognizer.
class SttEvent {
  final String type; // partial | final | lang | speech | rms | status | error | download
  final Map<dynamic, dynamic> data;
  const SttEvent(this.type, this.data);
  String? get text => data['text'] as String?;
  String? get lang => data['lang'] as String?;
}

/// Streaming speech recognition using the phone's own on-device engine
/// (Android: Google/Samsung speech services; words arrive as they're spoken).
class NativeStt {
  static const _m = MethodChannel('tt/stt');
  static const _e = EventChannel('tt/stt/events');
  static Stream<SttEvent>? _stream;

  static bool get isSupportedPlatform => Platform.isAndroid;

  static Stream<SttEvent> get events {
    _stream ??= _e.receiveBroadcastStream().map((e) {
      final m = e as Map<dynamic, dynamic>;
      return SttEvent(m['type'] as String, m);
    });
    return _stream!;
  }

  static Future<bool> available() async {
    if (!isSupportedPlatform) return false;
    try {
      return await _m.invokeMethod<bool>('available') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<int> sdk() async {
    try {
      return await _m.invokeMethod<int>('sdk') ?? 0;
    } catch (_) {
      return 0;
    }
  }

  static Future<void> start(List<String> languages, String primary) =>
      _m.invokeMethod('start', {'languages': languages, 'primary': primary});
  static Future<void> pause() => _m.invokeMethod('pause');
  static Future<void> resume({String? primary}) => _m.invokeMethod('resume', {'primary': primary});
  static Future<void> stop() => _m.invokeMethod('stop');

  /// Which speech language packs are installed / downloadable on this phone.
  static Future<Map<String, dynamic>> checkSupport(List<String> languages) async {
    try {
      final r = await _m.invokeMethod<Map<dynamic, dynamic>>('checkSupport', {'languages': languages});
      return r?.map((k, v) => MapEntry(k.toString(), v)) ?? {'supported': false};
    } catch (e) {
      return {'supported': false, 'error': e.toString()};
    }
  }

  /// Recognize one utterance (16 kHz mono PCM16 bytes) in each of [languages];
  /// returns the most confident result: {text, lang, confidence} or null.
  static Future<Map<String, dynamic>?> recognizeAudio(Uint8List pcm, List<String> languages) async {
    final r = await _m.invokeMethod<Map<dynamic, dynamic>>('recognizeAudio', {'pcm': pcm, 'languages': languages});
    if (r == null) return null;
    final all = (r['all'] as List?)?.map((e) => (e as Map).map((k, v) => MapEntry(k.toString(), v))).toList();
    final best = r['best'] as Map?;
    return {
      'best': best?.map((k, v) => MapEntry(k.toString(), v)),
      'all': all,
    };
  }

  static Future<bool> hasExternalOutput() async {
    try {
      return await _m.invokeMethod<bool>('hasExternalOutput') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<String> logcat() async {
    try {
      return await _m.invokeMethod<String>('logcat') ?? '';
    } catch (e) {
      return 'logcat unavailable: $e';
    }
  }

  /// Play a synthesized file; speaker=true forces the phone speaker even with
  /// earbuds. Returns the route taken, or null if playback failed.
  static Future<String?> play(String path, {required bool speaker, double volume = 1.0}) async {
    try {
      final r = await _m.invokeMethod<Map>('play', {'path': path, 'speaker': speaker, 'volume': volume});
      if (r == null || r['ok'] != true) return null;
      return r['route']?.toString() ?? 'ok';
    } catch (e) {
      return null;
    }
  }

  /// Set a phone volume stream ('media' or 'call') to a fraction of its maximum.
  static Future<void> setLevel(String stream, double fraction) async {
    try {
      await _m.invokeMethod('setLevel', {'stream': stream, 'fraction': fraction});
    } catch (_) {}
  }

  static Future<void> stopPlay() async {
    try {
      await _m.invokeMethod('stopPlay');
    } catch (_) {}
  }

  static Future<bool> download(String language) async {
    try {
      return await _m.invokeMethod<bool>('download', {'language': language}) ?? false;
    } catch (_) {
      return false;
    }
  }
}
