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
    'es': {'el', 'la', 'los', 'las', 'es', 'está', 'no', 'sí', 'por', 'para', 'con', 'una', 'un', 'qué',
      'dónde', 'cómo', 'gracias', 'hola', 'quiero', 'tengo', 'muy', 'bien', 'aquí', 'usted'},
    'it': {'il', 'la', 'le', 'gli', 'è', 'non', 'sì', 'per', 'con', 'una', 'un', 'che', 'dove', 'come',
      'grazie', 'ciao', 'buongiorno', 'vorrei', 'ho', 'molto', 'bene', 'qui', 'questo', 'sono'},
    'pt': {'o', 'os', 'as', 'é', 'não', 'sim', 'por', 'para', 'com', 'uma', 'um', 'que', 'onde', 'como',
      'obrigado', 'obrigada', 'olá', 'quero', 'tenho', 'muito', 'bem', 'aqui', 'você', 'está'},
    'nl': {'de', 'het', 'een', 'en', 'is', 'niet', 'ik', 'je', 'wij', 'met', 'wat', 'hoe', 'waar',
      'dank', 'bedankt', 'alstublieft', 'goed', 'ook', 'hebben', 'naar', 'voor', 'dit', 'dat'},
    'cs': {'je', 'to', 'ne', 'ano', 'na', 'se', 'jak', 'kde', 'co', 'já', 'ty', 'my', 'prosím',
      'děkuji', 'dobrý', 'den', 'mám', 'chci', 'velmi', 'dobře', 'tady', 'jsem', 'jste'},
    'sk': {'je', 'to', 'nie', 'áno', 'na', 'sa', 'ako', 'kde', 'čo', 'ja', 'ty', 'my', 'prosím',
      'ďakujem', 'dobrý', 'deň', 'mám', 'chcem', 'veľmi', 'dobre', 'tu', 'som', 'ste'},
    'hu': {'a', 'az', 'és', 'nem', 'igen', 'van', 'hogy', 'hol', 'mi', 'én', 'te', 'kérem', 'köszönöm',
      'jó', 'napot', 'szeretnék', 'nagyon', 'itt', 'egy', 'ez', 'ön'},
    'ro': {'este', 'nu', 'da', 'și', 'pe', 'cu', 'unde', 'ce', 'cum', 'eu', 'tu', 'vă', 'rog',
      'mulțumesc', 'bună', 'ziua', 'vreau', 'am', 'foarte', 'bine', 'aici', 'un', 'o'},
    'hr': {'je', 'to', 'ne', 'da', 'na', 'se', 'kako', 'gdje', 'što', 'ja', 'ti', 'mi', 'molim',
      'hvala', 'dobar', 'dan', 'imam', 'želim', 'vrlo', 'dobro', 'ovdje', 'sam', 'ste'},
    'sv': {'och', 'är', 'inte', 'ja', 'nej', 'jag', 'du', 'vi', 'en', 'ett', 'med', 'vad', 'hur', 'var',
      'tack', 'hej', 'snälla', 'bra', 'också', 'har', 'till', 'det', 'den'},
    'no': {'og', 'er', 'ikke', 'ja', 'nei', 'jeg', 'du', 'vi', 'en', 'et', 'med', 'hva', 'hvordan',
      'hvor', 'takk', 'hei', 'vær', 'så', 'snill', 'bra', 'også', 'har', 'til', 'det', 'den'},
    'da': {'og', 'er', 'ikke', 'ja', 'nej', 'jeg', 'du', 'vi', 'en', 'et', 'med', 'hvad', 'hvordan',
      'hvor', 'tak', 'hej', 'venligst', 'godt', 'også', 'har', 'til', 'det', 'den'},
    'fi': {'ja', 'on', 'ei', 'kyllä', 'minä', 'sinä', 'me', 'mitä', 'miten', 'missä', 'kiitos', 'hei',
      'ole', 'hyvä', 'hyvää', 'päivää', 'haluan', 'minulla', 'erittäin', 'tässä', 'tämä', 'se'},
    'tr': {'ve', 'bir', 'bu', 'değil', 'evet', 'hayır', 'ben', 'sen', 'biz', 'ne', 'nasıl', 'nerede',
      'lütfen', 'teşekkür', 'merhaba', 'istiyorum', 'var', 'çok', 'iyi', 'burada', 'için', 'ile'},
    'vi': {'và', 'là', 'không', 'vâng', 'tôi', 'bạn', 'chúng', 'gì', 'như', 'thế', 'nào', 'ở', 'đâu',
      'xin', 'cảm', 'ơn', 'chào', 'muốn', 'có', 'rất', 'tốt', 'đây', 'này'},
    'id': {'dan', 'adalah', 'tidak', 'ya', 'saya', 'anda', 'kami', 'apa', 'bagaimana', 'di', 'mana',
      'tolong', 'terima', 'kasih', 'halo', 'mau', 'ada', 'sangat', 'baik', 'sini', 'ini', 'itu', 'untuk'},
    'tl': {'at', 'ay', 'hindi', 'oo', 'ako', 'ikaw', 'kami', 'ano', 'paano', 'saan', 'po', 'salamat',
      'kumusta', 'gusto', 'mayroon', 'may', 'napaka', 'mabuti', 'dito', 'ito', 'ang', 'ng', 'sa'},
  };

  /// Non-Latin scripts: presence of the script settles it instantly.
  static const Map<String, String> _scripts = {
    'ja': r'[\u3040-\u30ff\u4e00-\u9fff]',
    'zh': r'[\u4e00-\u9fff]',
    'ko': r'[\uac00-\ud7af\u1100-\u11ff]',
    'el': r'[\u0370-\u03ff]',
    'ru': r'[\u0400-\u04ff]',
    'uk': r'[\u0400-\u04ff]',
    'th': r'[\u0e00-\u0e7f]',
    'hi': r'[\u0900-\u097f]',
    'ar': r'[\u0600-\u06ff]',
    'he': r'[\u0590-\u05ff]',
  };

  static const Map<String, String> _accents = {
    'pl': 'ąćęłńóśźż',
    'de': 'äöüß',
    'fr': 'éèêàçùâîôûë',
    'ga': 'áéíóú',
    'es': 'áéíóúñ¿¡',
    'it': 'àèéìòù',
    'pt': 'ãõáéíóúâêôç',
    'cs': 'ěščřžýáíéúůďťň',
    'sk': 'áäčďéíĺľňóôŕšťúýž',
    'hu': 'áéíóöőúüű',
    'ro': 'ăâîșț',
    'hr': 'čćđšž',
    'sv': 'åäö',
    'no': 'æøå',
    'da': 'æøå',
    'fi': 'äöå',
    'tr': 'çğıöşü',
    'vi': 'ăâđêôơưàảãáạằẳẵắặầẩẫấậèẻẽéẹềểễếệìỉĩíịòỏõóọồổỗốộờởỡớợùủũúụừửữứựỳỷỹýỵ',
  };

  /// True if [text] is English rather than [other].
  static bool isEnglish(String text, Language other) {
    final t = text.toLowerCase();
    final script = _scripts[other.code];
    if (script != null) return !RegExp(script).hasMatch(t);

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
