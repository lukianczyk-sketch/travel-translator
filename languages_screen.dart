import 'package:flutter/material.dart';

import '../models/language.dart';
import '../services/model_manager.dart';
import '../theme.dart';

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
              const Text('Languages', style: headline),
              const SizedBox(height: 6),
              const Text(
                'Download on wifi once. Then it all works with no signal.',
                style: TextStyle(color: Palette.muted, fontSize: 17, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 26),
              const _SectionLabel('ENGINES (download once)'),
              const SizedBox(height: 10),
              _EngineCard(pack: whisperPack, status: mm.engine(whisperPack.id)),
              const SizedBox(height: 12),
              _EngineCard(pack: nllbPack, status: mm.engine(nllbPack.id), comingSoon: true),
              const SizedBox(height: 28),
              const _SectionLabel('YOUR LANGUAGES'),
              const SizedBox(height: 10),
              ...travelLanguages.map(
                (l) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _LanguageTile(lang: l, installed: mm.isLanguageInstalled(l.code)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
          color: Palette.muted,
          fontSize: 13,
          fontWeight: FontWeight.w800,
          letterSpacing: 2,
        ),
      );
}

class _EngineCard extends StatelessWidget {
  final EnginePack pack;
  final PackStatus status;
  final bool comingSoon;
  const _EngineCard({required this.pack, required this.status, this.comingSoon = false});

  @override
  Widget build(BuildContext context) {
    final mm = ModelManager.instance;
    final installed = status.state == PackState.installed;
    final downloading = status.state == PackState.downloading;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Palette.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: installed ? Palette.ok.withOpacity(0.6) : Colors.transparent, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                pack.id == 'whisper' ? Icons.hearing_rounded : Icons.psychology_rounded,
                color: installed ? Palette.ok : Palette.gold,
                size: 30,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(pack.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                    Text('${pack.subtitle} · ${pack.sizeMb} MB',
                        style: const TextStyle(color: Palette.muted, fontSize: 14)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (comingSoon)
            const _Pill('ARRIVES IN NEXT BUILD', Palette.gold)
          else if (installed)
            Row(
              children: [
                const _Pill('READY', Palette.ok),
                const Spacer(),
                TextButton(
                  onPressed: () => mm.deleteEngine(pack),
                  child: const Text('Delete', style: TextStyle(color: Palette.muted, fontSize: 15)),
                ),
              ],
            )
          else if (downloading)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: status.progress == 0 ? null : status.progress,
                    minHeight: 12,
                    backgroundColor: Palette.bg,
                    color: Palette.you,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text('${(status.progress * 100).toStringAsFixed(0)}%  ·  '
                        '${(status.progress * pack.sizeMb).toStringAsFixed(0)} / ${pack.sizeMb} MB',
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                    const Spacer(),
                    TextButton(
                      onPressed: () => mm.cancelEngine(pack.id),
                      child: const Text('Cancel', style: TextStyle(color: Palette.them, fontSize: 15)),
                    ),
                  ],
                ),
              ],
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (status.error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(status.error!, style: const TextStyle(color: Palette.them, fontSize: 14)),
                  ),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Palette.you,
                      foregroundColor: Palette.bg,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: () => mm.downloadEngine(pack),
                    icon: const Icon(Icons.download_rounded, size: 26),
                    label: const Text('Download on wifi',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String text;
  final Color color;
  const _Pill(this.text, this.color);
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.18),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(text,
            style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
      );
}

class _LanguageTile extends StatelessWidget {
  final Language lang;
  final bool installed;
  const _LanguageTile({required this.lang, required this.installed});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => ModelManager.instance.setLanguageInstalled(lang.code, !installed),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: installed ? Palette.them.withOpacity(0.18) : Palette.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: installed ? Palette.them : Colors.transparent, width: 1.5),
        ),
        child: Row(
          children: [
            Text(lang.flag, style: const TextStyle(fontSize: 34)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(lang.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                  Text(lang.native, style: const TextStyle(color: Palette.muted, fontSize: 15)),
                ],
              ),
            ),
            Icon(
              installed ? Icons.check_circle_rounded : Icons.add_circle_outline_rounded,
              color: installed ? Palette.them : Palette.muted,
              size: 32,
            ),
          ],
        ),
      ),
    );
  }
}
