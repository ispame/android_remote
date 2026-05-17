package com.openclaw.remote.data

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

@RunWith(RobolectricTestRunner::class)
class SettingsManagerAndroidTest {
    private lateinit var context: Context
    private lateinit var manager: SettingsManagerAndroid

    @Before
    fun setUp() = runTest {
        context = ApplicationProvider.getApplicationContext()
        manager = SettingsManagerAndroid(context)
        manager.clearConfig()
    }

    @Test
    fun persistsTtsProviderConfiguration() = runTest {
        manager.updateConfig(
            GatewayConfig(
                gatewayUrl = "wss://boson-tech.top/ws",
                deviceId = "device-1",
                deviceLabel = "Chao iPhone",
                token = "token-1",
                pairedBackendId = "main",
                pairedBackendLabel = "OpenClaw",
                asrMode = "router",
                asrProfileId = "volcengine-bigmodel",
                ttsEngine = "minimax",
                minimaxApiKey = "test-key",
                minimaxVoiceId = "female_sunny_zh",
            )
        )

        val config = manager.configFlow.first()

        assertEquals("minimax", config.ttsEngine)
        assertEquals("test-key", config.minimaxApiKey)
        assertEquals("female_sunny_zh", config.minimaxVoiceId)
    }

    @Test
    fun soundPlaybackDefaultsToEnabledAndPersistsAcrossManagerInstances() = runTest {
        assertEquals(true, manager.soundPlaybackEnabledFlow.first())

        manager.updateSoundPlaybackEnabled(false)
        val restoredMuted = SettingsManagerAndroid(context)

        assertEquals(false, restoredMuted.soundPlaybackEnabledFlow.first())

        restoredMuted.updateSoundPlaybackEnabled(true)
        val restoredEnabled = SettingsManagerAndroid(context)

        assertEquals(true, restoredEnabled.soundPlaybackEnabledFlow.first())
    }
}
