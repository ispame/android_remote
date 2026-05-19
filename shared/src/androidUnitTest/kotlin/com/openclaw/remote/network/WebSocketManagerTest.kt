package com.openclaw.remote.network

import com.openclaw.remote.domain.ConnectionState
import com.openclaw.remote.domain.PairingState
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class WebSocketManagerTest {
    @Test
    fun autoPairUsesConfiguredBackendWhenRuntimeBackendIsMissing() {
        assertEquals(
            "bk_openclaw",
            resolveAutoPairBackendId(
                configuredBackendId = "bk_openclaw",
                registeredBackendId = null,
            ),
        )
    }

    @Test
    fun autoPairPrefersRuntimeBackendAfterSuccessfulPairing() {
        assertEquals(
            "bk_runtime",
            resolveAutoPairBackendId(
                configuredBackendId = "bk_config",
                registeredBackendId = "bk_runtime",
            ),
        )
    }

    @Test
    fun autoPairIgnoresBlankConfiguredBackend() {
        assertNull(
            resolveAutoPairBackendId(
                configuredBackendId = " ",
                registeredBackendId = null,
            ),
        )
    }

    @Test
    fun transientDisconnectKeepsReconnectablePairedState() {
        assertEquals(
            ConnectionState.CONNECTING,
            transientDisconnectConnectionState(
                pairingState = PairingState.PAIRED,
                hasRestorablePairing = true,
            ),
        )
    }

    @Test
    fun transientDisconnectRequiresFreshPairResponseBeforePairedAgain() {
        assertEquals(
            PairingState.PENDING,
            transientDisconnectPairingState(
                pairingState = PairingState.PAIRED,
                hasRestorablePairing = true,
            ),
        )
    }

    @Test
    fun registeredDuringAutoRestoreDoesNotLookPairedUntilPairResponse() {
        assertEquals(
            ConnectionState.REGISTERED,
            registeredConnectionState(pairingState = PairingState.PENDING),
        )
        assertEquals(
            ConnectionState.PAIRED,
            pairedConnectionState(),
        )
    }

    @Test
    fun reconnectingPairingCannotSendUserPayloads() {
        assertEquals(false, canSendUserPayload(PairingState.PENDING, registeredBackendId = "bk_openclaw"))
        assertEquals(false, canSendUserPayload(PairingState.PAIRED, registeredBackendId = null))
        assertEquals(true, canSendUserPayload(PairingState.PAIRED, registeredBackendId = "bk_openclaw"))
    }

    @Test
    fun duplicatePairRequestsAreSkippedOnlyWhilePending() {
        assertEquals(
            true,
            shouldSkipPairRequest(
                connectionState = ConnectionState.REGISTERED,
                pairingState = PairingState.PENDING,
                registeredBackendId = null,
                pendingPairBackendId = "bk_openclaw",
                requestedBackendId = "bk_openclaw",
            ),
        )
        assertEquals(
            false,
            shouldSkipPairRequest(
                connectionState = ConnectionState.PAIRED,
                pairingState = PairingState.PAIRED,
                registeredBackendId = "bk_openclaw",
                pendingPairBackendId = null,
                requestedBackendId = "bk_openclaw",
            ),
        )
        assertEquals(
            false,
            shouldSkipPairRequest(
                connectionState = ConnectionState.REGISTERED,
                pairingState = PairingState.PENDING,
                registeredBackendId = null,
                pendingPairBackendId = "bk_openclaw",
                requestedBackendId = "bk_hermes",
            ),
        )
    }

    @Test
    fun routerErrorWhilePairingClearsPendingPairingState() {
        val recovery = recoverPairingAfterRouterError(
            pairingState = PairingState.PENDING,
            pendingPairBackendId = "main",
            code = "TARGET_NOT_FOUND",
            message = "Backend not found: main",
        )

        assertEquals(PairingState.UNPAIRED, recovery.pairingState)
        assertNull(recovery.pendingPairBackendId)
    }

    @Test
    fun backendUnavailableErrorClearsStalePairedState() {
        val recovery = recoverPairingAfterRouterError(
            pairingState = PairingState.PAIRED,
            pendingPairBackendId = null,
            code = "CLIENT_NOT_FOUND",
            message = "Backend offline",
        )

        assertEquals(PairingState.UNPAIRED, recovery.pairingState)
        assertNull(recovery.pendingPairBackendId)
    }

    @Test
    fun staleSocketGenerationFramesAreIgnored() {
        assertEquals(
            true,
            shouldProcessIncomingFrame(
                intentionalDisconnect = false,
                frameGeneration = 7,
                currentGeneration = 7,
            ),
        )
        assertEquals(
            false,
            shouldProcessIncomingFrame(
                intentionalDisconnect = false,
                frameGeneration = 6,
                currentGeneration = 7,
            ),
        )
        assertEquals(
            false,
            shouldProcessIncomingFrame(
                intentionalDisconnect = true,
                frameGeneration = 7,
                currentGeneration = 7,
            ),
        )
    }

    @Test
    fun repeatedConnectDoesNotCancelActiveOrScheduledReconnectWork() {
        assertEquals(
            true,
            shouldIgnoreConnectRequest(
                hasActiveSession = false,
                connectAttemptInFlight = false,
                reconnectScheduled = true,
                intentionalDisconnect = false,
            ),
        )
        assertEquals(
            true,
            shouldIgnoreConnectRequest(
                hasActiveSession = true,
                connectAttemptInFlight = false,
                reconnectScheduled = false,
                intentionalDisconnect = false,
            ),
        )
        assertEquals(
            false,
            shouldIgnoreConnectRequest(
                hasActiveSession = false,
                connectAttemptInFlight = false,
                reconnectScheduled = false,
                intentionalDisconnect = true,
            ),
        )
    }
}
