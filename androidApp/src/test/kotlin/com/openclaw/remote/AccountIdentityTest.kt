package com.openclaw.remote

import com.openclaw.remote.data.deriveBosonAccountId
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Test

class AccountIdentityTest {
    @Test
    fun sameGatewayBackendAndTokenProduceSameAccountIdAcrossDevices() {
        val first = deriveBosonAccountId(
            gatewayUrl = "WSS://boson-tech.top/ws",
            backendId = "bk_openclaw",
            token = "shared-token",
        )
        val second = deriveBosonAccountId(
            gatewayUrl = "wss://boson-tech.top/ws",
            backendId = "bk_openclaw",
            token = "shared-token",
        )

        assertEquals(first, second)
        assertEquals("acct_5b576040e860b0d4", first)
    }

    @Test
    fun differentBackendOrTokenProducesDifferentAccountId() {
        val base = deriveBosonAccountId("wss://boson-tech.top/ws", "bk_openclaw", "shared-token")

        assertNotEquals(base, deriveBosonAccountId("wss://boson-tech.top/ws", "bk_other", "shared-token"))
        assertNotEquals(base, deriveBosonAccountId("wss://boson-tech.top/ws", "bk_openclaw", "other-token"))
    }
}
