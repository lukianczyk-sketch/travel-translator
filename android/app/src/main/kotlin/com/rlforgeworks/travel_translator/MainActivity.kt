package com.rlforgeworks.travel_translator

import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
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
                    startListening()
                    result.success(true)
                }
                "stop" -> { stopListening(); result.success(true) }
                "pause" -> { pauseListening(); result.success(true) }
                "resume" -> { if (!listening) startListening(); result.success(true) }
                "checkSupport" -> checkSupport(call.argument<List<String>>("languages") ?: listOf(), result)
                "download" -> download(call.argument<String>("language") ?: "en-US", result)
                else -> result.notImplemented()
            }
        }
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
            i.putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS, 700)
            i.putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_POSSIBLY_COMPLETE_SILENCE_LENGTH_MILLIS, 500)
        }
        if (Build.VERSION.SDK_INT >= 34 && langs.size > 1) {
            i.putExtra(RecognizerIntent.EXTRA_ENABLE_LANGUAGE_DETECTION, true)
            i.putStringArrayListExtra(RecognizerIntent.EXTRA_LANGUAGE_DETECTION_ALLOWED_LANGUAGES, langs)
            i.putExtra(RecognizerIntent.EXTRA_ENABLE_LANGUAGE_SWITCH, RecognizerIntent.LANGUAGE_SWITCH_QUICK_RESPONSE)
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
        override fun onReadyForSpeech(params: Bundle?) { send(mapOf("type" to "status", "message" to "ready")) }
        override fun onBeginningOfSpeech() { send(mapOf("type" to "speech", "on" to true)) }
        override fun onRmsChanged(rmsdB: Float) { send(mapOf("type" to "rms", "value" to rmsdB)) }
        override fun onBufferReceived(buffer: ByteArray?) {}
        override fun onEndOfSpeech() { send(mapOf("type" to "speech", "on" to false)) }
        override fun onError(error: Int) {
            // 7 = no match, 6 = speech timeout: just keep listening.
            if (error != 7 && error != 6) send(mapOf("type" to "error", "code" to error, "message" to "recognizer error $error"))
            if (error == 9) { listening = false; return } // insufficient permissions
            scheduleRestart(if (error == 8) 600 else 150)   // 8 = busy
        }
        override fun onResults(results: Bundle?) { emitResults(results, true); scheduleRestart(50) }
        override fun onPartialResults(partialResults: Bundle?) { emitResults(partialResults, false) }
        override fun onEvent(eventType: Int, params: Bundle?) {}
        override fun onSegmentResults(segmentResults: Bundle) { emitResults(segmentResults, true) }
        override fun onEndOfSegmentedSession() { scheduleRestart(50) }
        override fun onLanguageDetection(results: Bundle) {
            if (Build.VERSION.SDK_INT >= 34) {
                val lang = results.getString(SpeechRecognizer.DETECTED_LANGUAGE)
                val conf = results.getInt(SpeechRecognizer.LANGUAGE_DETECTION_CONFIDENCE_LEVEL, 0)
                val switched = results.getString(SpeechRecognizer.LANGUAGE_SWITCH_RESULT)
                if (lang != null) currentLang = lang
                send(mapOf("type" to "lang", "lang" to lang, "confidence" to conf, "switch" to switched))
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
