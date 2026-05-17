package com.openclaw.remote.data

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

@RunWith(RobolectricTestRunner::class)
class SettingsManagerAndroidProfilesTest {
    private lateinit var manager: SettingsManagerAndroid

    @Before
    fun setUp() = runTest {
        val context = ApplicationProvider.getApplicationContext<Context>()
        manager = SettingsManagerAndroid(context)
        manager.clearConfig()
    }

    @Test
    fun startsWithLegacyProfileProjection() = runTest {
        manager.updateConfig(
            GatewayConfig(
                gatewayUrl = "wss://boson-tech.top/ws",
                deviceId = "device-1",
                deviceLabel = "Pixel",
                token = "token-1",
                pairedBackendId = "bk_openclaw",
                pairedBackendLabel = "OpenClaw",
                asrMode = "router",
                asrProfileId = "profile-a",
            )
        )

        val state = manager.profilesFlow.first()
        val config = manager.configFlow.first()

        assertEquals(1, state.profiles.size)
        assertEquals("bk_openclaw", state.selectedProfile.backendId)
        assertEquals("OpenClaw", state.selectedProfile.backendLabel)
        assertTrue(state.selectedProfile.isPaired)
        assertEquals("bk_openclaw", config.pairedBackendId)
        assertEquals(state.selectedProfile.id, config.profileId)
    }

    @Test
    fun scannedProfileReplacesEmptyInitialProfile() = runTest {
        val profile = manager.upsertScannedProfile(
            gatewayUrl = "wss://boson-tech.top/ws",
            backendId = "bk_openclaw",
            token = "token-openclaw",
            platform = AgentPlatform.OPENCLAW,
            label = "OpenClaw Agent",
        )

        val state = manager.profilesFlow.first()

        assertNotNull(profile)
        assertEquals(1, state.profiles.size)
        assertEquals("bk_openclaw", state.selectedProfile.backendId)
        assertEquals("OpenClaw Agent", state.selectedProfile.displayName)
        assertFalse(state.selectedProfile.isPaired)
    }

    @Test
    fun scannedProfileWithSameGatewayAndBackendOverwritesExistingProfile() = runTest {
        val first = manager.upsertScannedProfile(
            gatewayUrl = "wss://boson-tech.top/ws",
            backendId = "bk_openclaw",
            token = "old-token",
            platform = AgentPlatform.OPENCLAW,
            label = "Old Label",
        )
        val second = manager.upsertScannedProfile(
            gatewayUrl = "wss://boson-tech.top/ws",
            backendId = "bk_openclaw",
            token = "new-token",
            platform = AgentPlatform.HERMES,
            label = "Hermes Relay",
        )

        val state = manager.profilesFlow.first()

        assertEquals(first?.id, second?.id)
        assertEquals(1, state.profiles.size)
        assertEquals("new-token", state.selectedProfile.token)
        assertEquals(AgentPlatform.HERMES, state.selectedProfile.platform)
        assertEquals("Hermes Relay", state.selectedProfile.backendLabel)
    }

    @Test
    fun scannedProfileWithNewBackendAddsUntilMaximumOfThree() = runTest {
        manager.upsertScannedProfile("wss://boson-tech.top/ws", "bk_openclaw", "t1", AgentPlatform.OPENCLAW, "OpenClaw")
        manager.upsertScannedProfile("wss://boson-tech.top/ws", "bk_hermes", "t2", AgentPlatform.HERMES, "Hermes")
        manager.upsertScannedProfile("wss://boson-tech.top/ws", "bk_custom", "t3", AgentPlatform.CUSTOM, "Custom")

        val rejected = manager.upsertScannedProfile("wss://boson-tech.top/ws", "bk_fourth", "t4", AgentPlatform.CUSTOM, "Fourth")
        val state = manager.profilesFlow.first()

        assertNull(rejected)
        assertEquals(SettingsManager.MAX_AGENT_PROFILES, state.profiles.size)
        assertEquals("最多支持 3 个 Agent", manager.profileAcceptError("wss://boson-tech.top/ws", "bk_fourth"))
    }

    @Test
    fun rejectsNewProfileFromDifferentGateway() = runTest {
        manager.upsertScannedProfile("wss://boson-tech.top/ws", "bk_openclaw", "t1", AgentPlatform.OPENCLAW, "OpenClaw")

        val rejected = manager.upsertScannedProfile("wss://other.example/ws", "bk_other", "t2", AgentPlatform.CUSTOM, "Other")

        assertNull(rejected)
        assertEquals(
            "当前版本仅支持同一 Gateway 下最多 3 个 Agent",
            manager.profileAcceptError("wss://other.example/ws", "bk_other"),
        )
    }

    @Test
    fun selectingProfileProjectsConfigFlow() = runTest {
        val openclaw = manager.upsertScannedProfile("wss://boson-tech.top/ws", "bk_openclaw", "t1", AgentPlatform.OPENCLAW, "OpenClaw")
        val hermes = manager.upsertScannedProfile("wss://boson-tech.top/ws", "bk_hermes", "t2", AgentPlatform.HERMES, "Hermes")

        manager.selectProfile(openclaw!!.id)
        assertEquals("bk_openclaw", manager.configFlow.first().pairedBackendId)

        manager.selectProfile(hermes!!.id)
        val config = manager.configFlow.first()

        assertEquals("bk_hermes", config.pairedBackendId)
        assertEquals("t2", config.token)
        assertEquals(hermes.id, config.profileId)
    }
}
