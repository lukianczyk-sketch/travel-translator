import 'dart:async';
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
  IOSink? _sink;

  // Tunables surfaced on the Diagnostics screen.
  bool fastWhisper = true;
  int whisperThreads = 6;

  Future<void> init() async {
    final dir = await getApplicationSupportDirectory();
    _file = File('${dir.path}/diag.log');
    if (await _file!.exists()) {
      final old = await _file!.readAsLines();
      lines.addAll(old.length > 400 ? old.sublist(old.length - 400) : old);
    }
    _sink = _file!.openWrite(mode: FileMode.append);
    final prefs = await SharedPreferences.getInstance();
    fastWhisper = prefs.getBool('fast_whisper') ?? true;
    whisperThreads = prefs.getInt('whisper_threads') ?? 6;
    log('--- app start ${DateTime.now()} ---');
  }

  void log(String msg) {
    final line = '${_ts()} $msg';
    lines.add(line);
    if (lines.length > 600) lines.removeRange(0, lines.length - 600);
    _sink?.writeln(line);
    _sink?.flush();
    debugPrint(line);
    notifyListeners();
  }

  String _ts() {
    final n = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(n.hour)}:${two(n.minute)}:${two(n.second)}.${(n.millisecond ~/ 10).toString().padLeft(2, '0')}';
  }

  Future<void> setFast(bool v) async {
    fastWhisper = v;
    (await SharedPreferences.getInstance()).setBool('fast_whisper', v);
    log('setting: fast whisper = $v');
    notifyListeners();
  }

  Future<void> setThreads(int v) async {
    whisperThreads = v;
    (await SharedPreferences.getInstance()).setInt('whisper_threads', v);
    log('setting: whisper threads = $v');
    notifyListeners();
  }

  Future<void> clear() async {
    lines.clear();
    await _sink?.close();
    await _file?.writeAsString('');
    _sink = _file!.openWrite(mode: FileMode.append);
    log('--- log cleared ---');
  }

  String get text => lines.join('\n');
}
