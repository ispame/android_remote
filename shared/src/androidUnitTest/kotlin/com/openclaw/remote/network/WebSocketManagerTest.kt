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
}
