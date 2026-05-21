package com.openclaw.remote.headset

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update

data class SoundPlaybackState(
    val soundPlaybackEnabled: Boolean = true,
    val isSpeaking: Boolean = false,
)

class SoundPlaybackController(
    private val ttsEngineProvider: () -> TtsEngine?,
    private val fallbackTtsEngineProvider: () -> TtsEngine? = { null },
    private val shouldUseFallback: (Throwable) -> Boolean = { false },
    initialSoundPlaybackEnabled: Boolean = true,
    private val persistSoundPlaybackEnabled: (Boolean) -> Unit = {},
) {
    private val _state = MutableStateFlow(
        SoundPlaybackState(soundPlaybackEnabled = initialSoundPlaybackEnabled)
    )
    val state: StateFlow<SoundPlaybackState> = _state

    fun syncSoundPlaybackEnabled(enabled: Boolean) {
        applySoundPlaybackEnabled(enabled = enabled, persist = false)
    }

    fun setSoundPlaybackEnabled(enabled: Boolean) {
        applySoundPlaybackEnabled(enabled = enabled, persist = true)
    }

    fun speakAssistantReply(text: String, apiKey: String?, voiceId: String?): Boolean {
        return enqueueAssistantReplies(listOf(text), apiKey, voiceId)
    }

    fun enqueueAssistantReplies(texts: List<String>, apiKey: String?, voiceId: String?): Boolean {
        if (!_state.value.soundPlaybackEnabled) return false
        val requests = texts
            .map { it.trim() }
            .filter { it.isNotEmpty() }
            .map { SpeechRequest(text = it, apiKey = apiKey, voiceId = voiceId) }
        if (requests.isEmpty()) return false

        queue.addAll(requests)
        startNextIfIdle()
        return true
    }

    fun speakManualText(text: String, apiKey: String?, voiceId: String?): Boolean {
        val request = text.trim()
            .takeIf { it.isNotEmpty() }
            ?.let { SpeechRequest(text = it, apiKey = apiKey, voiceId = voiceId) }
            ?: return false

        interruptCurrentPlayback()
        queue.add(request)
        startNextIfIdle()
        return currentRequest != null
    }

    fun interruptCurrentPlayback() {
        queue.clear()
        currentRequest = null
        ttsEngineProvider()?.stop()
        fallbackTtsEngineProvider()?.stop()
        markPlaybackFinished()
    }

    fun onHeadsetWake() {
        if (!_state.value.soundPlaybackEnabled) {
            setSoundPlaybackEnabled(true)
        }
        interruptCurrentPlayback()
    }

    fun markPlaybackStarted() {
        _state.update { it.copy(isSpeaking = true) }
    }

    fun markPlaybackFinished() {
        currentRequest = null
        startNextIfIdle()
        if (currentRequest != null) return
        _state.update { it.copy(isSpeaking = false) }
    }

    fun markPlaybackFailed(error: Throwable) {
        val failedRequest = currentRequest
        if (
            failedRequest != null &&
            !failedRequest.isFallback &&
            shouldUseFallback(error)
        ) {
            val fallbackEngine = fallbackTtsEngineProvider()
            if (fallbackEngine != null) {
                val fallbackRequest = failedRequest.copy(apiKey = null, voiceId = null, isFallback = true)
                currentRequest = fallbackRequest
                log("Primary TTS failed, falling back to system TTS: ${error.message.orEmpty()}")
                if (fallbackEngine.speak(fallbackRequest.text, null, null)) {
                    markPlaybackStarted()
                    return
                }
                log("Fallback TTS rejected playback")
            }
        }

        currentRequest = null
        startNextIfIdle()
        if (currentRequest == null) {
            _state.update { it.copy(isSpeaking = false) }
        }
    }

    private fun applySoundPlaybackEnabled(enabled: Boolean, persist: Boolean) {
        val previous = _state.value.soundPlaybackEnabled
        if (!enabled) {
            interruptCurrentPlayback()
        }
        _state.update { it.copy(soundPlaybackEnabled = enabled) }
        if (persist && previous != enabled) {
            persistSoundPlaybackEnabled(enabled)
        }
    }

    private fun startNextIfIdle() {
        if (currentRequest != null) return
        val request = queue.removeFirstOrNull() ?: return
        val engine = ttsEngineProvider()
        if (engine == null) {
            markPlaybackFailed(IllegalStateException("TTS engine unavailable"))
            return
        }
        currentRequest = request
        if (engine.speak(request.text, request.apiKey, request.voiceId)) {
            markPlaybackStarted()
            return
        }
        markPlaybackFailed(IllegalStateException("TTS engine rejected playback"))
    }

    private data class SpeechRequest(
        val text: String,
        val apiKey: String?,
        val voiceId: String?,
        val isFallback: Boolean = false,
    )

    private val queue = ArrayDeque<SpeechRequest>()
    private var currentRequest: SpeechRequest? = null

    private fun log(message: String) {
        println("$TAG $message")
    }

    private companion object {
        private const val TAG = "SoundPlaybackController"
    }
}
