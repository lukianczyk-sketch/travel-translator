import 'dart:io';

import 'package:whisper_ggml_plus/whisper_ggml_plus.dart';

/// One heard sentence.
class Heard {
  final String text;
  final String lang; // ISO 639-1 from Whisper ('en', 'pl', ...)
  const Heard(this.text, this.lang);
}

/// Whisper (small) through whisper.cpp, on sentence-sized audio only.
/// The native context stays warm between calls.
class SpeechToText {
  final String modelPath;
  final String vadModelPath;
  final int threads;
  final Whisper _whisper = const Whisper(model: WhisperModel.small);

  SpeechToText({required this.modelPath, required this.vadModelPath, this.threads = 6});

  Future<String?> warmUp(String silentWavPath) async {
    try {
      await transcribe(silentWavPath, seconds: 1);
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  /// [seconds] = length of the clip; the audio window is sized to it so
  /// Whisper doesn't pad every sentence out to 30 s.
  Future<Heard> transcribe(String wavPath, {required double seconds}) async {
    // 50 mel frames per second; keep a margin and a sane floor.
    final ctx = ((seconds + 1.0) * 50).clamp(160, 1500).round();
    final res = await _whisper.transcribeRaw(
      transcribeRequest: TranscribeRequest(
        audio: wavPath,
        language: 'auto',
        threads: threads,
        isNoTimestamps: true,
        vadMode: WhisperVadMode.disabled,
        vadModelPath: vadModelPath,
      ),
      modelPath: modelPath,
      audioCtx: ctx,
    );
    return Heard((res['text'] as String? ?? '').trim(), (res['language'] as String? ?? 'en').toLowerCase());
  }

  Future<void> dispose() async {
    try {
      await _whisper.dispose();
    } catch (_) {}
  }

  static bool looksLikeNoise(String t) {
    final s = t.trim();
    if (s.isEmpty) return true;
    final junk = RegExp(r'^[\[\(\.\-\s]*(music|applause|silence|blank_audio|noise|inaudible|thank you for watching)',
        caseSensitive: false);
    if (junk.hasMatch(s)) return true;
    if (s.replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), '').isEmpty) return true;
    return false;
  }

  static String collapseRepeats(String t) {
    final parts = t.split(RegExp(r'(?<=[.!?。！？])\s+')).map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    final out = <String>[];
    for (final p in parts) {
      if (out.isEmpty || out.last.toLowerCase() != p.toLowerCase()) out.add(p);
    }
    return out.join(' ');
  }
}

/// A short silent WAV used to warm up Whisper.
Future<String> ensureSilentWav(String dir) async {
  final f = File('$dir/warmup.wav');
  if (await f.exists()) return f.path;
  const n = 16000;
  final b = List<int>.filled(44 + n * 2, 0);
  void str(int o, String s) {
    for (var i = 0; i < s.length; i++) {
      b[o + i] = s.codeUnitAt(i);
    }
  }
  void u32(int o, int v) {
    b[o] = v & 0xff;
    b[o + 1] = (v >> 8) & 0xff;
    b[o + 2] = (v >> 16) & 0xff;
    b[o + 3] = (v >> 24) & 0xff;
  }
  void u16(int o, int v) {
    b[o] = v & 0xff;
    b[o + 1] = (v >> 8) & 0xff;
  }
  str(0, 'RIFF');
  u32(4, 36 + n * 2);
  str(8, 'WAVE');
  str(12, 'fmt ');
  u32(16, 16);
  u16(20, 1);
  u16(22, 1);
  u32(24, 16000);
  u32(28, 32000);
  u16(32, 2);
  u16(34, 16);
  str(36, 'data');
  u32(40, n * 2);
  await f.writeAsBytes(b, flush: true);
  return f.path;
}
