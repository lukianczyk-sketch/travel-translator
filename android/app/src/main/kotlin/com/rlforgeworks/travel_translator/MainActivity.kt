package com.rlforgeworks.travel_translator

import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.media.MediaPlayer
import android.os.Build
import android.os.Bundle
import kotlin.math.min
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import java.io.FileOutputStream
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import android.speech.ModelDownloadListener
import android.speech.RecognitionListener
import android.speech.RecognitionSupport
import android.speech.RecognitionSupportCallback
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import com.google.mlkit.common.model.DownloadConditions
import com.google.mlkit.common.model.RemoteModelManager
import com.google.mlkit.nl.translate.TranslateLanguage
import com.google.mlkit.nl.translate.TranslateRemoteModel
import com.google.mlkit.nl.translate.Translation
import com.google.mlkit.nl.translate.Translator
import com.google.mlkit.nl.translate.TranslatorOptions
import java.io.BufferedReader
import java.io.InputStreamReader
import java.util.concurrent.Executors

/**
 * Bridge to Android's on-device SpeechRecognizer: continuous streaming
 * recognition with partial results and (Android 14+) automatic language
 * detection/switching between the allowed languages.
 */
class MainActivity : FlutterActivity() {
    private var recognizer: SpeechRecognizer? = null
    private var events: EventChannel.EventSink? = null
    private val main = Handler(Looper.getMainLooper())
    private val executor = Executors.newSingleThreadExecutor()
    private var listening = false
    private var langs: ArrayList<String> = arrayListOf()
    private var primary: String = "en-US"
    private var currentLang: String? = null
    private var restartPending = false
    private var busyCount = 0
    private var quietCount = 0
    private val translators = HashMap<String, Translator>()
    private val marian = HashMap<String, MarianTranslator>() // "pl>en" → OPUS-MT engine
    private var parakeet: ParakeetRecognizer? = null
    private var player: MediaPlayer? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        EventChannel(messenger, "tt/stt/events").setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(args: Any?, sink: EventChannel.EventSink) { events = sink }
            override fun onCancel(args: Any?) { events = null }
        })

        MethodChannel(messenger, "tt/stt").setMethodCallHandler { call, result ->
            when (call.method) {
                "available" -> result.success(
                    Build.VERSION.SDK_INT >= 31 && SpeechRecognizer.isOnDeviceRecognitionAvailable(this)
                )
                "sdk" -> result.success(Build.VERSION.SDK_INT)
                "start" -> {
                    @Suppress("UNCHECKED_CAST")
                    val l = call.argument<List<String>>("languages") ?: listOf("en-US")
                    langs = ArrayList(l)
                    primary = call.argument<String>("primary") ?: l.first()
                    currentLang = null
                    busyCount = 0
                    quietCount = 0
                    resetAudioPath()
                    // Always begin with a fresh recognizer.
                    main.post {
                        try { recognizer?.cancel(); recognizer?.destroy() } catch (_: Exception) {}
                        recognizer = null
                        startListening()
                    }
                    result.success(true)
                }
                "stop" -> { stopListening(); result.success(true) }
                "pause" -> { pauseListening(); result.success(true) }
                "setPrimary" -> { primary = call.argument<String>("primary") ?: primary; result.success(true) }
                "resume" -> {
                    val p = call.argument<String>("primary")
                    if (p != null) primary = p
                    if (!listening) {
                        // Tear down the previous session and give the audio path a moment to settle.
                        resetAudioPath()
                        main.post { try { recognizer?.cancel() } catch (_: Exception) {} }
                        main.postDelayed({ startListening() }, 450)
                    }
                    result.success(true)
                }
                "checkSupport" -> checkSupport(call.argument<List<String>>("languages") ?: listOf(), result)
                "download" -> download(call.argument<String>("language") ?: "en-US", result)
                "logcat" -> result.success(readLogcat())
                "hasExternalOutput" -> result.success(externalOutputConnected(getSystemService(Context.AUDIO_SERVICE) as AudioManager))
                "recognizeAudio" -> {
                    val pcm = call.argument<ByteArray>("pcm") ?: ByteArray(0)
                    @Suppress("UNCHECKED_CAST")
                    val ls = call.argument<List<String>>("languages") ?: listOf("en-US")
                    executor.execute {
                        val out = recognizeAudio(pcm, ls)
                        main.post { result.success(out) }
                    }
                }
                "play" -> playFile(call.argument<String>("path") ?: "", call.argument<Boolean>("speaker") ?: true,
                                   (call.argument<Double>("volume") ?: 1.0).toFloat(), result)
                "setLevel" -> { setLevel(call.argument<String>("stream") ?: "media", (call.argument<Double>("fraction") ?: 1.0).toFloat()); result.success(true) }
                "stopPlay" -> { stopPlayback(); result.success(true) }
                else -> result.notImplemented()
            }
        }

        MethodChannel(messenger, "tt/mt").setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "isDownloaded" -> {
                        val code = mlLang(call.argument<String>("code") ?: "")
                        if (code == null) { result.success(false); return@setMethodCallHandler }
                        RemoteModelManager.getInstance()
                            .isModelDownloaded(TranslateRemoteModel.Builder(code).build())
                            .addOnSuccessListener { result.success(it) }
                            .addOnFailureListener { result.error("mt", it.toString(), null) }
                    }
                    "download" -> {
                        val code = mlLang(call.argument<String>("code") ?: "")
                        if (code == null) { result.error("mt", "unsupported language", null); return@setMethodCallHandler }
                        RemoteModelManager.getInstance()
                            .download(TranslateRemoteModel.Builder(code).build(), DownloadConditions.Builder().build())
                            .addOnSuccessListener { result.success(true) }
                            .addOnFailureListener { result.error("mt", it.toString(), null) }
                    }
                    "delete" -> {
                        val code = mlLang(call.argument<String>("code") ?: "")
                        if (code == null) { result.success(false); return@setMethodCallHandler }
                        RemoteModelManager.getInstance()
                            .deleteDownloadedModel(TranslateRemoteModel.Builder(code).build())
                            .addOnSuccessListener { result.success(true) }
                            .addOnFailureListener { result.error("mt", it.toString(), null) }
                    }
                    "extractTarBz2" -> {
                        val src = java.io.File(call.argument<String>("path") ?: "")
                        val dest = java.io.File(call.argument<String>("dest") ?: "")
                        executor.execute {
                            try {
                                dest.mkdirs()
                                val tin = org.apache.commons.compress.archivers.tar.TarArchiveInputStream(
                                    org.apache.commons.compress.compressors.bzip2.BZip2CompressorInputStream(
                                        java.io.BufferedInputStream(java.io.FileInputStream(src), 1 shl 20)))
                                var entry = tin.nextEntry
                                var count = 0
                                while (entry != null) {
                                    if (!entry.isDirectory) {
                                        val name = entry.name.substringAfterLast('/')
                                        if (name.isNotEmpty() && !entry.name.contains("test_wavs")) {
                                            val out = java.io.File(dest, name)
                                            java.io.FileOutputStream(out).use { fos -> tin.copyTo(fos, 1 shl 20) }
                                            count++
                                        }
                                    }
                                    entry = tin.nextEntry
                                }
                                tin.close()
                                main.post { result.success(count) }
                            } catch (e: Throwable) {
                                main.post { result.error("extract", e.toString(), null) }
                            }
                        }
                    }
                    "parakeetLoad" -> {
                        val dir = java.io.File(call.argument<String>("dir") ?: "")
                        executor.execute {
                            val existing = parakeet
                            if (existing != null && existing.ready) { main.post { result.success(true) }; return@execute }
                            val p = ParakeetRecognizer(dir)
                            val ok = p.load()
                            if (ok) parakeet = p
                            main.post { if (ok) result.success(true) else result.error("asr", p.loadError ?: "load failed", null) }
                        }
                    }
                    "parakeetUnload" -> { parakeet?.close(); parakeet = null; result.success(true) }
                    "parakeetTranscribe" -> {
                        val path = call.argument<String>("path") ?: ""
                        val p = parakeet
                        if (p == null || !p.ready) { result.error("asr", "parakeet not loaded", null); return@setMethodCallHandler }
                        executor.execute {
                            try {
                                val pcm = readWav16k(java.io.File(path))
                                val r = p.transcribe(pcm)
                                main.post { result.success(mapOf("text" to r.text, "confidence" to r.confidence,
                                    "msFeatures" to r.msFeatures, "msEncoder" to r.msEncoder, "msDecode" to r.msDecode)) }
                            } catch (e: Throwable) {
                                main.post { result.error("asr", e.toString(), null) }
                            }
                        }
                    }
                    "marianLoad" -> {
                        val key = call.argument<String>("key") ?: ""
                        val dir = java.io.File(call.argument<String>("dir") ?: "")
                        executor.execute {
                            val existing = marian[key]
                            if (existing != null && existing.ready) { main.post { result.success(true) }; return@execute }
                            val m = MarianTranslator(dir)
                            val ok = m.load()
                            if (ok) marian[key] = m
                            main.post { if (ok) result.success(true) else result.error("mt", m.loadError ?: "load failed", null) }
                        }
                    }
                    "marianUnload" -> {
                        val key = call.argument<String>("key") ?: ""
                        marian.remove(key)?.close()
                        result.success(true)
                    }
                    "marianTranslate" -> {
                        val key = call.argument<String>("key") ?: ""
                        val text = call.argument<String>("text") ?: ""
                        val m = marian[key]
                        if (m == null || !m.ready) { result.error("mt", "engine $key not loaded", null); return@setMethodCallHandler }
                        executor.execute {
                            try {
                                val out = m.translate(text)
                                main.post { result.success(out) }
                            } catch (e: Throwable) {
                                main.post { result.error("mt", e.toString(), null) }
                            }
                        }
                    }
                    "translate" -> {
                        val src = mlLang(call.argument<String>("src") ?: "")
                        val tgt = mlLang(call.argument<String>("tgt") ?: "")
                        val text = call.argument<String>("text") ?: ""
                        if (src == null || tgt == null) { result.error("mt", "unsupported language", null); return@setMethodCallHandler }
                        val key = "$src>$tgt"
                        val t = translators.getOrPut(key) {
                            Translation.getClient(TranslatorOptions.Builder().setSourceLanguage(src).setTargetLanguage(tgt).build())
                        }
                        t.translate(text)
                            .addOnSuccessListener { result.success(it) }
                            .addOnFailureListener { result.error("mt", it.toString(), null) }
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Throwable) {
                result.error("mt", e.toString(), null)
            }
        }
    }

    // ---------------- file-based recognition (no mic, no beeps) ----------------
    private val chimeStreams = intArrayOf(AudioManager.STREAM_MUSIC, AudioManager.STREAM_SYSTEM, AudioManager.STREAM_NOTIFICATION)

    /** Silence the recognizer's start/stop chimes while it runs on our audio. */
    private fun withChimesMuted(block: () -> Unit) {
        val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val muted = ArrayList<Int>()
        for (st in chimeStreams) {
            try {
                if (!am.isStreamMute(st)) { am.adjustStreamVolume(st, AudioManager.ADJUST_MUTE, 0); muted.add(st) }
            } catch (_: Exception) {}
        }
        try { block() } finally {
            for (st in muted) { try { am.adjustStreamVolume(st, AudioManager.ADJUST_UNMUTE, 0) } catch (_: Exception) {} }
        }
    }

    private fun recognizeAudio(pcm: ByteArray, languages: List<String>): Map<String, Any?> {
        val results = java.util.Collections.synchronizedList(ArrayList<Map<String, Any?>>())
        withChimesMuted {
            // All languages at once, each on its own recognizer + pipe.
            val threads = languages.map { lang -> Thread { results.add(recognizeOnce(pcm, lang)) } }
            threads.forEach { it.start() }
            threads.forEach { it.join(20000) }
        }
        val best = results.filter { (it["text"] as? String)?.isNotBlank() == true }
            .maxWithOrNull(compareBy<Map<String, Any?>>({ (it["confidence"] as? Double) ?: 0.0 }, { ((it["text"] as? String) ?: "").length }))
        return mapOf("best" to best, "all" to ArrayList(results))
    }

    private fun recognizeOnce(pcm: ByteArray, lang: String): Map<String, Any?> {
        val latch = CountDownLatch(1)
        var text = ""
        var conf = 0.0
        var err: Int? = null
        val pipe = try { ParcelFileDescriptor.createPipe() } catch (e: Exception) {
            return mapOf("lang" to lang, "text" to "", "confidence" to 0.0, "error" to "pipe: $e")
        }
        val readSide = pipe[0]
        val writeSide = pipe[1]
        val t0 = System.currentTimeMillis()
        main.post {
            val r = if (Build.VERSION.SDK_INT >= 31 && SpeechRecognizer.isOnDeviceRecognitionAvailable(this))
                SpeechRecognizer.createOnDeviceSpeechRecognizer(this) else SpeechRecognizer.createSpeechRecognizer(this)
            r.setRecognitionListener(object : RecognitionListener {
                override fun onReadyForSpeech(params: Bundle?) {}
                override fun onBeginningOfSpeech() {}
                override fun onRmsChanged(rmsdB: Float) {}
                override fun onBufferReceived(buffer: ByteArray?) {}
                override fun onEndOfSpeech() {}
                override fun onError(error: Int) { err = error; latch.countDown(); try { r.destroy() } catch (_: Exception) {} }
                override fun onResults(results: Bundle?) {
                    val list = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                    val scores = results?.getFloatArray(SpeechRecognizer.CONFIDENCE_SCORES)
                    text = list?.firstOrNull() ?: ""
                    conf = if (scores != null && scores.isNotEmpty()) scores[0].toDouble() else (if (text.isNotBlank()) 0.5 else 0.0)
                    latch.countDown()
                    try { r.destroy() } catch (_: Exception) {}
                }
                override fun onPartialResults(partialResults: Bundle?) {}
                override fun onEvent(eventType: Int, params: Bundle?) {}
            })
            val i = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH)
            i.putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            i.putExtra(RecognizerIntent.EXTRA_LANGUAGE, lang)
            i.putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, true)
            i.putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
            i.putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE, readSide)
            i.putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE_CHANNEL_COUNT, 1)
            i.putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE_ENCODING, android.media.AudioFormat.ENCODING_PCM_16BIT)
            i.putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE_SAMPLING_RATE, 16000)
            try { r.startListening(i) } catch (e: Exception) { err = -1; latch.countDown() }
        }
        // Feed the audio at roughly talking speed (the recognizer endpoints like a
        // live mic), with a little silence before and after so it can finalize.
        Thread {
            try {
                FileOutputStream(writeSide.fileDescriptor).use { out ->
                    val silence = ByteArray(3200) // 100 ms at 16 kHz mono 16-bit
                    repeat(3) { out.write(silence) }
                    var off = 0
                    val chunk = 3200
                    while (off < pcm.size) {
                        val n = minOf(chunk, pcm.size - off)
                        out.write(pcm, off, n)
                        off += n
                        Thread.sleep(45) // ~2x real time
                    }
                    repeat(12) { out.write(silence); Thread.sleep(45) } // 1.2 s tail
                    out.flush()
                }
            } catch (_: Exception) {}
            try { writeSide.close() } catch (_: Exception) {}
        }.start()
        latch.await(20, TimeUnit.SECONDS)
        try { readSide.close() } catch (_: Exception) {}
        return mapOf("lang" to lang, "text" to text, "confidence" to conf, "error" to err,
            "ms" to (System.currentTimeMillis() - t0))
    }

    private fun mlLang(code: String): String? = TranslateLanguage.fromLanguageTag(code)

    private fun readLogcat(): String {
        return try {
            val p = Runtime.getRuntime().exec(arrayOf("logcat", "-d", "-t", "400", "-v", "time"))
            val r = BufferedReader(InputStreamReader(p.inputStream))
            val sb = StringBuilder()
            var line = r.readLine()
            while (line != null) {
                if (line.contains("flutter", true) || line.contains("mlkit", true) || line.contains("Registrant") ||
                    line.contains("AndroidRuntime") || line.contains("FATAL") || line.contains("travel_translator") ||
                    line.contains("SpeechRecognizer", true) || line.contains(" E ")) sb.append(line).append('\n')
                line = r.readLine()
            }
            sb.toString()
        } catch (e: Exception) { "logcat unavailable: $e" }
    }

    private fun send(map: Map<String, Any?>) { main.post { events?.success(map) } }

    private fun buildIntent(): Intent {
        val i = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH)
        i.putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
        i.putExtra(RecognizerIntent.EXTRA_LANGUAGE, primary)
        i.putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
        i.putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, true)
        i.putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
        if (Build.VERSION.SDK_INT >= 33) {
            // Continuous session: one result per pause, no restarts.
            i.putExtra(RecognizerIntent.EXTRA_SEGMENTED_SESSION,
                RecognizerIntent.EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS)
            // Let a normal breath pass without ending the sentence.
            i.putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS, 1100)
            i.putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_POSSIBLY_COMPLETE_SILENCE_LENGTH_MILLIS, 900)
            i.putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_MINIMUM_LENGTH_MILLIS, 2000)
        }
        if (Build.VERSION.SDK_INT >= 34 && langs.size > 1) {
            i.putExtra(RecognizerIntent.EXTRA_ENABLE_LANGUAGE_DETECTION, true)
            i.putStringArrayListExtra(RecognizerIntent.EXTRA_LANGUAGE_DETECTION_ALLOWED_LANGUAGES, langs)
            i.putExtra(RecognizerIntent.EXTRA_ENABLE_LANGUAGE_SWITCH, RecognizerIntent.LANGUAGE_SWITCH_HIGH_PRECISION)
            i.putStringArrayListExtra(RecognizerIntent.EXTRA_LANGUAGE_SWITCH_ALLOWED_LANGUAGES, langs)
        }
        return i
    }

    private fun ensureRecognizer(): SpeechRecognizer? {
        if (recognizer != null) return recognizer
        val r = if (Build.VERSION.SDK_INT >= 31 && SpeechRecognizer.isOnDeviceRecognitionAvailable(this))
            SpeechRecognizer.createOnDeviceSpeechRecognizer(this)
        else if (SpeechRecognizer.isRecognitionAvailable(this))
            SpeechRecognizer.createSpeechRecognizer(this)
        else null
        r?.setRecognitionListener(listener)
        recognizer = r
        return r
    }

    private fun startListening() {
        val r = ensureRecognizer()
        if (r == null) { send(mapOf("type" to "error", "message" to "No speech recognizer on this phone")); return }
        listening = true
        restartPending = false
        main.post { try { r.startListening(buildIntent()) } catch (e: Exception) {
            send(mapOf("type" to "error", "message" to e.toString())) } }
        send(mapOf("type" to "status", "message" to "listening"))
    }

    private fun pauseListening() {
        listening = false
        main.post { try { recognizer?.cancel() } catch (_: Exception) {} }
    }

    // ---------------- audio playback with speaker routing ----------------
    private fun externalOutputConnected(am: AudioManager): Boolean {
        val devs = am.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
        return devs.any {
            it.type == AudioDeviceInfo.TYPE_BLUETOOTH_A2DP || it.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO ||
            it.type == AudioDeviceInfo.TYPE_WIRED_HEADSET || it.type == AudioDeviceInfo.TYPE_WIRED_HEADPHONES ||
            it.type == AudioDeviceInfo.TYPE_USB_HEADSET || (Build.VERSION.SDK_INT >= 31 && it.type == AudioDeviceInfo.TYPE_BLE_HEADSET)
        }
    }

    private fun externalOutputDevice(am: AudioManager): AudioDeviceInfo? {
        val devs = am.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
        return devs.firstOrNull { it.type == AudioDeviceInfo.TYPE_BLUETOOTH_A2DP }
            ?: devs.firstOrNull { Build.VERSION.SDK_INT >= 31 && it.type == AudioDeviceInfo.TYPE_BLE_HEADSET }
            ?: devs.firstOrNull { it.type == AudioDeviceInfo.TYPE_WIRED_HEADSET || it.type == AudioDeviceInfo.TYPE_WIRED_HEADPHONES || it.type == AudioDeviceInfo.TYPE_USB_HEADSET }
            ?: devs.firstOrNull { it.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO }
    }

    /** Make sure the earbuds are back in music mode (speaker-pinning can leave Samsung in call mode). */
    @Suppress("DEPRECATION")
    private fun leaveCallMode(am: AudioManager) {
        try {
            if (Build.VERSION.SDK_INT >= 31) am.clearCommunicationDevice() else am.setSpeakerphoneOn(false)
            if (am.isBluetoothScoOn) { am.isBluetoothScoOn = false }
            try { am.stopBluetoothSco() } catch (_: Exception) {}
            am.mode = AudioManager.MODE_NORMAL
        } catch (_: Exception) {}
    }

    private fun resetAudioPath() {
        val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        try {
            if (Build.VERSION.SDK_INT >= 31) am.clearCommunicationDevice() else am.setSpeakerphoneOn(false)
            am.mode = AudioManager.MODE_NORMAL
        } catch (_: Exception) {}
    }

    /** Reads a 16 kHz mono 16-bit PCM WAV (the app's own utterance files) into floats. */
    private fun readWav16k(f: java.io.File): FloatArray {
        val bytes = f.readBytes()
        var pos = 12
        var dataOff = -1; var dataLen = 0
        while (pos + 8 <= bytes.size) {
            val id = String(bytes, pos, 4, Charsets.US_ASCII)
            val len = java.nio.ByteBuffer.wrap(bytes, pos + 4, 4).order(java.nio.ByteOrder.LITTLE_ENDIAN).int
            if (id == "data") { dataOff = pos + 8; dataLen = len; break }
            pos += 8 + len + (len and 1)
        }
        if (dataOff < 0) throw IllegalArgumentException("no data chunk")
        val n = min(dataLen, bytes.size - dataOff) / 2
        val bb = java.nio.ByteBuffer.wrap(bytes, dataOff, n * 2).order(java.nio.ByteOrder.LITTLE_ENDIAN)
        val out = FloatArray(n)
        for (i in 0 until n) out[i] = bb.short / 32768f
        return out
    }

    // ---------------- volume ----------------
    private fun streamOf(name: String) = if (name == "call") AudioManager.STREAM_VOICE_CALL else AudioManager.STREAM_MUSIC
    /** Sets a phone volume stream to a fraction (0..1) of its maximum. Simple and predictable. */
    private fun setLevel(name: String, fraction: Float) {
        val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val st = streamOf(name)
        try {
            val max = am.getStreamMaxVolume(st)
            val idx = Math.round(fraction.coerceIn(0f, 1f) * max).coerceIn(1, max)
            am.setStreamVolume(st, idx, 0)
        } catch (_: Exception) {}
    }

    private fun playFile(path: String, forceSpeaker: Boolean, volume: Float, result: MethodChannel.Result) {
        val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        // Speaker is already the default unless something external is connected.
        val external = externalOutputConnected(am)
        val speaker = forceSpeaker && external
        val route = StringBuilder(if (speaker) "speaker" else "default")
        try { player?.release() } catch (_: Exception) {}
        val mp = MediaPlayer()
        player = mp
        var done = false
        val spk = am.getDevices(AudioManager.GET_DEVICES_OUTPUTS).firstOrNull { it.type == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER }
        fun finish(ok: Boolean) {
            if (done) return
            done = true
            try { mp.release() } catch (_: Exception) {}
            if (speaker) leaveCallMode(am)
            main.post { result.success(mapOf("ok" to ok, "route" to route.toString())) }
        }
        try {
            if (speaker) {
                // Route like a speakerphone call: forces the built-in speaker even with earbuds connected.
                am.mode = AudioManager.MODE_IN_COMMUNICATION
                if (Build.VERSION.SDK_INT >= 31) {
                    val comm = am.availableCommunicationDevices.firstOrNull { it.type == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER }
                    val ok = if (comm != null) am.setCommunicationDevice(comm) else false
                    route.append(" commDev=").append(ok)
                } else {
                    am.setSpeakerphoneOn(true)
                    route.append(" speakerphone=").append(am.isSpeakerphoneOn)
                }
                mp.setAudioAttributes(AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build())

            } else {
                // Their side: normal media channel, pinned to the earbuds/headset if one is connected.
                leaveCallMode(am)
                mp.setAudioAttributes(AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build())
                @Suppress("DEPRECATION")
                route.append(" mode=").append(am.mode).append(" sco=").append(am.isBluetoothScoOn).append(" a2dp=").append(am.isBluetoothA2dpOn)
            }
            // The slider sets the phone's real volume for that route; the player itself plays at full.
            setLevel(if (speaker) "call" else "media", volume)
            mp.setVolume(1f, 1f)
            route.append(" level=").append(Math.round(volume * 100)).append("%")
            mp.setDataSource(path)
            mp.setOnCompletionListener { finish(true) }
            mp.setOnErrorListener { _, _, _ -> finish(false); true }
            mp.setOnPreparedListener {
                // Pin this player (only valid once prepared): speaker for your side, earbuds for theirs.
                if (Build.VERSION.SDK_INT >= 28) {
                    val target = if (speaker) spk else externalOutputDevice(am)
                    if (target != null) {
                        try { route.append(" preferred=").append(it.setPreferredDevice(target)).append("→").append(target.productName) } catch (_: Exception) {}
                    }
                }
                it.start()
                if (Build.VERSION.SDK_INT >= 28) main.postDelayed({
                    try {
                        val dev = it.routedDevice
                        route.append(" out=").append(dev?.productName ?: "?").append("/type").append(dev?.type ?: -1)
                    } catch (_: Exception) {}
                }, 400)
            }
            mp.prepareAsync()
        } catch (e: Exception) {
            route.append(" err=").append(e.message)
            finish(false)
        }
    }

    private fun stopPlayback() {
        try { player?.stop(); player?.release() } catch (_: Exception) {}
        player = null
    }

    private fun stopListening() {
        listening = false
        main.post {
            try { recognizer?.cancel() } catch (_: Exception) {}
            try { recognizer?.destroy() } catch (_: Exception) {}
            recognizer = null
        }
    }

    private fun scheduleRestart(delayMs: Long) {
        if (!listening || restartPending) return
        restartPending = true
        main.postDelayed({
            restartPending = false
            if (listening) { try { recognizer?.startListening(buildIntent()) } catch (e: Exception) {
                send(mapOf("type" to "error", "message" to e.toString())) } }
        }, delayMs)
    }

    private fun emitResults(b: Bundle?, final: Boolean) {
        val list = b?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION) ?: return
        val text = list.firstOrNull() ?: return
        if (text.isBlank()) return
        send(mapOf("type" to (if (final) "final" else "partial"), "text" to text, "lang" to currentLang))
    }

    private val listener = object : RecognitionListener {
        override fun onReadyForSpeech(params: Bundle?) { busyCount = 0; send(mapOf("type" to "status", "message" to "ready")) }
        override fun onBeginningOfSpeech() { send(mapOf("type" to "speech", "on" to true)) }
        override fun onRmsChanged(rmsdB: Float) { send(mapOf("type" to "rms", "value" to rmsdB)) }
        override fun onBufferReceived(buffer: ByteArray?) {}
        override fun onEndOfSpeech() { send(mapOf("type" to "speech", "on" to false)) }
        override fun onError(error: Int) {
            if (!listening) return // we cancelled on purpose (phone is talking)
            // 7 = no match, 6 = speech timeout: keep listening, but don't hammer.
            if (error == 6 || error == 7) {
                quietCount++
                if (quietCount % 5 == 0) send(mapOf("type" to "error", "code" to error, "message" to "recognizer restarted ${quietCount}x with nothing heard"))
                scheduleRestart(if (quietCount > 3) 700 else 200)
                return
            }
            send(mapOf("type" to "error", "code" to error, "message" to "recognizer error $error"))
            if (error == 9) { listening = false; return } // insufficient permissions
            if (error == 8) { // recognizer busy: cancel, and after repeats rebuild it
                busyCount++
                main.post { try { recognizer?.cancel() } catch (_: Exception) {} }
                if (busyCount >= 3) {
                    busyCount = 0
                    main.post {
                        try { recognizer?.destroy() } catch (_: Exception) {}
                        recognizer = null
                        ensureRecognizer()
                    }
                }
                scheduleRestart(900)
                return
            }
            busyCount = 0
            scheduleRestart(150)
        }
        override fun onResults(results: Bundle?) { busyCount = 0; quietCount = 0; emitResults(results, true); scheduleRestart(50) }
        override fun onPartialResults(partialResults: Bundle?) { emitResults(partialResults, false) }
        override fun onEvent(eventType: Int, params: Bundle?) {}
        override fun onSegmentResults(segmentResults: Bundle) { quietCount = 0; emitResults(segmentResults, true) }
        override fun onEndOfSegmentedSession() { scheduleRestart(50) }
        override fun onLanguageDetection(results: Bundle) {
            if (Build.VERSION.SDK_INT >= 34) {
                val lang = results.getString(SpeechRecognizer.DETECTED_LANGUAGE)
                val conf = results.getInt(SpeechRecognizer.LANGUAGE_DETECTION_CONFIDENCE_LEVEL, 0)
                val switched = results.getString(SpeechRecognizer.LANGUAGE_SWITCH_RESULT)
                val changed = lang != null && lang != currentLang
                if (lang != null) currentLang = lang
                if (changed || switched != null) send(mapOf("type" to "lang", "lang" to lang, "confidence" to conf, "switch" to switched))
            }
        }
    }

    private fun checkSupport(languages: List<String>, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < 33) { result.success(mapOf("supported" to false)); return }
        val r = ensureRecognizer()
        if (r == null) { result.success(mapOf("supported" to false)); return }
        val i = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH)
        i.putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
        var done = false
        r.checkRecognitionSupport(i, executor, object : RecognitionSupportCallback {
            override fun onSupportResult(s: RecognitionSupport) {
                if (done) return; done = true
                main.post { result.success(mapOf(
                    "supported" to true,
                    "installed" to s.installedOnDeviceLanguages,
                    "pending" to s.pendingOnDeviceLanguages,
                    "downloadable" to s.supportedOnDeviceLanguages,
                    "online" to s.onlineLanguages)) }
            }
            override fun onError(error: Int) {
                if (done) return; done = true
                main.post { result.success(mapOf("supported" to false, "error" to error)) }
            }
        })
    }

    private fun download(language: String, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < 33) { result.success(false); return }
        val r = ensureRecognizer()
        if (r == null) { result.success(false); return }
        val i = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH)
        i.putExtra(RecognizerIntent.EXTRA_LANGUAGE, language)
        if (Build.VERSION.SDK_INT >= 34) {
            r.triggerModelDownload(i, executor, object : ModelDownloadListener {
                override fun onProgress(completedPercent: Int) { send(mapOf("type" to "download", "lang" to language, "percent" to completedPercent)) }
                override fun onSuccess() { send(mapOf("type" to "download", "lang" to language, "percent" to 100, "done" to true)) }
                override fun onScheduled() { send(mapOf("type" to "download", "lang" to language, "scheduled" to true)) }
                override fun onError(error: Int) { send(mapOf("type" to "download", "lang" to language, "error" to error)) }
            })
        } else {
            r.triggerModelDownload(i)
        }
        result.success(true)
    }

    override fun onDestroy() {
        stopListening()
        super.onDestroy()
    }
}
