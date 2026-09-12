import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/language.dart';

enum PackState { notInstalled, downloading, installed, failed }

class PackStatus {
  PackState state;
  double progress; // 0..1 across all files of the pack
  String? error;
  PackStatus({this.state = PackState.notInstalled, this.progress = 0, this.error});
}

/// Single source of truth for what's on the phone.
class ModelManager extends ChangeNotifier {
  ModelManager._();
  static final ModelManager instance = ModelManager._();

  final Dio _dio = Dio();
  final Map<String, PackStatus> _packs = {for (final p in allPacks) p.id: PackStatus()};
  final Set<String> _installedLanguages = {};
  final Map<String, CancelToken> _cancels = {};
  Directory? _dir;

  PackStatus pack(String id) => _packs[id]!;
  bool isInstalled(String id) => pack(id).state == PackState.installed;
  bool get allEnginesReady => allPacks.every((p) => isInstalled(p.id));
  bool isLanguageInstalled(String code) => _installedLanguages.contains(code);
  List<Language> get installedLanguages =>
      travelLanguages.where((l) => _installedLanguages.contains(l.code)).toList();

  String get modelsPath => _dir?.path ?? '';
  String filePath(String fileName) => '${_dir!.path}/$fileName';

  Future<void> init() async {
    final base = await getApplicationSupportDirectory();
    _dir = Directory('${base.path}/models');
    if (!await _dir!.exists()) await _dir!.create(recursive: true);

    for (final p in allPacks) {
      if (await _packComplete(p)) _packs[p.id]!.state = PackState.installed;
    }
    final prefs = await SharedPreferences.getInstance();
    _installedLanguages.addAll(prefs.getStringList('langs') ?? const []);
    notifyListeners();
  }

  Future<bool> _packComplete(EnginePack p) async {
    for (final f in p.files) {
      final file = File(filePath(f.fileName));
      if (!await file.exists()) return false;
      // Guard against half-written files. Sizes are approximate (and small
      // files round badly), so only reject if it's clearly incomplete.
      if (await file.length() < f.sizeMb * 1000 * 1000 * 0.6) return false;
    }
    return true;
  }

  Future<void> download(EnginePack p) async {
    final status = _packs[p.id]!;
    if (status.state == PackState.downloading) return;
    status
      ..state = PackState.downloading
      ..progress = 0
      ..error = null;
    notifyListeners();

    final cancel = CancelToken();
    _cancels[p.id] = cancel;
    final total = p.sizeMb.toDouble();
    var doneMb = 0.0;
    try {
      for (final f in p.files) {
        final target = filePath(f.fileName);
        if (await File(target).exists() &&
            await File(target).length() >= f.sizeMb * 1000 * 1000 * 0.6) {
          doneMb += f.sizeMb;
          continue;
        }
        final tmp = '$target.part';
        await _dio.download(
          f.url,
          tmp,
          cancelToken: cancel,
          options: Options(receiveTimeout: const Duration(hours: 3)),
          onReceiveProgress: (got, len) {
            final fileMb = len > 0 ? got / len * f.sizeMb : 0.0;
            status.progress = ((doneMb + fileMb) / total).clamp(0, 1);
            notifyListeners();
          },
        );
        await File(tmp).rename(target);
        doneMb += f.sizeMb;
      }
      status
        ..state = PackState.installed
        ..progress = 1;
    } on DioException catch (e) {
      status
        ..state = PackState.notInstalled
        ..error = CancelToken.isCancel(e) ? null : 'Download failed. Check wifi and retry.';
    } catch (_) {
      status
        ..state = PackState.failed
        ..error = 'Something went wrong. Retry.';
    } finally {
      _cancels.remove(p.id);
      notifyListeners();
    }
  }

  void cancel(String id) => _cancels[id]?.cancel();

  Future<void> delete(EnginePack p) async {
    for (final f in p.files) {
      final file = File(filePath(f.fileName));
      if (await file.exists()) await file.delete();
    }
    _packs[p.id] = PackStatus();
    notifyListeners();
  }

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
