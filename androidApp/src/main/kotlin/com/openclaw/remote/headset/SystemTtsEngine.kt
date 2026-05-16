package com.openclaw.remote.headset

import android.content.Context
import android.media.AudioManager
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.util.Log
import java.util.Locale

class SystemTtsEngine(context: Context) : BaseTtsEngine(context) {

    private var tts: TextToSpeech? = null
    private var initialized = false

    init {
        tts = TextToSpeech(context) { status ->
            if (status == TextToSpeech.SUCCESS) {
                val result = tts?.setLanguage(Locale.CHINA)
                if (result == TextToSpeech.LANG_MISSING_DATA || result == TextToSpeech.LANG_NOT_SUPPORTED) {
                    tts?.setLanguage(Locale.getDefault())
                }
                tts?.setSpeechRate(0.9f)
                tts?.setPitch(1.0f)

                tts?.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                    override fun onStart(utteranceId: String?) {
                        Log.d(TAG, "TTS started")
                        onSpeakStart?.invoke()
                    }

                    override fun onDone(utteranceId: String?) {
                        Log.d(TAG, "TTS done")
                        onSpeakDone?.invoke()
                    }

                    override fun onError(utteranceId: String?) {
                        Log.e(TAG, "TTS error")
                        onSpeakDone?.invoke()
                    }
                })

                initialized = true
                Log.i(TAG, "System TTS initialized")
            } else {
                Log.e(TAG, "System TTS init failed")
            }
        }
    }

    override fun speak(text: String, apiKey: String?) {
        if (!initialized) {
            Log.w(TAG, "TTS not initialized")
            return
        }
        if (text.isBlank()) return

        val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        audioManager.mode = AudioManager.MODE_IN_COMMUNICATION
        audioManager.isSpeakerphoneOn = false

        tts?.speak(text, TextToSpeech.QUEUE_FLUSH, null, "system_tts_${System.currentTimeMillis()}")
        Log.d(TAG, "System TTS speaking")
    }

    override fun stop() {
        tts?.stop()
    }

    override fun release() {
        tts?.stop()
        tts?.shutdown()
        tts = null
        initialized = false
    }

    companion object {
        private const val TAG = "SystemTtsEngine"
    }
}