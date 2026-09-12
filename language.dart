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

/// Robert's travel set. Order = display order.
const travelLanguages = <Language>[
  Language(code: 'pl', name: 'Polish', native: 'Polski', flag: '🇵🇱',
      nllbCode: 'pol_Latn', ttsLocale: 'pl-PL'),
  Language(code: 'de', name: 'German', native: 'Deutsch', flag: '🇩🇪',
      nllbCode: 'deu_Latn', ttsLocale: 'de-DE'),
  Language(code: 'fr', name: 'French', native: 'Français', flag: '🇫🇷',
      nllbCode: 'fra_Latn', ttsLocale: 'fr-FR'),
  Language(code: 'el', name: 'Greek', native: 'Ελληνικά', flag: '🇬🇷',
      nllbCode: 'ell_Grek', ttsLocale: 'el-GR'),
  Language(code: 'ja', name: 'Japanese', native: '日本語', flag: '🇯🇵',
      nllbCode: 'jpn_Jpan', ttsLocale: 'ja-JP'),
  Language(code: 'ga', name: 'Irish', native: 'Gaeilge', flag: '🇮🇪',
      nllbCode: 'gle_Latn', ttsLocale: 'ga-IE'),
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

const vadPack = EnginePack(
  id: 'vad',
  title: 'Reflexes — Silero VAD',
  subtitle: 'Knows the instant someone starts and stops talking',
  files: [
    PackFile(
      url: 'https://raw.githubusercontent.com/snakers4/silero-vad/master/src/silero_vad/data/silero_vad.onnx',
      fileName: 'silero_vad.onnx',
      sizeMb: 3,
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

const allPacks = [whisperPack, nllbPack, vadPack];
