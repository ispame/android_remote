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
