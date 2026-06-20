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
        manager = SettingsManagerAndroid(context, FakeCredentialVault())
        manager.clearConfig()
    }

    @Test
    fun startsWithLegacyProfileProjection() = runTest {
        manager.updateConfig(
            GatewayConfig(
                gatewayUrl = "wss://boson-tech.top/ws",
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
    fun legacyProfileIdIsStableBeforeProfilesArePersisted() = runTest {
        val firstConfig = manager.configFlow.first()
        val firstState = manager.profilesFlow.first()

        manager.updateDeviceLabel("Pixel")

        val secondConfig = manager.configFlow.first()
        val secondState = manager.profilesFlow.first()

        assertEquals(firstConfig.profileId, secondConfig.profileId)
        assertEquals(firstState.selectedProfile.id, secondState.selectedProfile.id)
        assertEquals(firstConfig.profileId, firstState.selectedProfile.id)
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
        assertNull(manager.configFlow.first().pairedBackendId)
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
    fun scannedHttpsGatewayMatchesExistingWebSocketGateway() = runTest {
        manager.upsertScannedProfile(
            gatewayUrl = "wss://boson-tech.top/ws",
            backendId = "bk_hermes",
            token = "token-hermes",
            platform = AgentPlatform.HERMES,
            label = "Hermes",
        )

        val codex = manager.upsertScannedProfile(
            gatewayUrl = "https://boson-tech.top",
            backendId = "codex-mac-mini",
            token = "token-codex",
            platform = AgentPlatform.CODEX,
            label = "Codex",
        )

        val state = manager.profilesFlow.first()

        assertNotNull(codex)
        assertEquals(2, state.profiles.size)
        assertEquals("wss://boson-tech.top/ws", codex?.gatewayUrl)
        assertEquals("wss://boson-tech.top/ws", state.selectedProfile.gatewayUrl)
        assertNull(manager.profileAcceptError("https://boson-tech.top", "codex-mac-mini"))
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
        var config = manager.configFlow.first()
        assertNull(config.pairedBackendId)
        assertEquals("t1", config.token)

        manager.updatePairedBackend("bk_openclaw", "OpenClaw", openclaw.id)
        assertEquals("bk_openclaw", manager.configFlow.first().pairedBackendId)

        manager.selectProfile(hermes!!.id)
        config = manager.configFlow.first()

        assertNull(config.pairedBackendId)
        assertEquals("t2", config.token)
        assertEquals(hermes.id, config.profileId)

        manager.updatePairedBackend("bk_hermes", "Hermes", hermes.id)
        assertEquals("bk_hermes", manager.configFlow.first().pairedBackendId)
    }

    @Test
    fun saveProfileClearsPairingWhenTokenChanges() = runTest {
        val profile = manager.upsertScannedProfile(
            gatewayUrl = "wss://boson-tech.top/ws",
            backendId = "bk_openclaw",
            token = "good-token",
            platform = AgentPlatform.OPENCLAW,
            label = "OpenClaw",
        )!!
        manager.updatePairedBackend("bk_openclaw", "OpenClaw", profile.id)

        val pairedProfile = manager.profilesFlow.first().selectedProfile
        assertTrue(pairedProfile.isPaired)

        val saved = manager.saveProfile(
            pairedProfile.copy(token = "wrong-token", isPaired = true),
            select = true,
        )

        val state = manager.profilesFlow.first()
        val config = manager.configFlow.first()

        assertTrue(saved)
        assertEquals("wrong-token", state.selectedProfile.token)
        assertFalse(state.selectedProfile.isPaired)
        assertNull(config.pairedBackendId)
    }

    @Test
    fun setProfilePinnedPersistsPinStateWithoutChangingSelection() = runTest {
        val openclaw = manager.upsertScannedProfile("wss://boson-tech.top/ws", "bk_openclaw", "t1", AgentPlatform.OPENCLAW, "OpenClaw")!!
        val hermes = manager.upsertScannedProfile("wss://boson-tech.top/ws", "bk_hermes", "t2", AgentPlatform.HERMES, "Hermes")!!
        manager.selectProfile(openclaw.id)

        manager.setProfilePinned(hermes.id, true)

        val state = manager.profilesFlow.first()
        assertEquals(openclaw.id, state.selectedProfileId)
        assertEquals(true, state.profiles.first { it.id == hermes.id }.isPinned)

        manager.setProfilePinned(hermes.id, false)

        assertEquals(false, manager.profilesFlow.first().profiles.first { it.id == hermes.id }.isPinned)
    }

    @Test
    fun accountChangeClearsAccountScopedAgentProfiles() = runTest {
        manager.updateConfig(
            GatewayConfig(
                gatewayUrl = "wss://boson-tech.top/ws",
                accountId = "acct-old",
                accessToken = "access-old",
                refreshToken = "refresh-old",
                deviceLabel = "Pixel",
            )
        )
        manager.upsertScannedProfile("wss://boson-tech.top/ws", "bk_old", "token-old", AgentPlatform.OPENCLAW, "Old Agent")
        val paired = manager.profilesFlow.first().selectedProfile
        manager.updatePairedBackend("bk_old", "Old Agent", paired.id)

        manager.updateConfig(
            manager.configFlow.first().copy(
                accountId = "acct-new",
                accessToken = "access-new",
                refreshToken = "refresh-new",
                pairedBackendId = null,
                pairedBackendLabel = null,
            )
        )

        val state = manager.profilesFlow.first()
        val config = manager.configFlow.first()

        assertEquals("acct-new", config.accountId)
        assertEquals("Pixel", config.deviceLabel)
        assertEquals(1, state.profiles.size)
        assertEquals("", state.selectedProfile.backendId)
        assertFalse(state.selectedProfile.isPaired)
        assertNull(config.pairedBackendId)
    }
}
