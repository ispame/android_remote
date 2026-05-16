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
    private lateinit var manager: SettingsManagerAndroid

    @Before
    fun setUp() = runTest {
        val context = ApplicationProvider.getApplicationContext<Context>()
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
}
