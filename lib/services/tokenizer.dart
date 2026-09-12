import 'dart:convert';
import 'dart:io';

/// Tokenizer for NLLB-200, read from the Hugging Face `tokenizer.json`.
/// Metaspace pre-tokenization (spaces → ▁) + byte-free BPE over merges.
class NllbTokenizer {
  final Map<String, int> _vocab;
  final Map<int, String> _idToToken;
  final Map<String, int> _mergeRank; // "a b" -> rank
  final int unkId;
  final int eosId;
  final int padId;
  final Map<String, int> _langIds;

  NllbTokenizer._(this._vocab, this._idToToken, this._mergeRank, this.unkId,
      this.eosId, this.padId, this._langIds);

  static const String _space = '\u2581'; // ▁

  static NllbTokenizer load(String path) {
    final json = jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
    final model = json['model'] as Map<String, dynamic>;
    final vocabRaw = model['vocab'] as Map<String, dynamic>;
    final vocab = <String, int>{};
    vocabRaw.forEach((k, v) => vocab[k] = (v as num).toInt());

    // Added tokens (specials + language codes) live outside model.vocab.
    final langIds = <String, int>{};
    final added = (json['added_tokens'] as List?) ?? const [];
    for (final t in added) {
      final m = t as Map<String, dynamic>;
      final content = m['content'] as String;
      final id = (m['id'] as num).toInt();
      vocab[content] = id;
      if (RegExp(r'^[a-z]{3}_[A-Z][a-z]{3}$').hasMatch(content)) langIds[content] = id;
    }

    final idToToken = <int, String>{};
    vocab.forEach((k, v) => idToToken[v] = k);

    final merges = <String, int>{};
    final mergesRaw = (model['merges'] as List?) ?? const [];
    for (var i = 0; i < mergesRaw.length; i++) {
      final m = mergesRaw[i];
      if (m is String) {
        merges[m] = i;
      } else if (m is List && m.length == 2) {
        merges['${m[0]} ${m[1]}'] = i;
      }
    }

    final unk = vocab[model['unk_token'] ?? '<unk>'] ?? 3;
    final eos = vocab['</s>'] ?? 2;
    final pad = vocab['<pad>'] ?? 1;
    return NllbTokenizer._(vocab, idToToken, merges, unk, eos, pad, langIds);
  }

  int langId(String nllbCode) {
    final id = _langIds[nllbCode] ?? _vocab[nllbCode];
    if (id == null) throw StateError('Unknown language token $nllbCode');
    return id;
  }

  /// NLLB input format: [src_lang] tokens... [</s>]
  List<int> encode(String text, String srcLang) {
    final ids = <int>[langId(srcLang)];
    final norm = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (norm.isEmpty) return [...ids, eosId];
    // Metaspace with add_prefix_space: every word gets a leading ▁.
    for (final word in norm.split(' ')) {
      if (word.isEmpty) continue;
      ids.addAll(_bpe('$_space$word'));
    }
    ids.add(eosId);
    return ids;
  }

  List<int> _bpe(String word) {
    // Fast path: whole word is a token.
    final whole = _vocab[word];
    if (whole != null) return [whole];

    var symbols = word.runes.map((r) => String.fromCharCode(r)).toList();
    if (symbols.length == 1) return [_vocab[symbols[0]] ?? unkId];

    while (symbols.length > 1) {
      var bestRank = 1 << 30;
      var bestIdx = -1;
      for (var i = 0; i < symbols.length - 1; i++) {
        final rank = _mergeRank['${symbols[i]} ${symbols[i + 1]}'];
        if (rank != null && rank < bestRank) {
          bestRank = rank;
          bestIdx = i;
        }
      }
      if (bestIdx < 0) break;
      final merged = symbols[bestIdx] + symbols[bestIdx + 1];
      symbols = [
        ...symbols.sublist(0, bestIdx),
        merged,
        ...symbols.sublist(bestIdx + 2),
      ];
    }
    return symbols.map((s) => _vocab[s] ?? unkId).toList();
  }

  String decode(List<int> ids) {
    final buf = StringBuffer();
    for (final id in ids) {
      if (id == eosId || id == padId) continue;
      final tok = _idToToken[id];
      if (tok == null) continue;
      if (_langIds.containsKey(tok) || tok == '<s>' || tok == '<unk>') continue;
      buf.write(tok);
    }
    return buf.toString().replaceAll(_space, ' ').trim();
  }
}
