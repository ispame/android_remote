package com.openclaw.remote.viewmodel

import com.openclaw.remote.data.GatewayConfig
import com.openclaw.remote.data.AgentAvailabilityStatus
import com.openclaw.remote.data.ChatMessage
import com.openclaw.remote.domain.ConnectionState
import com.openclaw.remote.domain.PairingState
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class ChatViewModelConfigTest {
    @Test
    fun connectionKeyIgnoresPairingLabelAndTtsSettings() {
        val base = GatewayConfig(
            gatewayUrl = "wss://boson-tech.top",
            deviceLabel = "phone",
            token = "token",
            pairedBackendId = "bk_openclaw",
            pairedBackendLabel = "OpenClaw",
            asrMode = "router",
            asrProfileId = "profile-a",
            ttsEngine = "system",
            minimaxApiKey = "",
        )
        val changedNonConnectionSettings = base.copy(
            pairedBackendLabel = "OpenClaw Agent",
            ttsEngine = "minimax",
            minimaxApiKey = "test-key",
        )

        assertFalse(
            shouldReconnectForConfig(
                previous = base.toChatConnectionKey(),
                next = changedNonConnectionSettings.toChatConnectionKey(),
            ),
        )
    }

    @Test
    fun connectionKeyIgnoresPairingTargetChanges() {
        val base = GatewayConfig(pairedBackendId = "bk_openclaw")
        val changedBackend = base.copy(pairedBackendId = "bk_other")

        assertFalse(
            shouldReconnectForConfig(
                previous = base.toChatConnectionKey(),
                next = changedBackend.toChatConnectionKey(),
            ),
        )
    }

    @Test
    fun connectionKeyIgnoresBackendQrToken() {
        val base = GatewayConfig(
            token = "backend-qr-token-a",
            accessToken = "access-token-a",
        )
        val changed = base.copy(
            token = "backend-qr-token-b",
        )

        assertFalse(
            shouldReconnectForConfig(
                previous = base.toChatConnectionKey(),
                next = changed.toChatConnectionKey(),
            ),
        )
    }

    @Test
    fun connectionKeyChangesWhenAccessTokenChanges() {
        val base = GatewayConfig(
            accessToken = "access-token-a",
            accountId = "acct-1",
        )
        val changed = base.copy(accessToken = "access-token-b")

        assertTrue(
            shouldReconnectForConfig(
                previous = base.toChatConnectionKey(),
                next = changed.toChatConnectionKey(),
            ),
        )
    }

    @Test
    fun pairRequestRefreshesConnectionWhenTargetProfileDiffersFromActiveManager() {
        val active = GatewayConfig(profileId = "openclaw")
        val target = active.copy(profileId = "hermes")

        assertTrue(
            shouldRefreshConnectionForPairRequest(
                previous = active.toChatConnectionKey(),
                next = target.toChatConnectionKey(),
            ),
        )
    }

    @Test
    fun pairedBackendPersistenceSkipsUnchangedValues() {
        val config = GatewayConfig(
            pairedBackendId = "bk_openclaw",
            pairedBackendLabel = "OpenClaw",
        )

        assertFalse(shouldPersistPairedBackend(config, "bk_openclaw", "OpenClaw"))
        assertTrue(shouldPersistPairedBackend(config, "bk_openclaw", "OpenClaw Agent"))
    }

    @Test
    fun oldestHistoryTimestampUsesOldestLoadedRawTimestamp() {
        val messages = listOf(
            ChatMessage(content = "older", timestamp = "09:10", rawTimestamp = "2026-05-21T01:10:00.000Z"),
            ChatMessage(content = "newer", timestamp = "09:12", rawTimestamp = "2026-05-21T01:12:00.000Z"),
            ChatMessage(content = "pending", timestamp = "09:13"),
        )

        assertEquals("2026-05-21T01:10:00.000Z", oldestHistoryTimestamp(messages))
    }

    @Test
    fun authenticatedConnectionRequiresNonBlankAccessToken() {
        assertFalse(shouldMaintainAuthenticatedConnection(" ", "2099-01-01T00:00:00.000Z"))
        assertTrue(shouldMaintainAuthenticatedConnection("access-token", "2099-01-01T00:00:00.000Z"))
    }

    @Test
    fun authenticatedConnectionWaitsForRefreshWhenAccessTokenIsExpired() {
        assertFalse(shouldMaintainAuthenticatedConnection("access-token", "2000-01-01T00:00:00.000Z"))
    }

    @Test
    fun selectedProfileCannotSendThroughDifferentActiveManager() {
        val route = checkSelectedProfilePayloadRoute(
            selectedProfileId = "agent2",
            activeConnectionProfileId = "agent1",
            selectedBackendId = "bk_agent2",
            registeredBackendId = "bk_agent1",
            pairingState = PairingState.PAIRED,
            connectionState = ConnectionState.PAIRED,
        )

        assertFalse(route.canSend)
        assertEquals(ChatPayloadRouteBlockReason.PROFILE_NOT_ACTIVE, route.reason)
    }

    @Test
    fun selectedProfileCannotSendWhenRegisteredBackendDiffers() {
        val route = checkSelectedProfilePayloadRoute(
            selectedProfileId = "agent2",
            activeConnectionProfileId = "agent2",
            selectedBackendId = "bk_agent2",
            registeredBackendId = "bk_agent1",
            pairingState = PairingState.PAIRED,
            connectionState = ConnectionState.PAIRED,
        )

        assertFalse(route.canSend)
        assertEquals(ChatPayloadRouteBlockReason.BACKEND_MISMATCH, route.reason)
    }

    @Test
    fun selectedProfileCanSendOnlyWhenProfileAndBackendBothMatch() {
        val route = checkSelectedProfilePayloadRoute(
            selectedProfileId = "agent2",
            activeConnectionProfileId = "agent2",
            selectedBackendId = "bk_agent2",
            registeredBackendId = "bk_agent2",
            pairingState = PairingState.PAIRED,
            connectionState = ConnectionState.PAIRED,
        )

        assertTrue(route.canSend)
        assertEquals(null, route.reason)
    }

    @Test
    fun profileCannotDisplayAvailableFromAnotherProfilesManagerState() {
        val availabilityConnectionState = connectionStateForProfileAvailability(
            profileId = "agent2",
            selectedProfileId = "agent1",
            activeConnectionProfileId = "agent1",
            selectedConnectionState = ConnectionState.PAIRED,
            profileConnectionState = ConnectionState.DISCONNECTED,
            routerConnectionState = ConnectionState.PAIRED,
        )

        assertEquals(
            ConnectionState.DISCONNECTED,
            availabilityConnectionState,
        )
        assertEquals(
            AgentAvailabilityStatus.CONNECTING,
            agentAvailabilityForStatus(
                hasBackendId = true,
                pairingState = PairingState.PAIRED,
                connectionState = availabilityConnectionState,
            ),
        )
    }

    @Test
    fun profileDisplaysAvailableAfterItsOwnRuntimeEvidence() {
        val availabilityConnectionState = connectionStateForProfileAvailability(
            profileId = "agent2",
            selectedProfileId = "agent1",
            activeConnectionProfileId = "agent1",
            selectedConnectionState = ConnectionState.PAIRED,
            profileConnectionState = ConnectionState.PAIRED,
            routerConnectionState = ConnectionState.PAIRED,
        )

        assertEquals(ConnectionState.PAIRED, availabilityConnectionState)
        assertEquals(
            AgentAvailabilityStatus.AVAILABLE,
            agentAvailabilityForStatus(
                hasBackendId = true,
                pairingState = PairingState.PAIRED,
                connectionState = availabilityConnectionState,
            ),
        )
    }

    @Test
    fun routerReconnectDowngradesReachableProfileToConnecting() {
        val availabilityConnectionState = connectionStateForProfileAvailability(
            profileId = "agent2",
            selectedProfileId = "agent1",
            activeConnectionProfileId = "agent1",
            selectedConnectionState = ConnectionState.CONNECTING,
            profileConnectionState = ConnectionState.PAIRED,
            routerConnectionState = ConnectionState.CONNECTING,
        )

        assertEquals(ConnectionState.CONNECTING, availabilityConnectionState)
        assertEquals(
            AgentAvailabilityStatus.CONNECTING,
            agentAvailabilityForStatus(
                hasBackendId = true,
                pairingState = PairingState.PAIRED,
                connectionState = availabilityConnectionState,
            ),
        )
    }
}
