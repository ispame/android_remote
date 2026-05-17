package com.openclaw.remote.headset

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SoundPlaybackControllerTest {
    @Test
    fun mutedPlaybackSkipsAssistantSpeech() {
        val engine = FakeTtsEngine()
        val controller = SoundPlaybackController(
            ttsEngineProvider = { engine },
            initialSoundPlaybackEnabled = false,
        )

        val didSpeak = controller.speakAssistantReply("长回复", apiKey = null, voiceId = null)

        assertFalse(didSpeak)
        assertEquals(0, engine.speakCount)
        assertFalse(controller.state.value.isSpeaking)
    }

    @Test
    fun turningSoundOffPersistsAndStopsCurrentPlayback() {
        val engine = FakeTtsEngine()
        val persisted = mutableListOf<Boolean>()
        val controller = SoundPlaybackController(
            ttsEngineProvider = { engine },
            initialSoundPlaybackEnabled = true,
            persistSoundPlaybackEnabled = { persisted += it },
        )
        controller.speakAssistantReply("长回复", apiKey = "key", voiceId = "voice")

        controller.setSoundPlaybackEnabled(false)

        assertEquals(listOf(false), persisted)
        assertEquals(1, engine.stopCount)
        assertFalse(controller.state.value.soundPlaybackEnabled)
        assertFalse(controller.state.value.isSpeaking)
    }

    @Test
    fun interruptStopsCurrentPlaybackWithoutChangingPreference() {
        val engine = FakeTtsEngine()
        val persisted = mutableListOf<Boolean>()
        val controller = SoundPlaybackController(
            ttsEngineProvider = { engine },
            initialSoundPlaybackEnabled = true,
            persistSoundPlaybackEnabled = { persisted += it },
        )
        controller.speakAssistantReply("长回复", apiKey = null, voiceId = null)

        controller.interruptCurrentPlayback()

        assertEquals(1, engine.stopCount)
        assertTrue(controller.state.value.soundPlaybackEnabled)
        assertFalse(controller.state.value.isSpeaking)
        assertTrue(persisted.isEmpty())
    }

    @Test
    fun headsetWakeRestoresMutedPlaybackPersistentlyAndInterrupts() {
        val engine = FakeTtsEngine()
        val persisted = mutableListOf<Boolean>()
        val controller = SoundPlaybackController(
            ttsEngineProvider = { engine },
            initialSoundPlaybackEnabled = false,
            persistSoundPlaybackEnabled = { persisted += it },
        )

        controller.onHeadsetWake()

        assertEquals(listOf(true), persisted)
        assertEquals(1, engine.stopCount)
        assertTrue(controller.state.value.soundPlaybackEnabled)
        assertFalse(controller.state.value.isSpeaking)
    }

    @Test
    fun headsetWakeWhenAlreadyEnabledOnlyInterruptsCurrentPlayback() {
        val engine = FakeTtsEngine()
        val persisted = mutableListOf<Boolean>()
        val controller = SoundPlaybackController(
            ttsEngineProvider = { engine },
            initialSoundPlaybackEnabled = true,
            persistSoundPlaybackEnabled = { persisted += it },
        )
        controller.speakAssistantReply("长回复", apiKey = null, voiceId = null)

        controller.onHeadsetWake()

        assertTrue(persisted.isEmpty())
        assertEquals(1, engine.stopCount)
        assertTrue(controller.state.value.soundPlaybackEnabled)
        assertFalse(controller.state.value.isSpeaking)
    }
}

private class FakeTtsEngine : TtsEngine {
    var speakCount = 0
        private set
    var stopCount = 0
        private set

    override fun speak(text: String, apiKey: String?, voiceId: String?) {
        speakCount += 1
    }

    override fun stop() {
        stopCount += 1
    }

    override fun release() = Unit
}
