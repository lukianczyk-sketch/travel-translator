import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/language.dart';
import '../services/book_store.dart';
import '../services/tts.dart';
import '../theme.dart';

class BookScreen extends StatefulWidget {
  const BookScreen({super.key});

  @override
  State<BookScreen> createState() => _BookScreenState();
}

class _BookScreenState extends State<BookScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  final Speaker _speaker = Speaker();

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _speak(Entry e) async {
    HapticFeedback.selectionClick();
    await _speaker.say(e.translated, e.speakLocale);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: BookStore.instance,
      builder: (context, _) {
        final book = BookStore.instance;
        return SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(24, 16, 24, 0),
                child: Text('Book', style: headline),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(24, 6, 24, 12),
                child: Text(
                  'Tap a line to hear it again. Star it to keep it.',
                  style: TextStyle(color: Palette.muted, fontSize: 17, fontWeight: FontWeight.w600),
                ),
              ),
              TabBar(
                controller: _tabs,
                indicatorColor: Palette.you,
                indicatorWeight: 4,
                labelColor: Palette.text,
                unselectedLabelColor: Palette.muted,
                labelStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 1),
                tabs: [
                  Tab(text: 'RECENT (${book.history.length})'),
                  Tab(text: 'PINNED (${book.pins.length})'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabs,
                  children: [
                    _EntryList(
                      entries: book.history,
                      empty: 'Nothing yet. Have a conversation and it shows up here.',
                      onSpeak: _speak,
                      trailing: book.history.isEmpty
                          ? null
                          : TextButton(
                              onPressed: () => _confirmClear(context),
                              child: const Text('Clear history', style: TextStyle(color: Palette.muted)),
                            ),
                    ),
                    _EntryList(
                      entries: book.pins,
                      empty: 'Star a line in Recent to pin it here for quick replay.',
                      onSpeak: _speak,
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

  Future<void> _confirmClear(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Palette.card,
        title: const Text('Clear history?'),
        content: const Text('Pinned phrases are kept.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear', style: TextStyle(color: Palette.them)),
          ),
        ],
      ),
    );
    if (ok == true) await BookStore.instance.clearHistory();
  }
}

class _EntryList extends StatelessWidget {
  final List<Entry> entries;
  final String empty;
  final Future<void> Function(Entry) onSpeak;
  final Widget? trailing;
  const _EntryList({required this.entries, required this.empty, required this.onSpeak, this.trailing});

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(empty,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Palette.muted, fontSize: 18, height: 1.4)),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: entries.length + (trailing != null ? 1 : 0),
      itemBuilder: (context, i) {
        if (i == entries.length) return Center(child: trailing);
        final e = entries[i];
        final lang = languageByCode(e.langCode);
        final color = e.fromThem ? Palette.them : Palette.you;
        final pinned = BookStore.instance.isPinned(e);
        return GestureDetector(
          onTap: () => onSpeak(e),
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
            decoration: BoxDecoration(
              color: Palette.card,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 5,
                  height: 64,
                  margin: const EdgeInsets.only(right: 12),
                  decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${lang?.flag ?? ''} ${e.fromThem ? 'THEM' : 'YOU'}',
                        style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 2),
                      ),
                      const SizedBox(height: 6),
                      Text(e.original, style: const TextStyle(color: Palette.muted, fontSize: 15, height: 1.3)),
                      const SizedBox(height: 4),
                      Text(e.translated,
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, height: 1.2)),
                    ],
                  ),
                ),
                IconButton(
                  iconSize: 28,
                  color: pinned ? Palette.gold : Palette.muted,
                  icon: Icon(pinned ? Icons.star_rounded : Icons.star_outline_rounded),
                  onPressed: () => BookStore.instance.togglePin(e),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
