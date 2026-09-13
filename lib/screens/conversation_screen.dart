import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/language.dart';
import '../services/diag.dart';
import '../services/pipeline.dart';
import '../theme.dart';

class ConversationScreen extends StatefulWidget {
  final List<Language> languages;
  const ConversationScreen({super.key, required this.languages});

  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen>
    with SingleTickerProviderStateMixin {
  late final Pipeline _pipe = Pipeline(widget.languages);
  bool _bigText = false;
  bool _showLatency = false;

  late final AnimationController _wave =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);

  @override
  void initState() {
    super.initState();
    _pipe.start().catchError((e) {
      Diag.instance.log('ERROR pipeline start: $e');
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
    final big = _bigText ? 1.35 : 1.0;
    return AnimatedBuilder(
      animation: _pipe,
      builder: (context, _) {
        final lang = _pipe.other;
        final multi = widget.languages.length > 1;
        final last = _pipe.last;
        final themLast = last != null && last.fromThem ? last : _lastFrom(true);
        final youLast = last != null && !last.fromThem ? last : _lastFrom(false);
        final liveThem = _pipe.live.isNotEmpty && _pipe.liveFromThem ? _pipe.live : null;
        final liveYou = _pipe.live.isNotEmpty && !_pipe.liveFromThem ? _pipe.live : null;
        return Scaffold(
          body: Column(
            children: [
              Expanded(
                child: _Panel(
                  color: Palette.them,
                  soft: Palette.themSoft,
                  label: multi ? '${widget.languages.map((l) => l.flag).join(' ')}  THEM  →  ENGLISH' : '${lang.flag}  THEM  →  ENGLISH',
                  active: _pipe.turn == Turn.them || (_pipe.turn == Turn.speaking && (last?.fromThem ?? false)),
                  original: liveThem ?? themLast?.original ?? '',
                  translated: liveThem != null
                      ? '…'
                      : themLast?.translated ?? (_pipe.ready ? 'Waiting for someone to speak…' : _pipe.status),
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
                onSpeaker: () => setState(() => _pipe.speakerForThem = !_pipe.speakerForThem),
              ),
              Expanded(
                child: _Panel(
                  color: Palette.you,
                  soft: Palette.youSoft,
                  label: '🇺🇸  YOU  →  ${lang.name.toUpperCase()}',
                  active: _pipe.turn == Turn.you || (_pipe.turn == Turn.speaking && !(last?.fromThem ?? true)),
                  original: liveYou ?? youLast?.original ?? '',
                  translated: liveYou != null ? '…' : youLast?.translated ?? 'Your words will appear here in ${lang.name}.',
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
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w900, letterSpacing: 2)),
              const SizedBox(height: 8),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        translated,
                        style: TextStyle(fontSize: 30 * scale, fontWeight: FontWeight.w800, height: 1.15, letterSpacing: -0.5),
                      ),
                      if (original.isNotEmpty) const SizedBox(height: 10),
                      if (original.isNotEmpty)
                        Text(original,
                            style: TextStyle(color: Palette.muted, fontSize: 17 * scale, height: 1.3)),
                    ],
                  ),
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
  final Pipeline pipe;
  final Animation<double> wave;
  final bool bigText, showLatency;
  final VoidCallback onBigText, onLatency, onReplay, onStop, onSpeaker;
  const _StatusBar({
    required this.pipe,
    required this.wave,
    required this.bigText,
    required this.showLatency,
    required this.onBigText,
    required this.onLatency,
    required this.onReplay,
    required this.onStop,
    required this.onSpeaker,
  });

  @override
  Widget build(BuildContext context) {
    final label = switch (pipe.turn) {
      Turn.listening => pipe.ready ? 'LISTENING' : 'STARTING',
      Turn.talking => 'SOMEONE\'S TALKING',
      Turn.them => 'THEY\'RE TALKING',
      Turn.you => 'YOU\'RE TALKING',
      Turn.thinking => 'HEARING',
      Turn.speaking => 'SPEAKING — ONE MOMENT',
    };
    final lat = pipe.lastLatency;
    final sub = showLatency && lat != null
        ? 'translate ${_s(lat.translateMs)} · to voice ${_s(lat.totalMs)}'
        : pipe.status;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      color: Palette.bg2,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _RoundBtn(icon: Icons.stop_rounded, color: Palette.them, onTap: onStop, size: 46),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
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
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(child: _BarBtn(icon: Icons.replay_rounded, label: 'Replay', on: false, onTap: onReplay)),
              const SizedBox(width: 8),
              Expanded(child: _BarBtn(icon: Icons.speed_rounded, label: 'Time', on: showLatency, onTap: onLatency)),
              const SizedBox(width: 8),
              Expanded(child: _BarBtn(icon: Icons.format_size_rounded, label: 'Aa', on: bigText, onTap: onBigText)),
              const SizedBox(width: 8),
              Expanded(child: _BarBtn(icon: Icons.volume_up_rounded, label: 'Speaker', on: pipe.speakerForThem, onTap: onSpeaker)),
            ],
          ),
        ],
      ),
    );
  }

  static String _s(int ms) => '${(ms / 1000).toStringAsFixed(1)}s';
}

class _BarBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool on;
  final VoidCallback onTap;
  const _BarBtn({required this.icon, required this.label, required this.on, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 34,
        decoration: BoxDecoration(
          color: on ? Palette.gold : Palette.card,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 20, color: on ? Palette.bg : Colors.white),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: on ? Palette.bg : Colors.white)),
          ],
        ),
      ),
    );
  }
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
