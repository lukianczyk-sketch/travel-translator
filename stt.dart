import 'dart:io';

import 'package:whisper_ggml_plus/whisper_ggml_plus.dart';

/// Whisper large-v3-turbo through whisper.cpp. The native context stays warm
/// between calls (the plugin caches it per model path), so only the first
/// utterance pays the load cost.
class SpeechToText {
  final String modelPath;
  final int threads;
  final Whisper _whisper = const Whisper(model: WhisperModel.largeV3Turbo);

  /// Trims Whisper's audio window to 15 s (audio_ctx 768). Big latency win for
  /// conversational utterances, which are always shorter than that.
  bool fast = true;

  SpeechToText({required this.modelPath, this.threads = 6});

  /// Warm the model so the first real sentence isn't slow.
  Future<void> warmUp(String silentWavPath) async {
    try {
      await transcribe(silentWavPath);
    } catch (_) {}
  }

  Future<String> transcribe(String wavPath) async {
    final res = await _whisper.transcribe(
      transcribeRequest: TranscribeRequest(
        audio: wavPath,
        language: 'auto',
        threads: threads,
        isNoTimestamps: true,
        speedUp: fast,
        vadMode: WhisperVadMode.disabled,
      ),
      modelPath: modelPath,
    );
    return res.text.trim();
  }

  Future<void> dispose() async {
    try {
      await _whisper.dispose();
    } catch (_) {}
  }

  static bool looksLikeNoise(String t) {
    final s = t.trim();
    if (s.isEmpty) return true;
    // Whisper hallucinations on silence/noise.
    final junk = RegExp(r'^[\[\(\.\-\s]*(music|applause|silence|blank_audio|noise|inaudible)', caseSensitive: false);
    if (junk.hasMatch(s)) return true;
    if (s.replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), '').isEmpty) return true;
    return false;
  }
}

/// A short silent WAV used to warm up Whisper.
Future<String> ensureSilentWav(String dir) async {
  final f = File('$dir/warmup.wav');
  if (await f.exists()) return f.path;
  const n = 16000; // 1 s
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
