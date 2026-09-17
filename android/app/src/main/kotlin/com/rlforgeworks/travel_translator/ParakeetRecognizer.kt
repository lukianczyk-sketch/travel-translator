package com.rlforgeworks.travel_translator

import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import java.io.File
import java.nio.FloatBuffer
import java.nio.IntBuffer
import java.nio.LongBuffer
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.ln
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * NVIDIA Parakeet TDT 0.6B v3 (25 European languages, auto language) on ONNX Runtime.
 * Files in [dir]: encoder.int8.onnx, decoder.int8.onnx, joiner.int8.onnx, tokens.txt
 * (the sherpa-onnx export). Front-end = NeMo's log-mel (128 bins, 25/10 ms, hann,
 * pre-emphasis 0.97, slaney mel, per-feature normalisation). Greedy TDT search.
 */
class ParakeetRecognizer(private val dir: File) {
    private val env: OrtEnvironment = OrtEnvironment.getEnvironment()
    private lateinit var encoder: OrtSession
    private lateinit var decoder: OrtSession
    private lateinit var joiner: OrtSession
    private val tokens = ArrayList<String>()
    private var vocab = 8193 // incl. <blk>
    private var blank = 8192

    @Volatile var ready = false
        private set
    var loadError: String? = null
        private set

    class Result(val text: String, val confidence: Double, val msFeatures: Long, val msEncoder: Long, val msDecode: Long)

    fun load(): Boolean {
        try {
            File(dir, "tokens.txt").forEachLine { line ->
                val l = line.trimEnd()
                if (l.isEmpty()) return@forEachLine
                val sp = l.lastIndexOf(' ')
                val tok = if (sp > 0) l.substring(0, sp) else l
                tokens.add(tok)
            }
            vocab = tokens.size
            blank = tokens.indexOf("<blk>").let { if (it >= 0) it else vocab - 1 }
            val opts = OrtSession.SessionOptions().apply {
                setIntraOpNumThreads(4)
                setOptimizationLevel(OrtSession.SessionOptions.OptLevel.ALL_OPT)
                try { addConfigEntry("session.intra_op.allow_spinning", "0") } catch (_: Throwable) {}
            }
            encoder = env.createSession(File(dir, "encoder.int8.onnx").absolutePath, opts)
            decoder = env.createSession(File(dir, "decoder.int8.onnx").absolutePath, opts)
            joiner = env.createSession(File(dir, "joiner.int8.onnx").absolutePath, opts)
            ready = true
            return true
        } catch (e: Throwable) {
            loadError = e.toString(); ready = false; return false
        }
    }

    fun close() {
        try { encoder.close() } catch (_: Throwable) {}
        try { decoder.close() } catch (_: Throwable) {}
        try { joiner.close() } catch (_: Throwable) {}
        ready = false
    }

    // ---------------- front-end ----------------
    private val nFft = 512
    private val winLen = 400
    private val hop = 160
    private val nMels = 128
    private val window = FloatArray(nFft).also { w ->
        val off = (nFft - winLen) / 2
        for (i in 0 until winLen) w[off + i] = (0.5 - 0.5 * cos(2.0 * PI * i / winLen)).toFloat() // periodic hann
    }
    private val mel: Array<FloatArray> = buildMel()

    private fun hzToMel(f: Double): Double {
        val fSp = 200.0 / 3; val minLogHz = 1000.0; val minLogMel = minLogHz / fSp; val logstep = ln(6.4) / 27.0
        return if (f >= minLogHz) minLogMel + ln(f / minLogHz) / logstep else f / fSp
    }
    private fun melToHz(m: Double): Double {
        val fSp = 200.0 / 3; val minLogHz = 1000.0; val minLogMel = minLogHz / fSp; val logstep = ln(6.4) / 27.0
        return if (m >= minLogMel) minLogHz * exp(logstep * (m - minLogMel)) else fSp * m
    }
    private fun buildMel(): Array<FloatArray> {
        val nBins = nFft / 2 + 1
        val fftFreqs = DoubleArray(nBins) { it * 8000.0 / (nBins - 1) }
        val melPts = DoubleArray(nMels + 2)
        val mLo = hzToMel(0.0); val mHi = hzToMel(8000.0)
        for (i in melPts.indices) melPts[i] = melToHz(mLo + (mHi - mLo) * i / (nMels + 1))
        val w = Array(nMels) { FloatArray(nBins) }
        for (i in 0 until nMels) {
            val lo = melPts[i]; val c = melPts[i + 1]; val hi = melPts[i + 2]
            val enorm = 2.0 / (hi - lo)
            for (k in 0 until nBins) {
                val f = fftFreqs[k]
                val lower = (f - lo) / (c - lo)
                val upper = (hi - f) / (hi - c)
                val v = max(0.0, min(lower, upper))
                w[i][k] = (v * enorm).toFloat()
            }
        }
        return w
    }

    // iterative radix-2 complex FFT, in place, n = 512
    private val cosT = DoubleArray(nFft / 2) { cos(-2.0 * PI * it / nFft) }
    private val sinT = DoubleArray(nFft / 2) { sin(-2.0 * PI * it / nFft) }
    private fun fft(re: DoubleArray, im: DoubleArray) {
        val n = re.size
        var j = 0
        for (i in 1 until n) {
            var bit = n shr 1
            while (j and bit != 0) { j = j xor bit; bit = bit shr 1 }
            j = j xor bit
            if (i < j) { var t = re[i]; re[i] = re[j]; re[j] = t; t = im[i]; im[i] = im[j]; im[j] = t }
        }
        var len = 2
        while (len <= n) {
            val step = n / len
            var i = 0
            while (i < n) {
                var k = 0
                for (jj in 0 until len / 2) {
                    val wr = cosT[k]; val wi = sinT[k]
                    val ur = re[i + jj]; val ui = im[i + jj]
                    val vr = re[i + jj + len / 2] * wr - im[i + jj + len / 2] * wi
                    val vi = re[i + jj + len / 2] * wi + im[i + jj + len / 2] * wr
                    re[i + jj] = ur + vr; im[i + jj] = ui + vi
                    re[i + jj + len / 2] = ur - vr; im[i + jj + len / 2] = ui - vi
                    k += step
                }
                i += len
            }
            len = len shl 1
        }
    }

    /** Returns features laid out [128][T] (channel-major, as the model wants). */
    private fun features(pcm: FloatArray): Pair<FloatArray, Int> {
        // pre-emphasis
        val n = pcm.size
        val y = FloatArray(n)
        if (n > 0) y[0] = pcm[0]
        for (i in 1 until n) y[i] = pcm[i] - 0.97f * pcm[i - 1]
        // reflect pad nFft/2 each side
        val pad = nFft / 2
        val padded = FloatArray(n + 2 * pad)
        for (i in 0 until n) padded[pad + i] = y[i]
        for (i in 0 until pad) {
            padded[pad - 1 - i] = y[min(i + 1, n - 1)]
            padded[pad + n + i] = y[max(n - 2 - i, 0)]
        }
        val nFrames = 1 + (padded.size - nFft) / hop
        val nBins = nFft / 2 + 1
        val logmel = Array(nFrames) { FloatArray(nMels) }
        val re = DoubleArray(nFft); val im = DoubleArray(nFft)
        val power = DoubleArray(nBins)
        for (f in 0 until nFrames) {
            val off = f * hop
            for (i in 0 until nFft) { re[i] = (padded[off + i] * window[i]).toDouble(); im[i] = 0.0 }
            fft(re, im)
            for (k in 0 until nBins) power[k] = re[k] * re[k] + im[k] * im[k]
            for (m in 0 until nMels) {
                var s = 0.0
                val row = mel[m]
                for (k in 0 until nBins) s += row[k] * power[k]
                logmel[f][m] = ln(s + 5.960464477539063e-8).toFloat() // 2^-24
            }
        }
        // per-feature normalisation over time (unbiased std, +1e-5)
        val out = FloatArray(nMels * nFrames)
        for (m in 0 until nMels) {
            var mean = 0.0
            for (f in 0 until nFrames) mean += logmel[f][m]
            mean /= nFrames
            var v = 0.0
            for (f in 0 until nFrames) { val d = logmel[f][m] - mean; v += d * d }
            val std = if (nFrames > 1) sqrt(v / (nFrames - 1)) else 0.0
            for (f in 0 until nFrames) out[m * nFrames + f] = ((logmel[f][m] - mean) / (std + 1e-5)).toFloat()
        }
        return Pair(out, nFrames)
    }

    // ---------------- recognition ----------------
    fun transcribe(pcmIn: FloatArray): Result {
        if (!ready) throw IllegalStateException(loadError ?: "parakeet not loaded")
        // The model needs a beat of silence after the speech to finish the last word.
        val lead = 1600; val tail = 8000
        val pcm = FloatArray(lead + pcmIn.size + tail)
        System.arraycopy(pcmIn, 0, pcm, lead, pcmIn.size)

        val t0 = System.currentTimeMillis()
        val (feat, nFrames) = features(pcm)
        val t1 = System.currentTimeMillis()
        val featT = OnnxTensor.createTensor(env, FloatBuffer.wrap(feat), longArrayOf(1, nMels.toLong(), nFrames.toLong()))
        val lenT = OnnxTensor.createTensor(env, LongBuffer.wrap(longArrayOf(nFrames.toLong())), longArrayOf(1))
        val encRes = encoder.run(mapOf("audio_signal" to featT, "length" to lenT))
        val encOut = encRes.get(0) as OnnxTensor
        val encLenV = encRes.get(1).value
        val tLen = when (encLenV) { is LongArray -> encLenV[0].toInt(); is IntArray -> encLenV[0]; else -> 0 }
        val encShape = encOut.info.shape // [1, 1024, T]
        val dim = encShape[1].toInt()
        val tTotal = encShape[2].toInt()
        val encBuf = encOut.floatBuffer
        val t2 = System.currentTimeMillis()

        var s1 = OnnxTensor.createTensor(env, FloatBuffer.wrap(FloatArray(2 * 640)), longArrayOf(2, 1, 640))
        var s2 = OnnxTensor.createTensor(env, FloatBuffer.wrap(FloatArray(2 * 640)), longArrayOf(2, 1, 640))
        var decOut: OnnxTensor
        run {
            val r = runDecoder(blank, s1, s2)
            decOut = r.first; s1 = r.second; s2 = r.third
        }
        val out = ArrayList<Int>()
        var sumLogP = 0.0
        val frame = FloatArray(dim)
        var t = 0; var tokensThisFrame = 0
        val T = min(tLen, tTotal)
        while (t < T) {
            for (c in 0 until dim) frame[c] = encBuf.get(c * tTotal + t)
            val encT = OnnxTensor.createTensor(env, FloatBuffer.wrap(frame), longArrayOf(1, dim.toLong(), 1))
            val jr = joiner.run(mapOf("encoder_outputs" to encT, "decoder_outputs" to decOut))
            val logit = (jr.get(0) as OnnxTensor).floatBuffer
            var best = 0; var bestV = Float.NEGATIVE_INFINITY
            for (v in 0 until vocab) { val x = logit.get(v); if (x > bestV) { bestV = x; best = v } }
            val nDur = logit.capacity() - vocab
            var skip = 0; var skipV = Float.NEGATIVE_INFINITY
            for (d in 0 until nDur) { val x = logit.get(vocab + d); if (x > skipV) { skipV = x; skip = d } }
            if (best != blank) {
                // log-softmax prob of the chosen token
                var mx = Float.NEGATIVE_INFINITY
                for (v in 0 until vocab) mx = max(mx, logit.get(v))
                var se = 0.0
                for (v in 0 until vocab) se += exp((logit.get(v) - mx).toDouble())
                sumLogP += (bestV - mx) - ln(se)
                out.add(best)
                val r = runDecoder(best, s1, s2)
                decOut.close(); s1.close(); s2.close()
                decOut = r.first; s1 = r.second; s2 = r.third
                tokensThisFrame++
            }
            jr.close(); encT.close()
            if (skip > 0) tokensThisFrame = 0
            if (tokensThisFrame >= 5) { tokensThisFrame = 0; skip = 1 }
            if (best == blank && skip == 0) { tokensThisFrame = 0; skip = 1 }
            t += skip
        }
        val t3 = System.currentTimeMillis()
        encRes.close(); featT.close(); lenT.close(); decOut.close(); s1.close(); s2.close()

        val sb = StringBuilder()
        for (id in out) if (id in tokens.indices) sb.append(tokens[id])
        val text = sb.toString().replace('\u2581', ' ').trim()
        val conf = if (out.isEmpty()) 0.0 else exp(sumLogP / out.size)
        return Result(text, conf, t1 - t0, t2 - t1, t3 - t2)
    }

    private fun runDecoder(tok: Int, s1: OnnxTensor, s2: OnnxTensor): Triple<OnnxTensor, OnnxTensor, OnnxTensor> {
        val tg = OnnxTensor.createTensor(env, IntBuffer.wrap(intArrayOf(tok)), longArrayOf(1, 1))
        val tl = OnnxTensor.createTensor(env, IntBuffer.wrap(intArrayOf(1)), longArrayOf(1))
        val r = decoder.run(mapOf("targets" to tg, "target_length" to tl, "states.1" to s1, "onnx::Slice_3" to s2))
        // outputs: [0]=outputs [1,640,1], [1]=prednet_lengths, [2]=states, [3]=cell states
        val outT = copy(r.get(0) as OnnxTensor)
        val n1 = copy(r.get(2) as OnnxTensor)
        val n2 = copy(r.get(3) as OnnxTensor)
        r.close(); tg.close(); tl.close()
        return Triple(outT, n1, n2)
    }

    /** Detach a tensor from its Result so it survives Result.close(). */
    private fun copy(t: OnnxTensor): OnnxTensor {
        val fb = t.floatBuffer
        val arr = FloatArray(fb.capacity()); fb.get(arr)
        return OnnxTensor.createTensor(env, FloatBuffer.wrap(arr), t.info.shape)
    }
}
