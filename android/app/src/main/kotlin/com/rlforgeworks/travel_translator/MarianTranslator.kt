package com.rlforgeworks.travel_translator

import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import org.json.JSONObject
import java.io.File
import java.nio.FloatBuffer
import java.nio.LongBuffer
import java.text.Normalizer

/**
 * OPUS-MT (Marian) translation on ONNX Runtime, fully offline.
 * Files (one folder per direction, e.g. models/opus-mt-pl-en/):
 *   encoder_model_quantized.onnx, decoder_model_quantized.onnx, tokenizer.json, config.json
 * The tokenizer is a SentencePiece-style unigram model read from tokenizer.json
 * (vocab = [[piece, logprob], ...] indexed by id; Metaspace pre-tokenizer).
 */
class MarianTranslator(private val dir: File) {
    private val env: OrtEnvironment = OrtEnvironment.getEnvironment()
    private lateinit var encoder: OrtSession
    private lateinit var decoder: OrtSession

    private val pieces = ArrayList<String>()
    private val scores = ArrayList<Float>()
    private val pieceToId = HashMap<String, Int>()
    private var maxPieceLen = 1
    private var unkId = 1
    private var eosId = 0
    private var padId = -1
    private var decoderStartId = -1
    private var maxLen = 96

    // Input names, read from the sessions so a differently-exported model still works.
    private lateinit var encInputIds: String
    private lateinit var encMask: String
    private lateinit var decInputIds: String
    private lateinit var decMask: String
    private lateinit var decHidden: String
    private lateinit var encOutName: String
    private lateinit var decLogitsName: String

    @Volatile var ready = false
        private set
    var loadError: String? = null
        private set

    fun load(): Boolean {
        try {
            val tok = JSONObject(File(dir, "tokenizer.json").readText())
            val model = tok.getJSONObject("model")
            val vocab = model.getJSONArray("vocab")
            for (i in 0 until vocab.length()) {
                val e = vocab.getJSONArray(i)
                val p = e.getString(0)
                pieces.add(p); scores.add(e.getDouble(1).toFloat())
                if (!pieceToId.containsKey(p)) pieceToId[p] = i
                if (p.length > maxPieceLen) maxPieceLen = p.length
            }
            unkId = model.optInt("unk_id", pieceToId["<unk>"] ?: 1)
            eosId = pieceToId["</s>"] ?: 0
            padId = pieceToId["<pad>"] ?: -1

            val cfgFile = File(dir, "config.json")
            if (cfgFile.exists()) {
                val cfg = JSONObject(cfgFile.readText())
                decoderStartId = cfg.optInt("decoder_start_token_id", padId)
                eosId = cfg.optInt("eos_token_id", eosId)
                padId = cfg.optInt("pad_token_id", padId)
                maxLen = cfg.optInt("max_length", maxLen).coerceIn(32, 128)
            }
            if (decoderStartId < 0) decoderStartId = padId

            val opts = OrtSession.SessionOptions().apply {
                setIntraOpNumThreads(4)
                setOptimizationLevel(OrtSession.SessionOptions.OptLevel.ALL_OPT)
            }
            encoder = env.createSession(File(dir, "encoder_model_quantized.onnx").absolutePath, opts)
            decoder = env.createSession(File(dir, "decoder_model_quantized.onnx").absolutePath, opts)

            val encIn = encoder.inputNames
            encInputIds = encIn.firstOrNull { it == "input_ids" } ?: encIn.first()
            encMask = encIn.firstOrNull { it.contains("attention_mask") } ?: "attention_mask"
            encOutName = encoder.outputNames.firstOrNull { it.contains("hidden") } ?: encoder.outputNames.first()
            val decIn = decoder.inputNames
            decInputIds = decIn.firstOrNull { it == "input_ids" } ?: decIn.first { it.contains("input_ids") }
            decMask = decIn.firstOrNull { it == "encoder_attention_mask" } ?: decIn.first { it.contains("attention_mask") }
            decHidden = decIn.firstOrNull { it == "encoder_hidden_states" } ?: decIn.first { it.contains("hidden") }
            decLogitsName = decoder.outputNames.firstOrNull { it == "logits" } ?: decoder.outputNames.first()
            ready = true
            return true
        } catch (e: Throwable) {
            loadError = e.toString()
            ready = false
            return false
        }
    }

    fun close() {
        try { encoder.close() } catch (_: Throwable) {}
        try { decoder.close() } catch (_: Throwable) {}
        ready = false
    }

    // ---------------- tokenizer ----------------
    private fun normalize(text: String): String {
        var t = Normalizer.normalize(text.trim(), Normalizer.Form.NFKC)
        t = t.replace(Regex("\\s+"), " ")
        return "\u2581" + t.replace(' ', '\u2581')
    }

    /** Viterbi segmentation over the unigram vocab (SentencePiece-style). */
    private fun encode(text: String): LongArray {
        val s = normalize(text)
        val n = s.length
        val best = DoubleArray(n + 1) { Double.NEGATIVE_INFINITY }
        val back = IntArray(n + 1) { -1 }
        val backId = IntArray(n + 1) { -1 }
        best[0] = 0.0
        val unkScore = (scores.minOrNull() ?: -10f) - 10f
        for (i in 0 until n) {
            if (best[i] == Double.NEGATIVE_INFINITY) continue
            val lim = minOf(n, i + maxPieceLen)
            var any = false
            for (j in i + 1..lim) {
                val id = pieceToId[s.substring(i, j)] ?: continue
                any = true
                val sc = best[i] + scores[id]
                if (sc > best[j]) { best[j] = sc; back[j] = i; backId[j] = id }
            }
            if (!any) {
                // Unknown character: one <unk> token, advance by one code point.
                val cp = s.codePointAt(i)
                val j = i + Character.charCount(cp)
                val sc = best[i] + unkScore
                if (j <= n && sc > best[j]) { best[j] = sc; back[j] = i; backId[j] = unkId }
            }
        }
        val out = ArrayList<Long>()
        var k = n
        while (k > 0 && back[k] >= 0) { out.add(backId[k].toLong()); k = back[k] }
        out.reverse()
        if (out.size > maxLen - 1) { while (out.size > maxLen - 1) out.removeAt(out.size - 1) }
        out.add(eosId.toLong())
        return out.toLongArray()
    }

    private fun decode(ids: List<Long>): String {
        val sb = StringBuilder()
        for (id in ids) {
            val i = id.toInt()
            if (i == eosId || i == padId || i == decoderStartId) continue
            if (i < 0 || i >= pieces.size) continue
            sb.append(pieces[i])
        }
        return sb.toString().replace('\u2581', ' ').trim()
    }

    // ---------------- translation ----------------
    /** Greedy decode; returns the translation or throws. */
    fun translate(text: String): String {
        if (!ready) throw IllegalStateException(loadError ?: "translator not loaded")
        val ids = encode(text)
        val n = ids.size
        val inputIds = OnnxTensor.createTensor(env, LongBuffer.wrap(ids), longArrayOf(1, n.toLong()))
        val mask = OnnxTensor.createTensor(env, LongBuffer.wrap(LongArray(n) { 1L }), longArrayOf(1, n.toLong()))
        val encOut = encoder.run(mapOf(encInputIds to inputIds, encMask to mask))
        val hidden = encOut.get(encOutName).get() as OnnxTensor

        val out = ArrayList<Long>()
        out.add(decoderStartId.toLong())
        var lastTok = -1L
        var repeats = 0
        try {
            for (step in 0 until maxLen) {
                val decIds = OnnxTensor.createTensor(env, LongBuffer.wrap(out.toLongArray()), longArrayOf(1, out.size.toLong()))
                val res = decoder.run(mapOf(decInputIds to decIds, decMask to mask, decHidden to hidden))
                val logits = res.get(decLogitsName).get() as OnnxTensor
                val info = logits.info.shape // [1, t, vocab]
                val vocab = info[2].toInt()
                val t = info[1].toInt()
                val fb: FloatBuffer = logits.floatBuffer
                val base = (t - 1) * vocab
                var bestId = 0
                var bestV = Float.NEGATIVE_INFINITY
                for (v in 0 until vocab) {
                    if (v == padId) continue
                    val x = fb.get(base + v)
                    if (x > bestV) { bestV = x; bestId = v }
                }
                res.close(); decIds.close()
                val tok = bestId.toLong()
                if (tok == eosId.toLong()) break
                if (tok == lastTok) { repeats++; if (repeats >= 3) break } else repeats = 0
                lastTok = tok
                out.add(tok)
            }
        } finally {
            encOut.close(); inputIds.close(); mask.close()
        }
        return decode(out)
    }
}
