import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Running log of what the app is doing, flushed to disk on every line so it
/// survives a crash. Read it from the Diagnostics screen.
class Diag extends ChangeNotifier {
  Diag._();
  static final Diag instance = Diag._();

  final List<String> lines = [];
  File? _file;


  Future<void> init() async {
    final dir = await getApplicationSupportDirectory();
    _file = File('${dir.path}/diag.log');
    if (await _file!.exists()) {
      final old = await _file!.readAsLines();
      lines.addAll(old.length > 400 ? old.sublist(old.length - 400) : old);
    }
    final prefs = await SharedPreferences.getInstance();
    log('--- app start ${DateTime.now()} ---');
  }

  void log(String msg) {
    int rss = 0;
    try {
      rss = ProcessInfo.currentRss ~/ (1024 * 1024);
    } catch (_) {}
    final line = '${_ts()} [${rss}MB] $msg';
    lines.add(line);
    if (lines.length > 600) lines.removeRange(0, lines.length - 600);
    try {
      _file?.writeAsStringSync('$line\n', mode: FileMode.append, flush: true);
    } catch (_) {}
    debugPrint(line);
    notifyListeners();
  }

  String _ts() {
    final n = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(n.hour)}:${two(n.minute)}:${two(n.second)}.${(n.millisecond ~/ 10).toString().padLeft(2, '0')}';
  }

  Future<void> clear() async {
    lines.clear();
    await _file?.writeAsString('');
    log('--- log cleared ---');
  }

  String get text => lines.join('\n');
}
