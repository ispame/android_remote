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
        if (!_state.value.soundPlaybackEnabled || text.isBlank()) return false
        val engine = ttsEngineProvider() ?: return false
        engine.speak(text, apiKey, voiceId)
        markPlaybackStarted()
        return true
    }

    fun interruptCurrentPlayback() {
        ttsEngineProvider()?.stop()
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
        _state.update { it.copy(isSpeaking = false) }
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
}
