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

  Future<void> dispose() async {}
}
