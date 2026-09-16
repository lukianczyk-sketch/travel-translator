/// Short everyday phrases the on-device translator gets wrong ("Hello?" →
/// nonsense). Exact-match only, after lower-casing and stripping punctuation,
/// so it never touches real sentences. Both directions.
class Glossary {
  static const Map<String, Map<String, String>> _enTo = {
    'pl': {
      'hello': 'Cześć', 'hi': 'Cześć', 'hey': 'Hej', 'good morning': 'Dzień dobry',
      'good afternoon': 'Dzień dobry', 'good evening': 'Dobry wieczór', 'good night': 'Dobranoc',
      'goodbye': 'Do widzenia', 'bye': 'Pa', 'see you': 'Do zobaczenia',
      'thank you': 'Dziękuję', 'thanks': 'Dzięki', 'thank you very much': 'Dziękuję bardzo',
      'please': 'Proszę', 'yes': 'Tak', 'no': 'Nie', 'okay': 'Dobrze', 'ok': 'Dobrze',
      'excuse me': 'Przepraszam', 'sorry': 'Przepraszam', "i'm sorry": 'Przepraszam',
      'cheers': 'Na zdrowie', "you're welcome": 'Proszę bardzo', 'no problem': 'Nie ma problemu',
      'how much': 'Ile to kosztuje?', 'how much is it': 'Ile to kosztuje?', 'how much is this': 'Ile to kosztuje?',
      'where is the bathroom': 'Gdzie jest toaleta?', 'where is the toilet': 'Gdzie jest toaleta?',
      'the bill please': 'Poproszę rachunek', 'check please': 'Poproszę rachunek',
      'i dont understand': 'Nie rozumiem', "i don't understand": 'Nie rozumiem',
      'do you speak english': 'Czy mówisz po angielsku?', 'help': 'Pomocy!',
      'water': 'Woda', 'beer': 'Piwo', 'coffee': 'Kawa', 'tea': 'Herbata',
    },
    'de': {
      'hello': 'Hallo', 'hi': 'Hallo', 'hey': 'Hey', 'good morning': 'Guten Morgen',
      'good afternoon': 'Guten Tag', 'good evening': 'Guten Abend', 'good night': 'Gute Nacht',
      'goodbye': 'Auf Wiedersehen', 'bye': 'Tschüss', 'see you': 'Bis später',
      'thank you': 'Danke', 'thanks': 'Danke', 'thank you very much': 'Vielen Dank',
      'please': 'Bitte', 'yes': 'Ja', 'no': 'Nein', 'okay': 'Okay', 'ok': 'Okay',
      'excuse me': 'Entschuldigung', 'sorry': 'Entschuldigung', "i'm sorry": 'Es tut mir leid',
      'cheers': 'Prost', "you're welcome": 'Gern geschehen', 'no problem': 'Kein Problem',
      'how much': 'Wie viel kostet das?', 'how much is it': 'Wie viel kostet das?', 'how much is this': 'Wie viel kostet das?',
      'where is the bathroom': 'Wo ist die Toilette?', 'where is the toilet': 'Wo ist die Toilette?',
      'the bill please': 'Die Rechnung, bitte', 'check please': 'Die Rechnung, bitte',
      'i dont understand': 'Ich verstehe nicht', "i don't understand": 'Ich verstehe nicht',
      'do you speak english': 'Sprechen Sie Englisch?', 'help': 'Hilfe!',
      'water': 'Wasser', 'beer': 'Bier', 'coffee': 'Kaffee', 'tea': 'Tee',
    },
  };

  static const Map<String, Map<String, String>> _toEn = {
    'pl': {
      'cześć': 'Hi', 'hej': 'Hey', 'halo': 'Hello?', 'dzień dobry': 'Good morning', 'dobry wieczór': 'Good evening',
      'dobranoc': 'Good night', 'do widzenia': 'Goodbye', 'pa': 'Bye', 'do zobaczenia': 'See you',
      'dziękuję': 'Thank you', 'dzięki': 'Thanks', 'dziękuję bardzo': 'Thank you very much',
      'proszę': 'Please', 'tak': 'Yes', 'nie': 'No', 'dobrze': 'Okay', 'przepraszam': 'Excuse me / sorry',
      'na zdrowie': 'Cheers', 'proszę bardzo': "You're welcome", 'nie ma problemu': 'No problem',
      'ile to kosztuje': 'How much is it?', 'gdzie jest toaleta': 'Where is the toilet?',
      'nie rozumiem': "I don't understand", 'smacznego': 'Enjoy your meal', 'słucham': 'Yes? / Pardon?',
    },
    'de': {
      'hallo': 'Hello', 'hey': 'Hey', 'guten morgen': 'Good morning', 'guten tag': 'Good day', 'guten abend': 'Good evening',
      'gute nacht': 'Good night', 'auf wiedersehen': 'Goodbye', 'tschüss': 'Bye', 'bis später': 'See you later',
      'danke': 'Thanks', 'vielen dank': 'Thank you very much', 'bitte': 'Please / you\'re welcome',
      'ja': 'Yes', 'nein': 'No', 'okay': 'Okay', 'entschuldigung': 'Excuse me / sorry',
      'prost': 'Cheers', 'kein problem': 'No problem', 'wie viel kostet das': 'How much is it?',
      'wo ist die toilette': 'Where is the toilet?', 'ich verstehe nicht': "I don't understand",
      'guten appetit': 'Enjoy your meal', 'wie bitte': 'Pardon?',
    },
  };

  /// Polish food & menu words the translator gets wrong. Checked INSIDE sentences
  /// too: if the sentence had "twarożek" and the English lacks "cottage cheese",
  /// the meaning is appended so it's never lost. Keys are lower-case stems; a few
  /// common inflections are listed.
  static const Map<String, String> plFood = {
    'twarożek': 'cottage cheese', 'twaróg': 'cottage cheese', 'twarożkiem': 'cottage cheese', 'twarogu': 'cottage cheese',
    'jajka na miękko': 'soft-boiled eggs', 'jajko na miękko': 'soft-boiled egg', 'jajka na twardo': 'hard-boiled eggs',
    'jajecznica': 'scrambled eggs', 'jajecznicę': 'scrambled eggs', 'jajka': 'eggs', 'jajko': 'egg',
    'kiełbaski': 'sausages', 'kiełbasa': 'sausage', 'kiełbasę': 'sausage', 'parówki': 'frankfurters',
    'pieczywo': 'bread', 'chleb': 'bread', 'chleba': 'bread', 'bułka': 'bread roll', 'bułki': 'bread rolls', 'bułkę': 'bread roll',
    'masło': 'butter', 'masłem': 'butter', 'ser': 'cheese', 'sera': 'cheese', 'serem': 'cheese', 'szynka': 'ham', 'szynką': 'ham',
    'śniadanie': 'breakfast', 'śniadania': 'breakfast', 'śniadaniu': 'breakfast', 'obiad': 'lunch', 'obiadu': 'lunch', 'kolacja': 'dinner', 'kolację': 'dinner',
    'herbata': 'tea', 'herbatę': 'tea', 'herbaty': 'tea', 'kawa': 'coffee', 'kawę': 'coffee', 'kawy': 'coffee',
    'woda': 'water', 'wodę': 'water', 'wody': 'water', 'piwo': 'beer', 'piwa': 'beer', 'wino': 'wine', 'wina': 'wine',
    'sok': 'juice', 'soku': 'juice', 'mleko': 'milk', 'mleka': 'milk',
    'kanapka': 'sandwich', 'kanapkę': 'sandwich', 'kanapki': 'sandwiches',
    'rzodkiewka': 'radish', 'rzodkiewką': 'radish', 'szczypiorek': 'chives', 'szczypiorkiem': 'chives',
    'jogurt': 'yogurt', 'jogurtem': 'yogurt', 'owoce': 'fruit', 'owocami': 'fruit', 'warzywa': 'vegetables', 'warzywami': 'vegetables',
    'omlet': 'omelet', 'omleta': 'omelet', 'naleśniki': 'pancakes', 'naleśnik': 'pancake',
    'pierogi': 'pierogi (dumplings)', 'pierogów': 'pierogi (dumplings)', 'bigos': 'bigos (hunter\'s stew)', 'żurek': 'żurek (sour rye soup)',
    'barszcz': 'beetroot soup', 'rosół': 'chicken broth', 'kotlet schabowy': 'breaded pork cutlet', 'schabowy': 'breaded pork cutlet',
    'placki ziemniaczane': 'potato pancakes', 'gołąbki': 'cabbage rolls', 'zapiekanka': 'zapiekanka (baguette pizza)',
    'sernik': 'cheesecake', 'makowiec': 'poppy-seed cake', 'pączek': 'doughnut', 'pączki': 'doughnuts', 'ciasto': 'cake', 'ciasta': 'cake',
    'lody': 'ice cream', 'zupa': 'soup', 'zupę': 'soup', 'zupy': 'soup', 'ryba': 'fish', 'rybę': 'fish', 'kurczak': 'chicken', 'kurczaka': 'chicken',
    'wieprzowina': 'pork', 'wołowina': 'beef', 'ziemniaki': 'potatoes', 'frytki': 'fries', 'sałatka': 'salad', 'sałatkę': 'salad',
    'ogórek': 'cucumber', 'pomidor': 'tomato', 'pomidory': 'tomatoes', 'cebula': 'onion', 'grzyby': 'mushrooms', 'kapusta': 'cabbage',
    'rachunek': 'the bill', 'menu': 'menu', 'karta': 'menu', 'kelner': 'waiter', 'kelnerka': 'waitress', 'napiwek': 'tip',
    'smacznego': 'enjoy your meal', 'na zdrowie': 'cheers',
  };

  /// For a Polish source sentence, returns "(term: meaning)" notes for food words
  /// whose English meaning is missing from the translation. Empty if all present.
  static String foodNotes(String src, String translated) {
    if (src.isEmpty) return '';
    final low = ' ${src.toLowerCase()} ';
    final tl = translated.toLowerCase();
    final notes = <String>[];
    final seen = <String>{};
    // Check two-word entries first, then single words.
    final keys = plFood.keys.toList()..sort((a, b) => b.length.compareTo(a.length));
    for (final k in keys) {
      if (!low.contains(RegExp('[^\\p{L}]${RegExp.escape(k)}[^\\p{L}]', unicode: true))) continue;
      final meaning = plFood[k]!;
      final core = meaning.split(' (').first.toLowerCase();
      if (seen.contains(core)) continue;
      seen.add(core);
      if (!tl.contains(core)) notes.add('$k = $meaning');
      if (notes.length >= 3) break;
    }
    return notes.isEmpty ? '' : ' (${notes.join('; ')})';
  }

  static String _key(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}\s\x27]', unicode: true), '').replaceAll(RegExp(r'\s+'), ' ').trim();

  /// Returns a fixed translation for a short everyday phrase, or null.
  static String? lookup(String text, String src, String tgt) {
    final k = _key(text);
    if (k.isEmpty || k.split(' ').length > 5) return null;
    final table = src == 'en' ? _enTo[tgt] : (tgt == 'en' ? _toEn[src] : null);
    final hit = table?[k];
    if (hit == null) return null;
    // "Hello?" (answering the phone / checking someone's there) → the local "Halo?"/"Hallo?".
    if (src == 'en' && k == 'hello' && text.trim().endsWith('?')) return tgt == 'pl' ? 'Halo?' : 'Hallo?';
    return hit;
  }
}
