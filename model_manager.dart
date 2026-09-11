import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/language.dart';

enum PackState { notInstalled, downloading, installed, failed }

class PackStatus {
  PackState state;
  double progress; // 0..1
  String? error;
  PackStatus({this.state = PackState.notInstalled, this.progress = 0, this.error});
}

/// Single source of truth for what's on the phone.
class ModelManager extends ChangeNotifier {
  ModelManager._();
  static final ModelManager instance = ModelManager._();

  final Dio _dio = Dio();
  final Map<String, PackStatus> _engines = {
    whisperPack.id: PackStatus(),
    nllbPack.id: PackStatus(),
  };
  final Set<String> _installedLanguages = {};
  final Map<String, CancelToken> _cancels = {};
  Directory? _dir;

  PackStatus engine(String id) => _engines[id]!;
  bool get whisperReady => engine(whisperPack.id).state == PackState.installed;
  bool isLanguageInstalled(String code) => _installedLanguages.contains(code);
  List<Language> get installedLanguages =>
      travelLanguages.where((l) => _installedLanguages.contains(l.code)).toList();

  Future<void> init() async {
    final base = await getApplicationSupportDirectory();
    _dir = Directory('${base.path}/models');
    if (!await _dir!.exists()) await _dir!.create(recursive: true);

    final whisperFile = File('${_dir!.path}/${whisperPack.fileName}');
    if (await whisperFile.exists() &&
        await whisperFile.length() > whisperPack.sizeMb * 1024 * 1024 * 0.95) {
      _engines[whisperPack.id]!.state = PackState.installed;
    }
    final prefs = await SharedPreferences.getInstance();
    _installedLanguages.addAll(prefs.getStringList('langs') ?? const []);
    notifyListeners();
  }

  String get modelsPath => _dir?.path ?? '';

  Future<void> downloadEngine(EnginePack pack) async {
    if (pack.url.isEmpty) return; // NLLB arrives in drop 2
    final status = _engines[pack.id]!;
    if (status.state == PackState.downloading) return;
    status
      ..state = PackState.downloading
      ..progress = 0
      ..error = null;
    notifyListeners();

    final target = '${_dir!.path}/${pack.fileName}';
    final tmp = '$target.part';
    final cancel = CancelToken();
    _cancels[pack.id] = cancel;
    try {
      await _dio.download(
        pack.url,
        tmp,
        cancelToken: cancel,
        options: Options(receiveTimeout: const Duration(hours: 2)),
        onReceiveProgress: (got, total) {
          if (total > 0) {
            status.progress = got / total;
            notifyListeners();
          }
        },
      );
      await File(tmp).rename(target);
      status
        ..state = PackState.installed
        ..progress = 1;
    } on DioException catch (e) {
      status
        ..state = PackState.notInstalled
        ..error = CancelToken.isCancel(e) ? null : 'Download failed. Check wifi and retry.';
      final f = File(tmp);
      if (await f.exists()) await f.delete();
    } catch (_) {
      status
        ..state = PackState.failed
        ..error = 'Something went wrong. Retry.';
    } finally {
      _cancels.remove(pack.id);
      notifyListeners();
    }
  }

  void cancelEngine(String id) => _cancels[id]?.cancel();

  Future<void> deleteEngine(EnginePack pack) async {
    final f = File('${_dir!.path}/${pack.fileName}');
    if (await f.exists()) await f.delete();
    _engines[pack.id] = PackStatus();
    notifyListeners();
  }

  /// Language packs are tiny tokenizer/config bundles layered on top of NLLB.
  /// In drop 1 this just records the choice so the UI + persistence are proven.
  Future<void> setLanguageInstalled(String code, bool installed) async {
    if (installed) {
      _installedLanguages.add(code);
    } else {
      _installedLanguages.remove(code);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('langs', _installedLanguages.toList());
    notifyListeners();
  }
}
