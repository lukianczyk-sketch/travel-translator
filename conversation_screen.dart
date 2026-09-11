import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/language.dart';
import '../theme.dart';

enum Turn { listening, them, you }

class ConversationScreen extends StatefulWidget {
  final Language language;
  const ConversationScreen({super.key, required this.language});

  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen>
    with SingleTickerProviderStateMixin {
  Turn _turn = Turn.listening;
  String _themOriginal = '';
  String _themTranslated = '';
  String _youOriginal = '';
  String _youTranslated = '';
  bool _bigText = false;

  late final AnimationController _wave =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);

  @override
  void initState() {
    super.initState();
    WakelockStub.keepOn();
    // Drop 2 replaces this with the live Whisper → NLLB → TTS relay.
    _themOriginal = '';
    _themTranslated = 'Waiting for someone to speak…';
    _youTranslated = 'Your words will appear here in ${widget.language.name}.';
  }

  @override
  void dispose() {
    _wave.dispose();
    WakelockStub.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lang = widget.language;
    final big = _bigText ? 1.35 : 1.0;
    return Scaffold(
      body: Column(
        children: [
          // ---------- THEM (top) ----------
          Expanded(
            child: _Panel(
              color: Palette.them,
              soft: Palette.themSoft,
              label: '${lang.flag}  THEM  →  ENGLISH',
              active: _turn == Turn.them,
              original: _themOriginal,
              translated: _themTranslated,
              scale: big,
              top: true,
            ),
          ),
          // ---------- STATUS BAR ----------
          _StatusBar(
            turn: _turn,
            wave: _wave,
            language: lang,
            bigText: _bigText,
            onBigText: () => setState(() => _bigText = !_bigText),
            onReplay: () {
              HapticFeedback.mediumImpact();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Replay arrives with the live engine in the next build.')),
              );
            },
            onStop: () => Navigator.of(context).pop(),
          ),
          // ---------- YOU (bottom) ----------
          Expanded(
            child: _Panel(
              color: Palette.you,
              soft: Palette.youSoft,
              label: '🇺🇸  YOU  →  ${lang.name.toUpperCase()}',
              active: _turn == Turn.you,
              original: _youOriginal,
              translated: _youTranslated,
              scale: big,
              top: false,
            ),
          ),
        ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  final Color color, soft;
  final String label, original, translated;
  final bool active, top;
  final double scale;
  const _Panel({
    required this.color,
    required this.soft,
    required this.label,
    required this.active,
    required this.original,
    required this.translated,
    required this.scale,
    required this.top,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: top ? Alignment.topCenter : Alignment.bottomCenter,
          end: top ? Alignment.bottomCenter : Alignment.topCenter,
          colors: [active ? color.withOpacity(0.35) : soft, Palette.bg],
        ),
      ),
      child: SafeArea(
        top: top,
        bottom: !top,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: top ? MainAxisAlignment.end : MainAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 10),
              if (original.isNotEmpty)
                Text(
                  original,
                  style: TextStyle(color: Palette.muted, fontSize: 18 * scale, height: 1.3),
                ),
              if (original.isNotEmpty) const SizedBox(height: 8),
              Text(
                translated,
                style: TextStyle(
                  fontSize: 30 * scale,
                  fontWeight: FontWeight.w800,
                  height: 1.15,
                  letterSpacing: -0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  final Turn turn;
  final Animation<double> wave;
  final Language language;
  final bool bigText;
  final VoidCallback onBigText, onReplay, onStop;
  const _StatusBar({
    required this.turn,
    required this.wave,
    required this.language,
    required this.bigText,
    required this.onBigText,
    required this.onReplay,
    required this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    final label = switch (turn) {
      Turn.listening => 'LISTENING',
      Turn.them => 'THEY\'RE TALKING',
      Turn.you => 'YOU\'RE TALKING',
    };
    return Container(
      height: 92,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      color: Palette.bg2,
      child: Row(
        children: [
          _RoundBtn(icon: Icons.stop_rounded, color: Palette.them, onTap: onStop, size: 62),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _Dots(wave: wave),
                    const SizedBox(width: 10),
                    Text(
                      label,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, letterSpacing: 2),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'Auto-detects who\'s speaking',
                  style: TextStyle(color: Palette.muted, fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          _RoundBtn(icon: Icons.replay_rounded, color: Palette.card, onTap: onReplay),
          const SizedBox(width: 10),
          _RoundBtn(
            icon: Icons.format_size_rounded,
            color: bigText ? Palette.gold : Palette.card,
            onTap: onBigText,
          ),
        ],
      ),
    );
  }
}

class _RoundBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final double size;
  const _RoundBtn({required this.icon, required this.color, required this.onTap, this.size = 52});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          boxShadow: color == Palette.them
              ? [BoxShadow(color: color.withOpacity(0.5), blurRadius: 16)]
              : null,
        ),
        child: Icon(icon, color: Colors.white, size: size * 0.55),
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  final Animation<double> wave;
  const _Dots({required this.wave});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: wave,
      builder: (_, __) => Row(
        children: List.generate(3, (i) {
          final phase = ((wave.value + i * 0.33) % 1.0);
          final h = 6 + 14 * (phase < 0.5 ? phase * 2 : (1 - phase) * 2);
          return Container(
            width: 5,
            height: h,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              color: Palette.ok,
              borderRadius: BorderRadius.circular(3),
            ),
          );
        }),
      ),
    );
  }
}

/// Keeps the screen awake during conversation. Real wakelock plugin lands in drop 2
/// alongside the audio engine to keep drop 1's dependency list minimal.
class WakelockStub {
  static void keepOn() {}
  static void release() {}
}
