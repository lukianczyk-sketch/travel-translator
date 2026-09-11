class Language {
  final String code; // ISO 639-1 (what Whisper reports)
  final String name;
  final String native;
  final String flag;
  final String nllbCode; // Flores-200 code used by NLLB
  final int packMb; // approx size of this language's translation pack

  const Language({
    required this.code,
    required this.name,
    required this.native,
    required this.flag,
    required this.nllbCode,
    required this.packMb,
  });
}

const english = Language(
  code: 'en', name: 'English', native: 'English', flag: '🇺🇸',
  nllbCode: 'eng_Latn', packMb: 0,
);

/// Robert's travel set. Order = display order.
const travelLanguages = <Language>[
  Language(code: 'pl', name: 'Polish', native: 'Polski', flag: '🇵🇱',
      nllbCode: 'pol_Latn', packMb: 40),
  Language(code: 'de', name: 'German', native: 'Deutsch', flag: '🇩🇪',
      nllbCode: 'deu_Latn', packMb: 40),
  Language(code: 'fr', name: 'French', native: 'Français', flag: '🇫🇷',
      nllbCode: 'fra_Latn', packMb: 40),
  Language(code: 'el', name: 'Greek', native: 'Ελληνικά', flag: '🇬🇷',
      nllbCode: 'ell_Grek', packMb: 40),
  Language(code: 'ja', name: 'Japanese', native: '日本語', flag: '🇯🇵',
      nllbCode: 'jpn_Jpan', packMb: 40),
  Language(code: 'ga', name: 'Irish', native: 'Gaeilge', flag: '🇮🇪',
      nllbCode: 'gle_Latn', packMb: 40),
];

Language? languageByCode(String code) {
  for (final l in travelLanguages) {
    if (l.code == code) return l;
  }
  return null;
}

/// The shared engines every language relies on.
class EnginePack {
  final String id;
  final String title;
  final String subtitle;
  final String url;
  final String fileName;
  final int sizeMb;

  const EnginePack({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.url,
    required this.fileName,
    required this.sizeMb,
  });
}

const whisperPack = EnginePack(
  id: 'whisper',
  title: 'Ears — Whisper large-v3-turbo',
  subtitle: 'Speech recognition, all languages, q8_0',
  url:
      'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q8_0.bin',
  fileName: 'ggml-large-v3-turbo-q8_0.bin',
  sizeMb: 874,
);

const nllbPack = EnginePack(
  id: 'nllb',
  title: 'Brain — NLLB-200 1.3B',
  subtitle: 'Translation engine, int8',
  url: '', // wired in drop 2
  fileName: 'nllb-200-distilled-1.3B-int8',
  sizeMb: 1300,
);
