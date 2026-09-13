import 'package:flutter/material.dart';

import '../models/language.dart';
import '../services/model_manager.dart';
import '../theme.dart';
import 'diag_screen.dart';

class LanguagesScreen extends StatelessWidget {
  const LanguagesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ModelManager.instance,
      builder: (context, _) {
        final mm = ModelManager.instance;
        return SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            children: [
              Row(
                children: [
                  const Expanded(child: Text('Languages', style: headline)),
                  IconButton(
                    tooltip: 'Re-check what\'s installed',
                    onPressed: mm.refresh,
                    icon: const Icon(Icons.refresh_rounded, color: Palette.muted, size: 28),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                'Tap a language to add it. Tap Get to put its ears + brain on the phone (about 60 MB, once). Then it works with no signal.',
                style: TextStyle(color: Palette.muted, fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 14),
              _EnglishRow(brain: mm.englishBrain, ears: mm.englishEars),
              const SizedBox(height: 18),
              ...travelLanguages.map(
                (l) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _LanguageTile(lang: l, chosen: mm.isChosen(l.code), status: mm.status(l.code)),
                ),
              ),
              const SizedBox(height: 18),
              Center(
                child: TextButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const DiagScreen()),
                  ),
                  icon: const Icon(Icons.bug_report_outlined, color: Palette.muted),
                  label: Text('Diagnostics · v$appVersion', style: const TextStyle(color: Palette.muted, fontSize: 16)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _EnglishRow extends StatelessWidget {
  final bool brain, ears;
  const _EnglishRow({required this.brain, required this.ears});
  @override
  Widget build(BuildContext context) {
    final ok = brain && ears;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: Palette.card, borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          const Text('🇺🇸', style: TextStyle(fontSize: 24)),
          const SizedBox(width: 10),
          const Expanded(child: Text('English (your side)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
          _Chip(ok ? 'READY' : 'ADDED WITH FIRST LANGUAGE', ok ? Palette.ok : Palette.muted),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String text;
  final Color color;
  const _Chip(this.text, this.color);
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(color: color.withOpacity(0.18), borderRadius: BorderRadius.circular(8)),
        child: Text(text, style: TextStyle(color: color, fontSize: 10.5, fontWeight: FontWeight.w900, letterSpacing: 1)),
      );
}

class _LanguageTile extends StatelessWidget {
  final Language lang;
  final bool chosen;
  final LangStatus status;
  const _LanguageTile({required this.lang, required this.chosen, required this.status});

  @override
  Widget build(BuildContext context) {
    final mm = ModelManager.instance;
    final ready = status.state == LangState.ready;
    final downloading = status.state == LangState.downloading;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      decoration: BoxDecoration(
        color: chosen ? Palette.them.withOpacity(0.14) : Palette.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: chosen ? Palette.them : Colors.transparent, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: () => mm.setChosen(lang.code, !chosen),
                child: Row(
                  children: [
                    Text(lang.flag, style: const TextStyle(fontSize: 30)),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(lang.name, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                        Text(lang.native, style: const TextStyle(color: Palette.muted, fontSize: 14)),
                      ],
                    ),
                  ],
                ),
              ),
              const Spacer(),
              if (ready)
                const _Chip('READY', Palette.ok)
              else if (downloading)
                const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 3, color: Palette.you))
              else
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: Palette.you,
                    foregroundColor: Palette.bg,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => mm.download(lang),
                  child: const Text('Get', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                ),
              const SizedBox(width: 6),
              IconButton(
                onPressed: () => mm.setChosen(lang.code, !chosen),
                icon: Icon(
                  chosen ? Icons.check_circle_rounded : Icons.add_circle_outline_rounded,
                  color: chosen ? Palette.them : Palette.muted,
                  size: 30,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _Chip(status.ears ? 'EARS ✓' : 'EARS ⬇', status.ears ? Palette.ok : Palette.muted),
              const SizedBox(width: 6),
              _Chip(status.brain ? 'BRAIN ✓' : 'BRAIN ⬇', status.brain ? Palette.ok : Palette.muted),
              if (downloading && status.earsPercent > 0) ...[
                const SizedBox(width: 8),
                Text('${status.earsPercent}%', style: const TextStyle(color: Palette.muted, fontSize: 12)),
              ],
            ],
          ),
          if (status.error != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(status.error!, style: const TextStyle(color: Palette.gold, fontSize: 13)),
            ),
        ],
      ),
    );
  }
}
