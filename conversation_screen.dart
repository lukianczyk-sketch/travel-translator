import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/language.dart';
import '../services/pipeline.dart';
import '../theme.dart';

class ConversationScreen extends StatefulWidget {
  final Language language;
  const ConversationScreen({super.key, required this.language});

  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen>
    with SingleTickerProviderStateMixin {
  late final Pipeline _pipe = Pipeline(widget.language);
  bool _bigText = false;
  bool _showLatency = false;

  late final AnimationController _wave =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);

  @override
  void initState() {
    super.initState();
    _pipe.start().catchError((e) {
      if (mounted) {
        setState(() => _pipe.status = 'Could not start: $e');
      }
    });
  }

  @override
  void dispose() {
    _wave.dispose();
    _pipe.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lang = widget.language;
    final big = _bigText ? 1.35 : 1.0;
    return AnimatedBuilder(
      animation: _pipe,
      builder: (context, _) {
        final last = _pipe.last;
        final themLast = last != null && last.fromThem ? last : _lastFrom(true);
        final youLast = last != null && !last.fromThem ? last : _lastFrom(false);
        return Scaffold(
          body: Column(
            children: [
              Expanded(
                child: _Panel(
                  color: Palette.them,
                  soft: Palette.themSoft,
                  label: '${lang.flag}  THEM  →  ENGLISH',
                  active: _pipe.turn == Turn.them || (_pipe.turn == Turn.speaking && (last?.fromThem ?? false)),
                  original: themLast?.original ?? '',
                  translated: themLast?.translated ??
                      (_pipe.ready ? 'Waiting for someone to speak…' : _pipe.status),
                  scale: big,
                  top: true,
                ),
              ),
              _StatusBar(
                pipe: _pipe,
                wave: _wave,
                bigText: _bigText,
                showLatency: _showLatency,
                onBigText: () => setState(() => _bigText = !_bigText),
                onLatency: () => setState(() => _showLatency = !_showLatency),
                onReplay: () {
                  HapticFeedback.mediumImpact();
                  _pipe.replay();
                },
                onStop: () => Navigator.of(context).pop(),
              ),
              Expanded(
                child: _Panel(
                  color: Palette.you,
                  soft: Palette.youSoft,
                  label: '🇺🇸  YOU  →  ${lang.name.toUpperCase()}',
                  active: _pipe.turn == Turn.you || (_pipe.turn == Turn.speaking && !(last?.fromThem ?? true)),
                  original: youLast?.original ?? '',
                  translated: youLast?.translated ?? 'Your words will appear here in ${lang.name}.',
                  scale: big,
                  top: false,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Exchange? _lastFrom(bool them) {
    for (final e in _pipe.history.reversed) {
      if (e.fromThem == them) return e;
    }
    return null;
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
              Text(label,
                  style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 2)),
              const SizedBox(height: 10),
              if (original.isNotEmpty)
                Text(original,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Palette.muted, fontSize: 18 * scale, height: 1.3)),
              if (original.isNotEmpty) const SizedBox(height: 8),
              Text(
                translated,
                maxLines: 6,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 30 * scale, fontWeight: FontWeight.w800, height: 1.15, letterSpacing: -0.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  final Pipeline pipe;
  final Animation<double> wave;
  final bool bigText, showLatency;
  final VoidCallback onBigText, onLatency, onReplay, onStop;
  const _StatusBar({
    required this.pipe,
    required this.wave,
    required this.bigText,
    required this.showLatency,
    required this.onBigText,
    required this.onLatency,
    required this.onReplay,
    required this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    final label = switch (pipe.turn) {
      Turn.listening => pipe.ready ? 'LISTENING' : 'STARTING',
      Turn.talking => 'SOMEONE\'S TALKING',
      Turn.them => 'THEY\'RE TALKING',
      Turn.you => 'YOU\'RE TALKING',
      Turn.thinking => 'HEARING',
      Turn.speaking => 'SPEAKING',
    };
    final lat = pipe.lastLatency;
    final sub = showLatency && lat != null
        ? 'hear ${_s(lat.hearMs)} · translate ${_s(lat.translateMs)} · total ${_s(lat.totalMs)}'
        : pipe.status;
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
                    _Dots(wave: wave, level: pipe.level, live: pipe.ready),
                    const SizedBox(width: 10),
                    Text(label,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, letterSpacing: 2)),
                  ],
                ),
                const SizedBox(height: 4),
                Text(sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: showLatency ? Palette.gold : Palette.muted,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          _RoundBtn(icon: Icons.replay_rounded, color: Palette.card, onTap: onReplay),
          const SizedBox(width: 8),
          _RoundBtn(icon: Icons.speed_rounded, color: showLatency ? Palette.gold : Palette.card, onTap: onLatency),
          const SizedBox(width: 8),
          _RoundBtn(icon: Icons.format_size_rounded, color: bigText ? Palette.gold : Palette.card, onTap: onBigText),
        ],
      ),
    );
  }

  static String _s(int ms) => '${(ms / 1000).toStringAsFixed(1)}s';
}

class _RoundBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final double size;
  const _RoundBtn({required this.icon, required this.color, required this.onTap, this.size = 50});

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
          boxShadow: color == Palette.them ? [BoxShadow(color: color.withOpacity(0.5), blurRadius: 16)] : null,
        ),
        child: Icon(icon, color: Colors.white, size: size * 0.55),
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  final Animation<double> wave;
  final double level;
  final bool live;
  const _Dots({required this.wave, required this.level, required this.live});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: wave,
      builder: (_, __) => Row(
        children: List.generate(3, (i) {
          final phase = ((wave.value + i * 0.33) % 1.0);
          final anim = 6 + 14 * (phase < 0.5 ? phase * 2 : (1 - phase) * 2);
          final h = live ? 6 + 16 * level.clamp(0.0, 1.0) * (0.6 + 0.4 * (anim / 20)) : anim;
          return Container(
            width: 5,
            height: h,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              color: live ? Palette.ok : Palette.muted,
              borderRadius: BorderRadius.circular(3),
            ),
          );
        }),
      ),
    );
  }
}
