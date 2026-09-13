import 'dart:async';

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
  bool englishEars = false;
  bool speechAvailable = false;
  bool canCheckEars = false; // Android 13+ can list installed speech packs
  int sdk = 0;
  StreamSubscription? _evSub;

  LangStatus status(String code) => _status[code]!;
  bool isChosen(String code) => _chosen.contains(code);
  List<Language> get chosenLanguages => travelLanguages.where((l) => _chosen.contains(l.code)).toList();
  List<Language> get readyLanguages =>
      chosenLanguages.where((l) => status(l.code).state == LangState.ready).toList();
  bool get anyReady => readyLanguages.isNotEmpty && englishBrain;

  Future<void> init() async {
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
    if (canCheckEars) {
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
    } else {
      // Can't inspect; assume the recognizer will fetch what it needs.
      englishEars = true;
      for (final l in travelLanguages) {
        _status[l.code]!.ears = true;
      }
    }
    notifyListeners();
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
      if (!s.ears && canCheckEars) {
        Diag.instance.log('speech: requesting pack ${l.ttsLocale}');
        await NativeStt.download(l.ttsLocale);
        if (!englishEars) await NativeStt.download('en-US');
        // Give the system a moment, then re-check (older phones give no callback).
        await Future.delayed(const Duration(seconds: 8));
        await refresh();
        if (!s.ears) {
          s.error = 'Speech pack is downloading in the background — check back in a minute.';
        }
      }
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
