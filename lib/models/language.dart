class Language {
  final String code; // ISO 639-1
  final String name;
  final String native;
  final String flag;
  final String nllbCode; // Flores-200 code used by NLLB
  final String ttsLocale; // BCP-47 for the phone's TTS voice

  const Language({
    required this.code,
    required this.name,
    required this.native,
    required this.flag,
    required this.nllbCode,
    required this.ttsLocale,
  });
}

const english = Language(
  code: 'en', name: 'English', native: 'English', flag: '🇺🇸',
  nllbCode: 'eng_Latn', ttsLocale: 'en-US',
);

/// Full catalog. First six are Robert's trip languages; the rest are common
/// travel languages. All are covered by the one NLLB pack.
const travelLanguages = <Language>[
  Language(code: 'pl', name: 'Polish', native: 'Polski', flag: '🇵🇱', nllbCode: 'pol_Latn', ttsLocale: 'pl-PL'),
  Language(code: 'de', name: 'German', native: 'Deutsch', flag: '🇩🇪', nllbCode: 'deu_Latn', ttsLocale: 'de-DE'),
  Language(code: 'fr', name: 'French', native: 'Français', flag: '🇫🇷', nllbCode: 'fra_Latn', ttsLocale: 'fr-FR'),
  Language(code: 'el', name: 'Greek', native: 'Ελληνικά', flag: '🇬🇷', nllbCode: 'ell_Grek', ttsLocale: 'el-GR'),
  Language(code: 'ja', name: 'Japanese', native: '日本語', flag: '🇯🇵', nllbCode: 'jpn_Jpan', ttsLocale: 'ja-JP'),
  Language(code: 'ga', name: 'Irish', native: 'Gaeilge', flag: '🇮🇪', nllbCode: 'gle_Latn', ttsLocale: 'ga-IE'),
  Language(code: 'es', name: 'Spanish', native: 'Español', flag: '🇪🇸', nllbCode: 'spa_Latn', ttsLocale: 'es-ES'),
  Language(code: 'it', name: 'Italian', native: 'Italiano', flag: '🇮🇹', nllbCode: 'ita_Latn', ttsLocale: 'it-IT'),
  Language(code: 'pt', name: 'Portuguese', native: 'Português', flag: '🇵🇹', nllbCode: 'por_Latn', ttsLocale: 'pt-PT'),
  Language(code: 'nl', name: 'Dutch', native: 'Nederlands', flag: '🇳🇱', nllbCode: 'nld_Latn', ttsLocale: 'nl-NL'),
  Language(code: 'cs', name: 'Czech', native: 'Čeština', flag: '🇨🇿', nllbCode: 'ces_Latn', ttsLocale: 'cs-CZ'),
  Language(code: 'sk', name: 'Slovak', native: 'Slovenčina', flag: '🇸🇰', nllbCode: 'slk_Latn', ttsLocale: 'sk-SK'),
  Language(code: 'hu', name: 'Hungarian', native: 'Magyar', flag: '🇭🇺', nllbCode: 'hun_Latn', ttsLocale: 'hu-HU'),
  Language(code: 'ro', name: 'Romanian', native: 'Română', flag: '🇷🇴', nllbCode: 'ron_Latn', ttsLocale: 'ro-RO'),
  Language(code: 'hr', name: 'Croatian', native: 'Hrvatski', flag: '🇭🇷', nllbCode: 'hrv_Latn', ttsLocale: 'hr-HR'),
  Language(code: 'sv', name: 'Swedish', native: 'Svenska', flag: '🇸🇪', nllbCode: 'swe_Latn', ttsLocale: 'sv-SE'),
  Language(code: 'no', name: 'Norwegian', native: 'Norsk', flag: '🇳🇴', nllbCode: 'nob_Latn', ttsLocale: 'nb-NO'),
  Language(code: 'da', name: 'Danish', native: 'Dansk', flag: '🇩🇰', nllbCode: 'dan_Latn', ttsLocale: 'da-DK'),
  Language(code: 'fi', name: 'Finnish', native: 'Suomi', flag: '🇫🇮', nllbCode: 'fin_Latn', ttsLocale: 'fi-FI'),
  Language(code: 'tr', name: 'Turkish', native: 'Türkçe', flag: '🇹🇷', nllbCode: 'tur_Latn', ttsLocale: 'tr-TR'),
  Language(code: 'ru', name: 'Russian', native: 'Русский', flag: '🇷🇺', nllbCode: 'rus_Cyrl', ttsLocale: 'ru-RU'),
  Language(code: 'uk', name: 'Ukrainian', native: 'Українська', flag: '🇺🇦', nllbCode: 'ukr_Cyrl', ttsLocale: 'uk-UA'),
  Language(code: 'zh', name: 'Chinese', native: '中文', flag: '🇨🇳', nllbCode: 'zho_Hans', ttsLocale: 'zh-CN'),
  Language(code: 'ko', name: 'Korean', native: '한국어', flag: '🇰🇷', nllbCode: 'kor_Hang', ttsLocale: 'ko-KR'),
  Language(code: 'vi', name: 'Vietnamese', native: 'Tiếng Việt', flag: '🇻🇳', nllbCode: 'vie_Latn', ttsLocale: 'vi-VN'),
  Language(code: 'th', name: 'Thai', native: 'ไทย', flag: '🇹🇭', nllbCode: 'tha_Thai', ttsLocale: 'th-TH'),
  Language(code: 'id', name: 'Indonesian', native: 'Bahasa Indonesia', flag: '🇮🇩', nllbCode: 'ind_Latn', ttsLocale: 'id-ID'),
  Language(code: 'tl', name: 'Filipino', native: 'Tagalog', flag: '🇵🇭', nllbCode: 'tgl_Latn', ttsLocale: 'fil-PH'),
  Language(code: 'hi', name: 'Hindi', native: 'हिन्दी', flag: '🇮🇳', nllbCode: 'hin_Deva', ttsLocale: 'hi-IN'),
  Language(code: 'ar', name: 'Arabic', native: 'العربية', flag: '🇸🇦', nllbCode: 'arb_Arab', ttsLocale: 'ar-SA'),
  Language(code: 'he', name: 'Hebrew', native: 'עברית', flag: '🇮🇱', nllbCode: 'heb_Hebr', ttsLocale: 'he-IL'),
];

Language? languageByCode(String code) {
  for (final l in travelLanguages) {
    if (l.code == code) return l;
  }
  return null;
}

/// One downloadable file inside a pack.
class PackFile {
  final String url;
  final String fileName;
  final int sizeMb;
  const PackFile({required this.url, required this.fileName, required this.sizeMb});
}

/// A pack = one engine, possibly several files, downloaded together.
class EnginePack {
  final String id;
  final String title;
  final String subtitle;
  final List<PackFile> files;
  const EnginePack({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.files,
  });
  int get sizeMb => files.fold(0, (a, f) => a + f.sizeMb);
}

const _hfWhisper = 'https://huggingface.co/ggerganov/whisper.cpp/resolve/main';
const _hfNllb = 'https://huggingface.co/Xenova/nllb-200-distilled-600M/resolve/main';

const whisperPack = EnginePack(
  id: 'whisper',
  title: 'Ears — Whisper large-v3-turbo',
  subtitle: 'Hears every language, q8_0',
  files: [
    PackFile(
      url: '$_hfWhisper/ggml-large-v3-turbo-q8_0.bin',
      fileName: 'ggml-large-v3-turbo-q8_0.bin',
      sizeMb: 874,
    ),
  ],
);

const whisperSmallPack = EnginePack(
  id: 'whisper_small',
  title: 'Ears (fast) — Whisper small',
  subtitle: 'Much quicker, a little less sharp. Pick one Ears in Diagnostics.',
  files: [
    PackFile(
      url: '$_hfWhisper/ggml-small-q8_0.bin',
      fileName: 'ggml-small-q8_0.bin',
      sizeMb: 264,
    ),
  ],
);

const vadPack = EnginePack(
  id: 'vad',
  title: 'Reflexes — Silero VAD',
  subtitle: 'Knows the instant someone starts and stops talking',
  files: [
    PackFile(
      url: 'https://raw.githubusercontent.com/snakers4/silero-vad/master/src/silero_vad/data/silero_vad.onnx',
      fileName: 'silero_vad.onnx',
      sizeMb: 2,
    ),
  ],
);

const nllbPack = EnginePack(
  id: 'nllb',
  title: 'Brain — NLLB-200',
  subtitle: 'Translates 200 languages, int8',
  files: [
    PackFile(url: '$_hfNllb/onnx/encoder_model_quantized.onnx', fileName: 'nllb_encoder.onnx', sizeMb: 419),
    PackFile(url: '$_hfNllb/onnx/decoder_model_merged_quantized.onnx', fileName: 'nllb_decoder.onnx', sizeMb: 476),
    PackFile(url: '$_hfNllb/tokenizer.json', fileName: 'nllb_tokenizer.json', sizeMb: 17),
  ],
);

const allPacks = [whisperPack, whisperSmallPack, nllbPack, vadPack];
