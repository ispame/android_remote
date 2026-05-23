package com.openclaw.remote.viewmodel

import com.openclaw.remote.data.AgentPlatform
import com.openclaw.remote.data.AgentProfile
import com.openclaw.remote.data.AgentAvailabilityStatus
import com.openclaw.remote.data.ChatMessage
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
            platform = AgentPlatform.OPENCLAW,
            gatewayUrl = "wss://boson-tech.top/ws",
            backendId = "bk_openclaw",
            backendLabel = "OpenClaw",
        ),
        AgentProfile(
            id = "profile-hermes",
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
    fun unknownBackendDoesNotFallBackToActiveProfile() {
        assertNull(
            resolveProfileIdForBackendId(
                profiles = profiles,
                backendId = "bk_unknown",
                activeProfileId = "profile-openclaw",
            ),
        )
    }

    @Test
    fun agentAvailabilityUsesSimpleUserFacingLabels() {
        assertEquals(
            "未配对",
            agentAvailabilityForStatus(
                hasBackendId = false,
                pairingState = PairingState.UNPAIRED,
                connectionState = ConnectionState.DISCONNECTED,
            ).label,
        )
        assertEquals(
            "未配对",
            agentAvailabilityForStatus(
                hasBackendId = true,
                pairingState = PairingState.UNPAIRED,
                connectionState = ConnectionState.PAIRED,
            ).label,
        )
        assertEquals(
            "连接中",
            agentAvailabilityForStatus(
                hasBackendId = true,
                pairingState = PairingState.PAIRED,
                connectionState = ConnectionState.CONNECTING,
            ).label,
        )
        assertEquals(
            "连接中",
            agentAvailabilityForStatus(
                hasBackendId = true,
                pairingState = PairingState.PENDING,
                connectionState = ConnectionState.REGISTERED,
            ).label,
        )
        assertEquals(
            "可用",
            agentAvailabilityForStatus(
                hasBackendId = true,
                pairingState = PairingState.PAIRED,
                connectionState = ConnectionState.REGISTERED,
            ).label,
        )
        assertEquals(
            "可用",
            agentAvailabilityForStatus(
                hasBackendId = true,
                pairingState = PairingState.PAIRED,
                connectionState = ConnectionState.PAIRED,
            ).label,
        )
    }

    @Test
    fun chatPayloadsCanSendOnlyAfterCurrentSocketPairResponse() {
        assertFalse(canSendChatPayload(PairingState.PAIRED, ConnectionState.REGISTERED))
        assertFalse(canSendChatPayload(PairingState.PENDING, ConnectionState.REGISTERED))
        assertTrue(canSendChatPayload(PairingState.PAIRED, ConnectionState.PAIRED))
    }

    @Test
    fun backendRuntimeEvidenceMarksOnlyThatProfileReachable() {
        val state = ChatProfileRuntimeState(
            registeredBackendId = "bk_hermes",
            pairingState = PairingState.PAIRED,
            connectionState = ConnectionState.DISCONNECTED,
        )

        val reachableState = state.withReachableBackend("bk_hermes")

        assertEquals(PairingState.PAIRED, reachableState.pairingState)
        assertEquals(ConnectionState.PAIRED, reachableState.connectionState)
        assertEquals("bk_hermes", reachableState.registeredBackendId)
    }

    @Test
    fun blankBackendRuntimeEvidenceDoesNotMarkProfileReachable() {
        val state = ChatProfileRuntimeState(
            registeredBackendId = null,
            pairingState = PairingState.UNPAIRED,
            connectionState = ConnectionState.DISCONNECTED,
        )

        val unchangedState = state.withReachableBackend(null)

        assertEquals(PairingState.UNPAIRED, unchangedState.pairingState)
        assertEquals(ConnectionState.DISCONNECTED, unchangedState.connectionState)
        assertEquals(null, unchangedState.registeredBackendId)
    }

    @Test
    fun unpairedProfileCannotBeRevivedByStalePairedRuntimeState() {
        val staleRuntime = ChatProfileRuntimeState(
            registeredBackendId = "bk_agent1",
            pairedBackendLabel = "Agent 1",
            pairingState = PairingState.PAIRED,
            connectionState = ConnectionState.PAIRED,
        )
        val unpairedProfile = profiles[1].copy(
            backendId = "bad_agent2",
            backendLabel = null,
            isPaired = false,
        )

        val mergedState = staleRuntime.withProfilePairing(unpairedProfile)

        assertEquals(null, mergedState.registeredBackendId)
        assertEquals(null, mergedState.pairedBackendLabel)
        assertEquals(PairingState.UNPAIRED, mergedState.pairingState)
        assertEquals(ConnectionState.DISCONNECTED, mergedState.connectionState)
    }

    @Test
    fun nonActiveProfileKeepsOwnRuntimeWhenPersistingSelectionState() {
        val existingAgent2State = ChatProfileRuntimeState(
            registeredBackendId = null,
            pairedBackendLabel = null,
            pairingState = PairingState.UNPAIRED,
            connectionState = ConnectionState.DISCONNECTED,
            messages = listOf(ChatMessage("agent2 history", "2026-05-19T10:00:00Z", "assistant")),
        )
        val activeAgent1Messages = listOf(ChatMessage("agent1 reply", "2026-05-19T10:01:00Z", "assistant"))

        val persistedState = runtimeStateForProfilePersistence(
            existingState = existingAgent2State,
            isManagerForProfile = false,
            currentRegisteredBackendId = "bk_agent1",
            currentPairedBackendLabel = "Agent 1",
            currentPairingState = PairingState.PAIRED,
            currentConnectionState = ConnectionState.PAIRED,
            currentMessages = activeAgent1Messages,
            currentIsLoadingHistory = false,
            currentHasMoreHistory = true,
            currentLoadedHistoryKeys = emptySet(),
        )

        assertEquals(existingAgent2State, persistedState)
    }

    @Test
    fun startupHistoryPreloadOnlyTargetsPairedProfilesWithBackendIds() {
        val candidates = startupHistoryPreloadCandidates(
            profiles = listOf(
                profiles[0].copy(id = "paired-openclaw", isPaired = true, backendId = "bk_openclaw"),
                profiles[1].copy(id = "unpaired-hermes", isPaired = false, backendId = "bk_hermes"),
                profiles[1].copy(id = "blank-backend", isPaired = true, backendId = ""),
            ),
            requestedProfileIds = emptySet(),
        )

        assertEquals(listOf("paired-openclaw"), candidates.map { it.id })
    }

    @Test
    fun startupHistoryPreloadSkipsAlreadyRequestedProfiles() {
        val candidates = startupHistoryPreloadCandidates(
            profiles = listOf(
                profiles[0].copy(id = "paired-openclaw", isPaired = true, backendId = "bk_openclaw"),
                profiles[1].copy(id = "paired-hermes", isPaired = true, backendId = "bk_hermes"),
            ),
            requestedProfileIds = setOf("paired-openclaw"),
        )

        assertEquals(listOf("paired-hermes"), candidates.map { it.id })
    }
}
