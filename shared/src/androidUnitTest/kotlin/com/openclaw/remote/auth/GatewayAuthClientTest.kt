package com.openclaw.remote.auth

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class GatewayAuthClientTest {
    @Test
    fun convertsSecureGatewayWebSocketUrlToHttpsBase() {
        assertEquals(
            "https://boson-tech.top",
            authBaseUrlFromGatewayUrl("wss://boson-tech.top/ws"),
        )
    }

    @Test
    fun convertsLocalWebSocketUrlToHttpBase() {
        assertEquals(
            "http://192.168.1.14:8765",
            authBaseUrlFromGatewayUrl("ws://192.168.1.14:8765/ws"),
        )
    }

    @Test
    fun preservesExistingHttpSchemeAndStripsTrailingWsSegment() {
        assertEquals(
            "https://gateway.example.com/router",
            authBaseUrlFromGatewayUrl("https://gateway.example.com/router/ws"),
        )
    }

    @Test
    fun rejectsBlankOrUnsupportedGatewayUrl() {
        assertNull(authBaseUrlFromGatewayUrl(" "))
        assertNull(authBaseUrlFromGatewayUrl("gateway.example.com/ws"))
    }
}
