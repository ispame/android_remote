package com.openclaw.remote.headset

import android.content.Context
import android.media.AudioManager
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.util.Log
import java.util.Locale

class HeadsetTtsSpeaker(private val context: Context) : TextToSpeech.OnInitListener {

    private var tts: TextToSpeech? = null
    private var initialized = false
    private var onSpeakStart: (() -> Unit)? = null
    private var onSpeakDone: (() -> Unit)? = null

    init {
        tts = TextToSpeech(context, this)
    }

    override fun onInit(status: Int) {
        if (status == TextToSpeech.SUCCESS) {
            val result = tts?.setLanguage(Locale.CHINA)
            if (result == TextToSpeech.LANG_MISSING_DATA || result == TextToSpeech.LANG_NOT_SUPPORTED) {
                Log.w(TAG, "Chinese TTS not supported, falling back to default")
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
            Log.i(TAG, "TTS initialized successfully")
        } else {
            Log.e(TAG, "TTS initialization failed")
        }
    }

    fun speak(text: String) {
        if (!initialized) {
            Log.w(TAG, "TTS not initialized yet")
            return
        }
        if (text.isBlank()) {
            Log.w(TAG, "Empty text, skipping TTS")
            return
        }

        // 配置音频管理器，确保走蓝牙输出
        val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        audioManager.mode = AudioManager.MODE_IN_COMMUNICATION
        audioManager.isSpeakerphoneOn = false

        val params = android.os.Bundle()
        tts?.speak(text, TextToSpeech.QUEUE_FLUSH, params, "headset_tts_${System.currentTimeMillis()}")
        Log.d(TAG, "TTS speaking: ${text.take(50)}...")
    }

    fun stop() {
        tts?.stop()
    }

    fun setCallbacks(onStart: () -> Unit, onDone: () -> Unit) {
        onSpeakStart = onStart
        onSpeakDone = onDone
    }

    fun release() {
        tts?.stop()
        tts?.shutdown()
        tts = null
        initialized = false
    }

    companion object {
        private const val TAG = "HeadsetTtsSpeaker"
    }
}