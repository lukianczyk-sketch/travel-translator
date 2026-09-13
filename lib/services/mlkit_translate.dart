import 'package:google_mlkit_translation/google_mlkit_translation.dart';

/// On-device translation via ML Kit. Models are ~30 MB per language and go
/// through English, so English + the other language must both be on the phone.
class MlkitTranslate {
  final _manager = OnDeviceTranslatorModelManager();
  final Map<String, OnDeviceTranslator> _translators = {};

  static TranslateLanguage? lang(String bcp) => BCP47Code.fromRawValue(bcp);

  Future<bool> isDownloaded(String bcp) => _manager.isModelDownloaded(bcp);

  Future<bool> download(String bcp) => _manager.downloadModel(bcp, isWifiRequired: false);

  Future<bool> delete(String bcp) => _manager.deleteModel(bcp);

  Future<String> translate(String text, String srcBcp, String tgtBcp) async {
    final key = '$srcBcp>$tgtBcp';
    var t = _translators[key];
    if (t == null) {
      final s = lang(srcBcp);
      final d = lang(tgtBcp);
      if (s == null || d == null) throw StateError('Unsupported language $srcBcp/$tgtBcp');
      t = OnDeviceTranslator(sourceLanguage: s, targetLanguage: d);
      _translators[key] = t;
    }
    return t.translateText(text);
  }

  Future<void> dispose() async {
    for (final t in _translators.values) {
      await t.close();
    }
    _translators.clear();
  }
}
