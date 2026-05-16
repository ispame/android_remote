package com.openclaw.remote.network

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
}
