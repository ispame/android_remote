package com.openclaw.remote.viewmodel

import com.openclaw.remote.data.AgentPlatform
import com.openclaw.remote.data.AgentProfile
import com.openclaw.remote.data.AgentAvailabilityStatus
import com.openclaw.remote.domain.ConnectionState
import com.openclaw.remote.domain.PairingState
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class ChatProfileRoutingTest {
    private val profiles = listOf(
        AgentProfile(
            id = "profile-openclaw",
            appClientId = "device-1",
            platform = AgentPlatform.OPENCLAW,
            gatewayUrl = "wss://boson-tech.top/ws",
            backendId = "bk_openclaw",
            backendLabel = "OpenClaw",
        ),
        AgentProfile(
            id = "profile-hermes",
            appClientId = "device-1",
            platform = AgentPlatform.HERMES,
            gatewayUrl = "wss://boson-tech.top/ws",
            backendId = "bk_hermes",
            backendLabel = "Hermes",
        ),
    )

    @Test
    fun resolvesProfileByBackendIdBeforeFallingBackToActiveProfile() {
        assertEquals(
            "profile-hermes",
            resolveProfileIdForBackendId(
                profiles = profiles,
                backendId = "bk_hermes",
                activeProfileId = "profile-openclaw",
            ),
        )
    }

    @Test
    fun blankBackendIdFallsBackToActiveProfile() {
        assertEquals(
            "profile-openclaw",
            resolveProfileIdForBackendId(
                profiles = profiles,
                backendId = "",
                activeProfileId = "profile-openclaw",
            ),
        )
    }

    @Test
    fun unknownBackendWithoutActiveProfileIsIgnored() {
        assertNull(
            resolveProfileIdForBackendId(
                profiles = profiles,
                backendId = "bk_unknown",
                activeProfileId = null,
            ),
        )
    }

    @Test
    fun unreadOnlyIncrementsForAssistantMessagesOutsideActiveProfile() {
        assertTrue(shouldIncrementUnreadCount("profile-hermes", "profile-openclaw", "assistant"))
        assertFalse(shouldIncrementUnreadCount("profile-openclaw", "profile-openclaw", "assistant"))
        assertFalse(shouldIncrementUnreadCount("profile-hermes", "profile-openclaw", "user"))
    }

    @Test
    fun agentIsAvailableOnlyAfterCurrentSocketPairResponse() {
        assertEquals(
            AgentAvailabilityStatus.CONNECTING,
            agentAvailabilityForStatus(
                hasBackendId = true,
                pairingState = PairingState.PAIRED,
                connectionState = ConnectionState.REGISTERED,
            ),
        )
        assertEquals(
            AgentAvailabilityStatus.PAIRING,
            agentAvailabilityForStatus(
                hasBackendId = true,
                pairingState = PairingState.PENDING,
                connectionState = ConnectionState.REGISTERED,
            ),
        )
        assertEquals(
            AgentAvailabilityStatus.AVAILABLE,
            agentAvailabilityForStatus(
                hasBackendId = true,
                pairingState = PairingState.PAIRED,
                connectionState = ConnectionState.PAIRED,
            ),
        )
    }

    @Test
    fun chatPayloadsCanSendOnlyAfterCurrentSocketPairResponse() {
        assertFalse(canSendChatPayload(PairingState.PAIRED, ConnectionState.REGISTERED))
        assertFalse(canSendChatPayload(PairingState.PENDING, ConnectionState.REGISTERED))
        assertTrue(canSendChatPayload(PairingState.PAIRED, ConnectionState.PAIRED))
    }
}
