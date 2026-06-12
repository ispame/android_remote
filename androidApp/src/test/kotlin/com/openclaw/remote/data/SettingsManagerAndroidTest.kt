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
    private lateinit var credentialVault: FakeCredentialVault

    @Before
    fun setUp() = runTest {
        context = ApplicationProvider.getApplicationContext()
        credentialVault = FakeCredentialVault()
        manager = SettingsManagerAndroid(context, credentialVault)
        manager.clearConfig()
    }

    @Test
    fun persistsTtsProviderConfiguration() = runTest {
        manager.updateConfig(
            GatewayConfig(
                gatewayUrl = "wss://boson-tech.top/ws",
                accountId = "acct-1",
                accessToken = "access-1",
                refreshToken = "refresh-1",
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
        assertEquals("test-key", credentialVault.get(LOCAL_TTS_MINIMAX_CREDENTIAL_ID))
    }

    @Test
    fun persistsGenericLocalCredentials() = runTest {
        manager.updateLocalCredential("llm:openai-compatible", "sk-openai")
        manager.updateLocalCredential("tts:minimax", "sk-minimax")

        assertEquals("sk-openai", manager.localCredential("llm:openai-compatible"))
        assertEquals("sk-minimax", manager.localCredential("tts:minimax"))

        manager.updateLocalCredential("llm:openai-compatible", "")

        assertEquals(null, manager.localCredential("llm:openai-compatible"))
        assertEquals("sk-minimax", manager.localCredential("tts:minimax"))
    }

    @Test
    fun minimaxApiKeyIsNotRestoredFromPlaintextDataStoreWhenVaultIsMissing() = runTest {
        manager.updateConfig(
            GatewayConfig(
                ttsEngine = "minimax",
                minimaxApiKey = "local-only-key",
                minimaxVoiceId = "female_sunny_zh",
            )
        )

        val restoredWithoutVault = SettingsManagerAndroid(context, FakeCredentialVault()).configFlow.first()

        assertEquals("minimax", restoredWithoutVault.ttsEngine)
        assertEquals("", restoredWithoutVault.minimaxApiKey)
        assertEquals("female_sunny_zh", restoredWithoutVault.minimaxVoiceId)
    }

    @Test
    fun persistsAccountScopedAuthSession() = runTest {
        manager.updateConfig(
            GatewayConfig(
                gatewayUrl = "wss://boson-tech.top/ws",
                accountId = "acct-123",
                accessToken = "access-token-123",
                refreshToken = "refresh-token-123",
                deviceLabel = "Pixel",
            )
        )

        val restored = SettingsManagerAndroid(context, credentialVault).configFlow.first()

        assertEquals("acct-123", restored.accountId)
        assertEquals("access-token-123", restored.accessToken)
        assertEquals("refresh-token-123", restored.refreshToken)
    }

    @Test
    fun soundPlaybackDefaultsToEnabledAndPersistsAcrossManagerInstances() = runTest {
        assertEquals(true, manager.soundPlaybackEnabledFlow.first())

        manager.updateSoundPlaybackEnabled(false)
        val restoredMuted = SettingsManagerAndroid(context, credentialVault)

        assertEquals(false, restoredMuted.soundPlaybackEnabledFlow.first())

        restoredMuted.updateSoundPlaybackEnabled(true)
        val restoredEnabled = SettingsManagerAndroid(context, credentialVault)

        assertEquals(true, restoredEnabled.soundPlaybackEnabledFlow.first())
    }
}
