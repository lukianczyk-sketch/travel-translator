import 'package:flutter/services.dart';

/// On-device translation via Google ML Kit, called directly from our own
/// Android code (channel tt/mt). Models are ~30 MB per language and pivot
/// through English, so English + the other language must both be on the phone.
class MlkitTranslate {
  static const _m = MethodChannel('tt/mt');

  Future<bool> isDownloaded(String code) async =>
      await _m.invokeMethod<bool>('isDownloaded', {'code': code}) ?? false;

  Future<bool> download(String code) async =>
      await _m.invokeMethod<bool>('download', {'code': code}) ?? false;

  Future<bool> delete(String code) async => await _m.invokeMethod<bool>('delete', {'code': code}) ?? false;

  Future<String> translate(String text, String src, String tgt) async =>
      await _m.invokeMethod<String>('translate', {'text': text, 'src': src, 'tgt': tgt}) ?? '';

  // ---- OPUS-MT (Marian) engines running on ONNX Runtime in our own Android code ----
  Future<void> marianLoad(String key, String dir) async =>
      await _m.invokeMethod<bool>('marianLoad', {'key': key, 'dir': dir});

  Future<String> marianTranslate(String key, String text) async =>
      await _m.invokeMethod<String>('marianTranslate', {'key': key, 'text': text}) ?? '';

  Future<void> marianUnload(String key) async {
    try {
      await _m.invokeMethod('marianUnload', {'key': key});
    } catch (_) {}
  }

  /// Unpack a .tar.bz2 (flattening paths) into [dest]; returns the file count.
  Future<int> extractTarBz2(String path, String dest) async =>
      await _m.invokeMethod<int>('extractTarBz2', {'path': path, 'dest': dest}) ?? 0;

  Future<void> parakeetLoad(String dir) async => await _m.invokeMethod('parakeetLoad', {'dir': dir});
  Future<void> parakeetUnload() async {
    try {
      await _m.invokeMethod('parakeetUnload');
    } catch (_) {}
  }

  /// Returns {text, confidence, msFeatures, msEncoder, msDecode}.
  Future<Map> parakeetTranscribe(String wavPath) async =>
      await _m.invokeMethod<Map>('parakeetTranscribe', {'path': wavPath}) ?? const {};

  Future<void> dispose() async {}
}
