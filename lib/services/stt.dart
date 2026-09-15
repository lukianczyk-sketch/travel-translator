import 'dart:io';
import 'dart:math' as math;

import 'package:whisper_ggml_plus/whisper_ggml_plus.dart';

/// One heard sentence.
class Heard {
  final String text;
  final String lang; // ISO 639-1 from Whisper ('en', 'pl', ...)
  final double? langProb; // language-ID prior (tie-break only)
  final double? logprob; // mean token log-prob of the winning decode
  final double? margin; // winner's score minus the runner-up's
  final List<Candidate> candidates; // one decode per language in play
  const Heard(this.text, this.lang, [this.langProb, this.logprob, this.margin, this.candidates = const []]);

  /// 0..1 confidence in the words themselves (not the language guess).
  double get confidence => logprob == null ? 1 : math.exp(logprob!).clamp(0, 1).toDouble();
}

class Candidate {
  final String lang;
  final String text;
  final double logprob;
  final double score;
  const Candidate(this.lang, this.text, this.logprob, this.score);
}

/// Whisper (small) through whisper.cpp, on sentence-sized audio only.
/// The native context stays warm between calls.
class SpeechToText {
  final String modelPath;
  final String vadModelPath;
  final int threads;
  /// True for the big model: one decode with restricted auto-detect (one encoder run).
  /// False for small: decode once per language and keep the most confident.
  final bool singlePass;
  final Whisper _whisper = const Whisper(model: WhisperModel.small);

  SpeechToText({required this.modelPath, required this.vadModelPath, this.threads = 6, this.singlePass = false});

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
  Future<Heard> transcribe(String wavPath, {required double seconds, List<String> allowedLangs = const []}) async {
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
        noFallback: true,
      ),
      modelPath: modelPath,
      audioCtx: ctx,
      allowedLangs: allowedLangs,
      singlePass: singlePass,
    );
    final cands = <Candidate>[];
    for (final c in (res['candidates'] as List? ?? const [])) {
      final m = c as Map;
      cands.add(Candidate((m['lang'] as String? ?? '?').toLowerCase(), (m['text'] as String? ?? '').trim(),
          (m['logprob'] as num?)?.toDouble() ?? 0, (m['score'] as num?)?.toDouble() ?? 0));
    }
    return Heard(
      (res['text'] as String? ?? '').trim(),
      (res['language'] as String? ?? 'en').toLowerCase(),
      (res['language_prob'] as num?)?.toDouble(),
      (res['logprob'] as num?)?.toDouble(),
      (res['margin'] as num?)?.toDouble(),
      cands,
    );
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

  /// Strip [MUSIC]-style tags, collapse stutter loops, drop junk.
  static String clean(String raw) {
    var t = raw.replaceAll(RegExp(r'[\[\(][^\]\)]{0,40}[\]\)]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    // Collapse repeated phrases (1–5 words) that loop.
    final words = t.split(' ');
    for (var n = 1; n <= 5; n++) {
      final out = <String>[];
      var i = 0;
      while (i < words.length) {
        out.addAll(words.sublist(i, (i + n).clamp(0, words.length)));
        var j = i + n;
        var reps = 0;
        while (j + n <= words.length && _same(words, i, j, n)) {
          reps++;
          j += n;
        }
        i = reps > 0 ? j : i + n;
      }
      words
        ..clear()
        ..addAll(out);
    }
    t = words.join(' ').trim();
    // Repeated sentences.
    final parts = t.split(RegExp(r'(?<=[.!?。！？,])\s+')).map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    final kept = <String>[];
    for (final p in parts) {
      if (kept.isEmpty || kept.last.toLowerCase() != p.toLowerCase()) kept.add(p);
    }
    return kept.join(' ');
  }

  static bool _same(List<String> w, int a, int b, int n) {
    for (var k = 0; k < n; k++) {
      if (w[a + k].toLowerCase() != w[b + k].toLowerCase()) return false;
    }
    return true;
  }

  /// True if the clean text is too short/uncertain to be worth speaking.
  /// [confidence] is how sure Whisper was of the words (0..1).
  static bool isFragment(String t, double? confidence) {
    final letters = t.replaceAll(RegExp(r'[^\p{L}]', unicode: true), '');
    if (letters.length < 3) return true;
    final wordCount = t.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
    if (wordCount == 1 && (confidence ?? 1) < 0.5) return true;
    return false;
  }

  static String collapseRepeats(String t) => clean(t);
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
