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

  // ---- Ears: Whisper small, one file for every language ----
  static const earsUrl = 'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small-q8_0.bin';
  static const earsFile = 'ggml-small-q8_0.bin';
  static const earsMb = 264;
  bool earsReady = false;
  bool earsDownloading = false;
  double earsProgress = 0;
  String? earsError;
  String modelsPath = '';
  final Dio _dio = Dio();
  CancelToken? _earsCancel;

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
    final prefs = await SharedPreferences.getInstance();
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
    final target = filePath(earsFile);
    final tmp = '$target.part';
    _earsCancel = CancelToken();
    try {
      await _dio.download(
        earsUrl,
        tmp,
        cancelToken: _earsCancel,
        options: Options(receiveTimeout: const Duration(hours: 2)),
        onReceiveProgress: (got, len) {
          if (len > 0) {
            earsProgress = got / len;
            notifyListeners();
          }
        },
      );
      await File(tmp).rename(target);
      earsReady = true;
      Diag.instance.log('ears: whisper small downloaded');
    } on DioException catch (e) {
      earsError = CancelToken.isCancel(e) ? null : 'Download failed. Check wifi and retry.';
      final f = File(tmp);
      if (await f.exists()) await f.delete();
    } catch (e) {
      earsError = 'Download failed: $e';
    } finally {
      earsDownloading = false;
      _earsCancel = null;
      await refresh();
    }
  }

  void cancelEars() => _earsCancel?.cancel();

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
