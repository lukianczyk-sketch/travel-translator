import '../models/language.dart';

/// Decides which way a sentence is going. The conversation is always
/// English <-> one chosen language, so this only has to answer one question:
/// "is this English?" Script checks handle Japanese/Greek instantly; the Latin
/// languages use accents plus the most common function words.
class LangGuess {
  static const _en = {
    'the', 'and', 'is', 'are', 'you', 'to', 'of', 'a', 'in', 'it', 'that', 'this', 'we', 'i', 'my',
    'for', 'on', 'with', 'have', 'do', 'not', 'can', 'what', 'where', 'how', 'much', 'please',
    'thank', 'thanks', 'yes', 'no', 'want', 'need', 'like', 'good', 'hello', 'hi', 'okay', 'ok',
  };

  static const Map<String, Set<String>> _words = {
    'pl': {'nie', 'jest', 'się', 'to', 'na', 'co', 'jak', 'tak', 'czy', 'do', 'ja', 'ty', 'gdzie',
      'dzień', 'dobry', 'proszę', 'dziękuję', 'ile', 'mam', 'chcę', 'jestem', 'bardzo', 'dobrze'},
    'de': {'der', 'die', 'das', 'und', 'ist', 'nicht', 'ich', 'sie', 'wir', 'ein', 'eine', 'zu',
      'mit', 'was', 'wie', 'wo', 'bitte', 'danke', 'ja', 'nein', 'haben', 'gut', 'auch', 'kein'},
    'fr': {'le', 'la', 'les', 'et', 'est', 'pas', 'je', 'vous', 'nous', 'un', 'une', 'de', 'des',
      'que', 'qui', 'où', 'merci', 'bonjour', 'oui', 'non', 'avec', 'pour', 'très', 'bien'},
    'ga': {'agus', 'tá', 'níl', 'an', 'na', 'ag', 'mé', 'tú', 'sé', 'sí', 'go', 'raibh', 'maith',
      'cad', 'conas', 'dia', 'duit', 'le', 'ar', 'is', 'ní', 'sea', 'bhfuil'},
  };

  static const Map<String, String> _accents = {
    'pl': 'ąćęłńóśźż',
    'de': 'äöüß',
    'fr': 'éèêàçùâîôûë',
    'ga': 'áéíóú',
  };

  /// True if [text] is English rather than [other].
  static bool isEnglish(String text, Language other) {
    final t = text.toLowerCase();
    if (other.code == 'ja') return !RegExp(r'[\u3040-\u30ff\u4e00-\u9fff]').hasMatch(t);
    if (other.code == 'el') return !RegExp(r'[\u0370-\u03ff]').hasMatch(t);

    var foreign = 0.0;
    var english = 0.0;
    final accents = _accents[other.code] ?? '';
    for (final ch in t.runes) {
      if (accents.contains(String.fromCharCode(ch))) foreign += 2;
    }
    final words = t.split(RegExp(r'[^\p{L}]+', unicode: true)).where((w) => w.isNotEmpty);
    final theirs = _words[other.code] ?? const <String>{};
    for (final w in words) {
      if (_en.contains(w)) english += 1;
      if (theirs.contains(w)) foreign += 1;
    }
    if (foreign == 0 && english == 0) return true; // unknown → assume English
    return english >= foreign;
  }
}
