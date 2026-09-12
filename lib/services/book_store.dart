import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One line of conversation, kept for history and pinning.
class Entry {
  final int time; // ms since epoch
  final bool fromThem;
  final String original;
  final String translated;
  final String speakLocale;
  final String langCode; // the non-English language of that conversation

  const Entry({
    required this.time,
    required this.fromThem,
    required this.original,
    required this.translated,
    required this.speakLocale,
    required this.langCode,
  });

  Map<String, dynamic> toJson() => {
        't': time,
        'm': fromThem,
        'o': original,
        'r': translated,
        'l': speakLocale,
        'c': langCode,
      };

  factory Entry.fromJson(Map<String, dynamic> j) => Entry(
        time: (j['t'] as num).toInt(),
        fromThem: j['m'] as bool,
        original: j['o'] as String,
        translated: j['r'] as String,
        speakLocale: j['l'] as String,
        langCode: j['c'] as String,
      );

  String get key => '$original|$translated';
}

/// Conversation history + pinned phrasebook, saved on the phone.
class BookStore extends ChangeNotifier {
  BookStore._();
  static final BookStore instance = BookStore._();

  static const int maxHistory = 400;
  final List<Entry> history = []; // newest first
  final List<Entry> pins = []; // newest first
  bool _loaded = false;

  Future<void> init() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    history.addAll(_read(prefs.getString('book_history')));
    pins.addAll(_read(prefs.getString('book_pins')));
    _loaded = true;
    notifyListeners();
  }

  List<Entry> _read(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List;
      return list.map((e) => Entry.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('book_history', jsonEncode(history.map((e) => e.toJson()).toList()));
    await prefs.setString('book_pins', jsonEncode(pins.map((e) => e.toJson()).toList()));
  }

  Future<void> addHistory(Entry e) async {
    history.insert(0, e);
    if (history.length > maxHistory) history.removeRange(maxHistory, history.length);
    notifyListeners();
    await _save();
  }

  bool isPinned(Entry e) => pins.any((p) => p.key == e.key);

  Future<void> togglePin(Entry e) async {
    if (isPinned(e)) {
      pins.removeWhere((p) => p.key == e.key);
    } else {
      pins.insert(0, e);
    }
    notifyListeners();
    await _save();
  }

  Future<void> clearHistory() async {
    history.clear();
    notifyListeners();
    await _save();
  }
}
