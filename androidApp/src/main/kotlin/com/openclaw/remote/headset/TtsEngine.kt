package com.openclaw.remote.headset

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

interface TtsEngine {
    fun speak(text: String, apiKey: String? = null)
    fun stop()
    fun release()
}

abstract class BaseTtsEngine(protected val context: android.content.Context) : TtsEngine {
    protected val scope = CoroutineScope(Dispatchers.Main)

    protected var onSpeakStart: (() -> Unit)? = null
    protected var onSpeakDone: (() -> Unit)? = null

    fun setCallbacks(onStart: () -> Unit, onDone: () -> Unit) {
        onSpeakStart = onStart
        onSpeakDone = onDone
    }
}