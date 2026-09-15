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
                'Get the Ears once (264 MB). Then tap a language to add it and Get its brain (about 60 MB). All offline after that.',
                style: TextStyle(color: Palette.muted, fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 14),
              _EarsCard(mm: mm),
              const SizedBox(height: 10),
              _BrainPlusCard(mm: mm),
              const SizedBox(height: 10),
              _EarsPlusCard(mm: mm),
              const SizedBox(height: 10),
              _EnglishRow(brain: mm.englishBrain, ears: mm.earsReady),
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

class _EarsCard extends StatelessWidget {
  final ModelManager mm;
  const _EarsCard({required this.mm});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Palette.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: mm.earsReady ? Palette.ok.withOpacity(0.6) : Colors.transparent, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.hearing_rounded, color: mm.earsReady ? Palette.ok : Palette.gold, size: 28),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Ears — Whisper small', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                    Text('Hears every language · 264 MB, once', style: TextStyle(color: Palette.muted, fontSize: 14)),
                  ],
                ),
              ),
              if (mm.earsReady) const _Chip('READY', Palette.ok),
            ],
          ),
          if (!mm.earsReady) ...[
            const SizedBox(height: 12),
            if (mm.earsDownloading) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: mm.earsProgress == 0 ? null : mm.earsProgress,
                  minHeight: 12,
                  backgroundColor: Palette.bg,
                  color: Palette.you,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Text('${(mm.earsProgress * 100).toStringAsFixed(0)}%', style: const TextStyle(fontWeight: FontWeight.w700)),
                  const Spacer(),
                  TextButton(onPressed: mm.cancelEars, child: const Text('Cancel', style: TextStyle(color: Palette.them))),
                ],
              ),
            ] else ...[
              if (mm.earsError != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(mm.earsError!, style: const TextStyle(color: Palette.them, fontSize: 14)),
                ),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Palette.you,
                    foregroundColor: Palette.bg,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: mm.downloadEars,
                  icon: const Icon(Icons.download_rounded, size: 24),
                  label: const Text('Get the Ears (wifi)', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

/// Better brain — OPUS-MT Polish → English on ONNX Runtime, replacing ML Kit
/// for that one direction (English → Polish stays on ML Kit, which is good).
class _BrainPlusCard extends StatelessWidget {
  final ModelManager mm;
  const _BrainPlusCard({required this.mm});
  @override
  Widget build(BuildContext context) {
    final on = mm.activeBrainPlus;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Palette.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: on ? Palette.them.withOpacity(0.7) : Colors.transparent, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.psychology_rounded, color: on ? Palette.them : Palette.muted, size: 28),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Better Brain — Polish → English', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                    Text('A dedicated Polish translator · about 130 MB, once', style: TextStyle(color: Palette.muted, fontSize: 14)),
                  ],
                ),
              ),
              if (mm.brainPlusReady)
                Switch(
                  value: mm.useBrainPlus,
                  activeColor: Palette.them,
                  onChanged: (v) => mm.setUseBrainPlus(v),
                ),
            ],
          ),
          if (mm.brainPlusReady) ...[
            const SizedBox(height: 6),
            Text(on ? 'ON — Polish → English uses the dedicated translator.' : 'OFF — Polish → English uses the basic translator.',
                style: TextStyle(color: on ? Palette.them : Palette.muted, fontSize: 14, fontWeight: FontWeight.w600)),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: mm.deleteBrainPlus,
                child: const Text('Remove pack', style: TextStyle(color: Palette.muted)),
              ),
            ),
          ] else ...[
            const SizedBox(height: 12),
            if (mm.brainPlusDownloading) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: mm.brainPlusProgress == 0 ? null : mm.brainPlusProgress,
                  minHeight: 12,
                  backgroundColor: Palette.bg,
                  color: Palette.them,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Text('${(mm.brainPlusProgress * 100).toStringAsFixed(0)}%', style: const TextStyle(fontWeight: FontWeight.w700)),
                  const Spacer(),
                  TextButton(onPressed: mm.cancelBrainPlus, child: const Text('Cancel', style: TextStyle(color: Palette.them))),
                ],
              ),
            ] else ...[
              if (mm.brainPlusError != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(mm.brainPlusError!, style: const TextStyle(color: Palette.them, fontSize: 14)),
                ),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Palette.them,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: mm.downloadBrainPlus,
                  icon: const Icon(Icons.download_rounded, size: 24),
                  label: const Text('Get the Better Brain (wifi)', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

/// Sharper ears — Whisper large-v3-turbo. Much better on Polish, German,
/// Greek, Japanese; heavier, so it's an opt-in second pack with a switch.
class _EarsPlusCard extends StatelessWidget {
  final ModelManager mm;
  const _EarsPlusCard({required this.mm});
  @override
  Widget build(BuildContext context) {
    final on = mm.activeEarsPlus;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Palette.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: on ? Palette.gold.withOpacity(0.7) : Colors.transparent, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome_rounded, color: on ? Palette.gold : Palette.muted, size: 28),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Sharper Ears — Whisper turbo', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                    Text('Much better on Polish, German, Greek · about 550 MB, once', style: TextStyle(color: Palette.muted, fontSize: 14)),
                  ],
                ),
              ),
              if (mm.earsPlusReady)
                Switch(
                  value: mm.useEarsPlus,
                  activeColor: Palette.gold,
                  onChanged: (v) => mm.setUseEarsPlus(v),
                ),
            ],
          ),
          if (mm.earsPlusReady) ...[
            const SizedBox(height: 6),
            Text(on ? 'ON — conversations use the sharper ears (a little slower).' : 'OFF — conversations use the fast small ears.',
                style: TextStyle(color: on ? Palette.gold : Palette.muted, fontSize: 14, fontWeight: FontWeight.w600)),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: mm.deleteEarsPlus,
                child: const Text('Remove pack', style: TextStyle(color: Palette.muted)),
              ),
            ),
          ] else ...[
            const SizedBox(height: 12),
            if (mm.earsPlusDownloading) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: mm.earsPlusProgress == 0 ? null : mm.earsPlusProgress,
                  minHeight: 12,
                  backgroundColor: Palette.bg,
                  color: Palette.gold,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Text('${(mm.earsPlusProgress * 100).toStringAsFixed(0)}%', style: const TextStyle(fontWeight: FontWeight.w700)),
                  const Spacer(),
                  TextButton(onPressed: mm.cancelEarsPlus, child: const Text('Cancel', style: TextStyle(color: Palette.them))),
                ],
              ),
            ] else ...[
              if (mm.earsPlusError != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(mm.earsPlusError!, style: const TextStyle(color: Palette.them, fontSize: 14)),
                ),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Palette.gold,
                    foregroundColor: Palette.bg,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: mm.downloadEarsPlus,
                  icon: const Icon(Icons.download_rounded, size: 24),
                  label: const Text('Get the Sharper Ears (wifi)', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                ),
              ),
            ],
          ],
        ],
      ),
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
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('English — your side', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                Text(ok ? 'Ready' : 'Installs automatically with your first language',
                    style: TextStyle(color: ok ? Palette.ok : Palette.muted, fontSize: 14, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
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
