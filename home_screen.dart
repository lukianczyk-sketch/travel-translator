import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/language.dart';
import '../services/model_manager.dart';
import '../theme.dart';
import 'conversation_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
  Language? _selected;

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final mm = ModelManager.instance;
    final lang = _selected;
    if (lang == null) {
      _toast('Pick a language first.');
      return;
    }
    if (!mm.allEnginesReady) {
      _toast('Download all three engine packs in Languages first (wifi once).');
      return;
    }
    final mic = await Permission.microphone.request();
    if (!mic.isGranted) {
      _toast('Microphone permission is required.');
      return;
    }
    if (!mounted) return;
    Navigator.of(context).push(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 350),
        pageBuilder: (_, a, __) => FadeTransition(
          opacity: a,
          child: ConversationScreen(language: lang),
        ),
      ),
    );
  }

  void _toast(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ModelManager.instance,
      builder: (context, _) {
        final mm = ModelManager.instance;
        final langs = mm.installedLanguages;
        if (_selected != null && !langs.contains(_selected)) _selected = null;
        _selected ??= langs.isNotEmpty ? langs.first : null;

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Travel\nTranslator', style: headline),
                const SizedBox(height: 6),
                Text(
                  'Offline. Live. Both ways.',
                  style: TextStyle(color: Palette.muted, fontSize: 17, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 22),
                _ReadyRow(ready: mm.allEnginesReady),
                const Spacer(),
                Center(
                  child: _TalkButton(
                    pulse: _pulse,
                    enabled: langs.isNotEmpty && mm.allEnginesReady,
                    onTap: _start,
                  ),
                ),
                const Spacer(),
                Text(
                  langs.isEmpty ? 'NO LANGUAGES YET' : 'THEY SPEAK',
                  style: const TextStyle(
                    color: Palette.muted,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 10),
                if (langs.isEmpty)
                  const Text(
                    'Go to Languages and download the ones you need.',
                    style: TextStyle(fontSize: 17),
                  )
                else
                  SizedBox(
                    height: 64,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: langs.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 10),
                      itemBuilder: (_, i) {
                        final l = langs[i];
                        final on = l == _selected;
                        return GestureDetector(
                          onTap: () => setState(() => _selected = l),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(horizontal: 18),
                            decoration: BoxDecoration(
                              color: on ? Palette.them : Palette.card,
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: on
                                  ? [BoxShadow(color: Palette.them.withOpacity(0.5), blurRadius: 18)]
                                  : null,
                            ),
                            child: Row(
                              children: [
                                Text(l.flag, style: const TextStyle(fontSize: 28)),
                                const SizedBox(width: 10),
                                Text(
                                  l.name,
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                    color: on ? Colors.white : Palette.text,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ReadyRow extends StatelessWidget {
  final bool ready;
  const _ReadyRow({required this.ready});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Palette.card,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: ready ? Palette.ok : Palette.gold,
              boxShadow: [BoxShadow(color: (ready ? Palette.ok : Palette.gold).withOpacity(0.7), blurRadius: 10)],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              ready ? 'All engines ready — works with no signal' : 'Engine packs not downloaded yet',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _TalkButton extends StatelessWidget {
  final Animation<double> pulse;
  final bool enabled;
  final VoidCallback onTap;
  const _TalkButton({required this.pulse, required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: pulse,
      builder: (_, __) {
        final t = enabled ? pulse.value : 0.0;
        return GestureDetector(
          onTap: onTap,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 250 + 40 * t,
                height: 250 + 40 * t,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Palette.them.withOpacity(0.10 + 0.08 * (1 - t)),
                ),
              ),
              Container(
                width: 220,
                height: 220,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: enabled
                        ? const [Color(0xFFFF7A5C), Palette.them, Color(0xFFC2185B)]
                        : const [Color(0xFF2A3247), Color(0xFF1A2236)],
                  ),
                  boxShadow: enabled
                      ? [BoxShadow(color: Palette.them.withOpacity(0.55), blurRadius: 40, spreadRadius: 4)]
                      : null,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.mic_rounded, size: 72, color: enabled ? Colors.white : Palette.muted),
                    const SizedBox(height: 4),
                    Text(
                      'TALK',
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 4,
                        color: enabled ? Colors.white : Palette.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
