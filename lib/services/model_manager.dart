import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/language.dart';
import 'diag.dart';
import 'mlkit_translate.dart';
import 'native_stt.dart';

enum LangState { missing, downloading, ready }

class LangStatus {
  bool ears = false; // speech pack on the phone
  bool brain = false; // ML Kit translation model on the phone
  bool downloading = false;
  int earsPercent = 0;
  String? error;
  LangState get state => downloading
      ? LangState.downloading
      : (ears && brain ? LangState.ready : LangState.missing);
}

/// What's installed on the phone, per language. Both engines are the phone's
/// own (Google speech packs + ML Kit translation models), all free + offline.
class ModelManager extends ChangeNotifier {
  ModelManager._();
  static final ModelManager instance = ModelManager._();

  final MlkitTranslate mlkit = MlkitTranslate();
  final Map<String, LangStatus> _status = {for (final l in travelLanguages) l.code: LangStatus()};
  final Set<String> _chosen = {};
  bool englishBrain = false;
  bool englishEars = true;
  bool speechAvailable = false;
  bool canCheckEars = false;
  int sdk = 0;
  StreamSubscription? _evSub;

  // ---- Ears: Whisper small (fast) and large-v3-turbo (sharp), one file for every language ----
  static const earsUrl = 'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small-q8_0.bin';
  static const earsFile = 'ggml-small-q8_0.bin';
  static const earsMb = 264;
  static const earsPlusUrl = 'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q5_0.bin';
  static const earsPlusFile = 'ggml-large-v3-turbo-q5_0.bin';
  static const earsPlusMb = 547;
  bool earsReady = false;
  bool earsDownloading = false;
  double earsProgress = 0;
  String? earsError;
  bool earsPlusReady = false;
  bool earsPlusDownloading = false;
  double earsPlusProgress = 0;
  String? earsPlusError;
  bool useEarsPlus = false; // user's choice; only honoured when the pack is on the phone
  String modelsPath = '';
  final Dio _dio = Dio();
  CancelToken? _earsCancel;
  CancelToken? _earsPlusCancel;

  /// The ears pack the conversation will actually use.
  bool get activeEarsPlus => useEarsPlus && earsPlusReady;
  String get activeEarsFile => activeEarsPlus ? earsPlusFile : earsFile;
  String get activeEarsName => activeEarsPlus ? 'Whisper large-v3-turbo' : 'Whisper small';

  Future<void> setUseEarsPlus(bool v) async {
    useEarsPlus = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('ears_plus', v);
    notifyListeners();
  }

  String filePath(String name) => '$modelsPath/$name';

  LangStatus status(String code) => _status[code]!;
  bool isChosen(String code) => _chosen.contains(code);
  List<Language> get chosenLanguages => travelLanguages.where((l) => _chosen.contains(l.code)).toList();
  List<Language> get readyLanguages =>
      chosenLanguages.where((l) => status(l.code).state == LangState.ready).toList();
  bool get anyReady => readyLanguages.isNotEmpty && englishBrain && earsReady;

  Future<void> init() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/models');
    if (!await dir.exists()) await dir.create(recursive: true);
    modelsPath = dir.path;
    final ef = File(filePath(earsFile));
    earsReady = await ef.exists() && await ef.length() > earsMb * 1000 * 1000 * 0.6;
    final epf = File(filePath(earsPlusFile));
    earsPlusReady = await epf.exists() && await epf.length() > earsPlusMb * 1000 * 1000 * 0.6;
    final prefs = await SharedPreferences.getInstance();
    useEarsPlus = prefs.getBool('ears_plus') ?? false;
    _chosen.addAll(prefs.getStringList('langs') ?? const []);
    speechAvailable = await NativeStt.available();
    sdk = await NativeStt.sdk();
    canCheckEars = speechAvailable && sdk >= 33;
    Diag.instance.log('speech: available=$speechAvailable sdk=$sdk');
    if (NativeStt.isSupportedPlatform) {
      _evSub ??= NativeStt.events.listen(_onEvent);
    }
    await refresh();
  }

  /// Re-check what's on the phone.
  Future<void> refresh() async {
    try {
      englishBrain = await mlkit.isDownloaded('en');
      for (final l in travelLanguages) {
        _status[l.code]!.brain = await mlkit.isDownloaded(l.code);
      }
    } catch (e) {
      Diag.instance.log('ERROR mlkit check: $e');
    }
    for (final l in travelLanguages) {
      _status[l.code]!.ears = earsReady;
    }
    if (false && canCheckEars) {
      final r = await NativeStt.checkSupport([...travelLanguages.map((l) => l.ttsLocale), 'en-US']);
      final installed = ((r['installed'] as List?) ?? const []).map((e) => e.toString().toLowerCase()).toList();
      final online = ((r['online'] as List?) ?? const []).map((e) => e.toString().toLowerCase()).toList();
      Diag.instance.log('speech packs installed: $installed');
      bool has(String locale) {
        final lc = locale.toLowerCase();
        final short = lc.split('-').first;
        return installed.any((i) => i == lc || i.split('-').first == short);
      }
      englishEars = has('en-US') || installed.isEmpty && online.isNotEmpty;
      for (final l in travelLanguages) {
        _status[l.code]!.ears = has(l.ttsLocale);
      }
    }
    notifyListeners();
  }

  Future<void> downloadEars() async {
    if (earsDownloading) return;
    earsDownloading = true;
    earsError = null;
    earsProgress = 0;
    notifyListeners();
    _earsCancel = CancelToken();
    final err = await _fetch(earsUrl, filePath(earsFile), _earsCancel!, (p) {
      earsProgress = p;
      notifyListeners();
    });
    earsError = err;
    if (err == null) {
      earsReady = true;
      Diag.instance.log('ears: whisper small downloaded');
    }
    earsDownloading = false;
    _earsCancel = null;
    await refresh();
  }

  Future<void> downloadEarsPlus() async {
    if (earsPlusDownloading) return;
    earsPlusDownloading = true;
    earsPlusError = null;
    earsPlusProgress = 0;
    notifyListeners();
    _earsPlusCancel = CancelToken();
    final err = await _fetch(earsPlusUrl, filePath(earsPlusFile), _earsPlusCancel!, (p) {
      earsPlusProgress = p;
      notifyListeners();
    });
    earsPlusError = err;
    if (err == null) {
      earsPlusReady = true;
      await setUseEarsPlus(true);
      Diag.instance.log('ears: whisper large-v3-turbo downloaded');
    }
    earsPlusDownloading = false;
    _earsPlusCancel = null;
    await refresh();
  }

  /// Downloads to a .part file then renames. Returns an error message or null.
  Future<String?> _fetch(String url, String target, CancelToken cancel, void Function(double) onProgress) async {
    final tmp = '$target.part';
    try {
      await _dio.download(
        url,
        tmp,
        cancelToken: cancel,
        options: Options(receiveTimeout: const Duration(hours: 2)),
        onReceiveProgress: (got, len) {
          if (len > 0) onProgress(got / len);
        },
      );
      await File(tmp).rename(target);
      return null;
    } on DioException catch (e) {
      final f = File(tmp);
      if (await f.exists()) await f.delete();
      return CancelToken.isCancel(e) ? null : 'Download failed. Check wifi and retry.';
    } catch (e) {
      return 'Download failed: $e';
    }
  }

  void cancelEars() => _earsCancel?.cancel();
  void cancelEarsPlus() => _earsPlusCancel?.cancel();

  Future<void> deleteEarsPlus() async {
    final f = File(filePath(earsPlusFile));
    if (await f.exists()) await f.delete();
    earsPlusReady = false;
    await setUseEarsPlus(false);
  }

  void _onEvent(SttEvent e) {
    if (e.type != 'download') return;
    final locale = (e.data['lang'] as String?) ?? '';
    final code = locale.split('-').first.toLowerCase();
    final s = _status[code];
    if (s == null) return;
    if (e.data['percent'] != null) s.earsPercent = (e.data['percent'] as num).toInt();
    if (e.data['done'] == true) {
      s.ears = true;
      s.downloading = false;
      Diag.instance.log('speech pack ready: $locale');
    }
    if (e.data['error'] != null) {
      s.error = 'Speech pack download failed (${e.data['error']})';
      s.downloading = false;
    }
    notifyListeners();
  }

  Future<void> setChosen(String code, bool chosen) async {
    if (chosen) {
      _chosen.add(code);
    } else {
      _chosen.remove(code);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('langs', _chosen.toList());
    notifyListeners();
  }

  /// Download both engines for a language (and English's brain model once).
  Future<void> download(Language l) async {
    final s = _status[l.code]!;
    if (s.downloading) return;
    s
      ..downloading = true
      ..error = null
      ..earsPercent = 0;
    notifyListeners();
    try {
      if (!englishBrain) {
        Diag.instance.log('mlkit: downloading en');
        englishBrain = await mlkit.download('en');
      }
      if (!s.brain) {
        Diag.instance.log('mlkit: downloading ${l.code}');
        s.brain = await mlkit.download(l.code);
      }
      s.ears = earsReady;
    } catch (e) {
      s.error = 'Download failed: $e';
      Diag.instance.log('ERROR download ${l.code}: $e');
    } finally {
      s.downloading = false;
      notifyListeners();
    }
  }

  Future<void> delete(Language l) async {
    try {
      await mlkit.delete(l.code);
    } catch (_) {}
    _status[l.code]!.brain = false;
    notifyListeners();
  }
}
