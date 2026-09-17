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

  // ---- Better brain: OPUS-MT Polish → English on ONNX Runtime (ML Kit stays for the other way) ----
  static const brainPlusBase = 'https://huggingface.co/Xenova/opus-mt-pl-en/resolve/main';
  static const brainPlusFiles = ['onnx/encoder_model_quantized.onnx', 'onnx/decoder_model_quantized.onnx', 'tokenizer.json', 'config.json'];
  static const brainPlusDir = 'opus-mt-pl-en';
  static const brainPlusMb = 130;
  bool brainPlusReady = false;
  bool brainPlusDownloading = false;
  double brainPlusProgress = 0;
  String? brainPlusError;
  bool useBrainPlus = true;
  CancelToken? _brainPlusCancel;
  bool get activeBrainPlus => useBrainPlus && brainPlusReady;
  String get brainPlusPath => '$modelsPath/$brainPlusDir';

  Future<void> setUseBrainPlus(bool v) async {
    useBrainPlus = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('brain_plus', v);
    notifyListeners();
  }

  Future<bool> _brainPlusOnDisk() async {
    for (final f in brainPlusFiles) {
      final file = File('$brainPlusPath/${f.split('/').last}');
      if (!await file.exists() || await file.length() < 1000) return false;
    }
    return true;
  }

  Future<void> downloadBrainPlus() async {
    if (brainPlusDownloading) return;
    brainPlusDownloading = true;
    brainPlusError = null;
    brainPlusProgress = 0;
    notifyListeners();
    _brainPlusCancel = CancelToken();
    await Directory(brainPlusPath).create(recursive: true);
    final weights = [0.40, 0.55, 0.04, 0.01];
    var done = 0.0;
    String? err;
    for (var i = 0; i < brainPlusFiles.length; i++) {
      final name = brainPlusFiles[i].split('/').last;
      final target = '$brainPlusPath/$name';
      if (await File(target).exists() && await File(target).length() > 1000) {
        done += weights[i];
        continue;
      }
      err = await _fetch('$brainPlusBase/${brainPlusFiles[i]}', target, _brainPlusCancel!, (p) {
        brainPlusProgress = done + weights[i] * p;
        notifyListeners();
      });
      if (err != null) break;
      done += weights[i];
    }
    brainPlusError = err;
    brainPlusReady = await _brainPlusOnDisk();
    if (brainPlusReady) {
      await setUseBrainPlus(true);
      Diag.instance.log('brain: opus-mt pl→en downloaded');
    }
    brainPlusDownloading = false;
    _brainPlusCancel = null;
    notifyListeners();
  }

  void cancelBrainPlus() => _brainPlusCancel?.cancel();

  Future<void> deleteBrainPlus() async {
    final d = Directory(brainPlusPath);
    if (await d.exists()) await d.delete(recursive: true);
    brainPlusReady = false;
    await setUseBrainPlus(false);
  }

  // ---- Fast Ears: NVIDIA Parakeet TDT 0.6B v3 (25 European languages, int8, sherpa-onnx export) ----
  static const fastEarsDir = 'parakeet-v3';
  static const fastEarsFiles = ['encoder.int8.onnx', 'decoder.int8.onnx', 'joiner.int8.onnx', 'tokens.txt'];
  // Per-file mirror (fast, no unpacking); falls back to the release tarball + on-device unpack.
  static const fastEarsFileBase = 'https://huggingface.co/csukuangfj/sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8/resolve/main';
  static const fastEarsTarUrl =
      'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8.tar.bz2';
  static const fastEarsMb = 670;
  /// Languages Parakeet v3 understands (ISO 639-1).
  static const fastEarsLangs = {'bg', 'hr', 'cs', 'da', 'nl', 'en', 'et', 'fi', 'fr', 'de', 'el', 'hu', 'it', 'lv', 'lt', 'mt', 'pl', 'pt', 'ro', 'ru', 'sk', 'sl', 'es', 'sv', 'uk'};
  bool fastEarsReady = false;
  bool fastEarsDownloading = false;
  double fastEarsProgress = 0;
  String fastEarsStage = '';
  String? fastEarsError;
  bool useFastEars = true;
  CancelToken? _fastEarsCancel;
  bool get activeFastEars => useFastEars && fastEarsReady;
  String get fastEarsPath => '$modelsPath/$fastEarsDir';

  Future<void> setUseFastEars(bool v) async {
    useFastEars = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('fast_ears', v);
    notifyListeners();
  }

  Future<bool> _fastEarsOnDisk() async {
    for (final f in fastEarsFiles) {
      final file = File('$fastEarsPath/$f');
      if (!await file.exists() || await file.length() < 1000) return false;
    }
    return true;
  }

  Future<void> downloadFastEars() async {
    if (fastEarsDownloading) return;
    fastEarsDownloading = true;
    fastEarsError = null;
    fastEarsProgress = 0;
    fastEarsStage = 'Downloading';
    notifyListeners();
    _fastEarsCancel = CancelToken();
    await Directory(fastEarsPath).create(recursive: true);
    String? err;
    // 1) per-file mirror
    final weights = [0.96, 0.02, 0.01, 0.01];
    var done = 0.0;
    var mirrorOk = true;
    for (var i = 0; i < fastEarsFiles.length; i++) {
      final name = fastEarsFiles[i];
      final target = '$fastEarsPath/$name';
      if (await File(target).exists() && await File(target).length() > 1000) {
        done += weights[i];
        continue;
      }
      err = await _fetch('$fastEarsFileBase/$name', target, _fastEarsCancel!, (p) {
        fastEarsProgress = done + weights[i] * p;
        notifyListeners();
      });
      if (err != null) {
        if (_fastEarsCancel!.isCancelled) break;
        mirrorOk = false;
        Diag.instance.log('fast ears: mirror failed for $name ($err) — trying the release tarball');
        break;
      }
      done += weights[i];
    }
    // 2) release tarball + native unpack
    if (!mirrorOk && !_fastEarsCancel!.isCancelled) {
      fastEarsProgress = 0;
      notifyListeners();
      final tar = '$modelsPath/parakeet.tar.bz2';
      err = await _fetch(fastEarsTarUrl, tar, _fastEarsCancel!, (p) {
        fastEarsProgress = p * 0.8;
        notifyListeners();
      });
      if (err == null) {
        fastEarsStage = 'Unpacking';
        fastEarsProgress = 0.85;
        notifyListeners();
        try {
          final n = await mlkit.extractTarBz2(tar, fastEarsPath);
          Diag.instance.log('fast ears: unpacked $n files');
        } catch (e) {
          err = 'Unpacking failed: $e';
        }
        try {
          await File(tar).delete();
        } catch (_) {}
      }
    }
    fastEarsError = err;
    fastEarsReady = await _fastEarsOnDisk();
    if (fastEarsReady) {
      await setUseFastEars(true);
      Diag.instance.log('ears: parakeet v3 downloaded');
    } else if (err == null && !_fastEarsCancel!.isCancelled) {
      fastEarsError = 'Download finished but files are missing — try again.';
    }
    fastEarsDownloading = false;
    fastEarsStage = '';
    _fastEarsCancel = null;
    notifyListeners();
  }

  void cancelFastEars() => _fastEarsCancel?.cancel();

  Future<void> deleteFastEars() async {
    final d = Directory(fastEarsPath);
    if (await d.exists()) await d.delete(recursive: true);
    fastEarsReady = false;
    await setUseFastEars(false);
  }

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
    if (!(prefs.getBool('ears_reset_v11') ?? false)) {
      // v0.11: back to the fast small ears by default (turbo stays available on the switch).
      useEarsPlus = false;
      await prefs.setBool('ears_plus', false);
      await prefs.setBool('ears_reset_v11', true);
    }
    useBrainPlus = prefs.getBool('brain_plus') ?? true;
    brainPlusReady = await _brainPlusOnDisk();
    useFastEars = prefs.getBool('fast_ears') ?? true;
    fastEarsReady = await _fastEarsOnDisk();
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
