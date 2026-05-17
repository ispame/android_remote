package com.openclaw.remote.ui.screen

import com.openclaw.remote.data.AgentPlatform
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class QRParseTest {
    @Test
    fun parsesBackendIdUrlWithPlatformAndLabel() {
        var parsed: QRParseResult? = null

        parseQRPack(
            "openclaw://connect?gateway=wss%3A%2F%2Fboson-tech.top%2Fws&backendId=bk_openclaw&token=t1&platform=hermes&label=Hermes%20Relay"
        ) { parsed = it }

        val success = parsed as QRParseResult.Success
        assertEquals("wss://boson-tech.top/ws", success.gatewayUrl)
        assertEquals("bk_openclaw", success.backendId)
        assertEquals("t1", success.token)
        assertEquals(AgentPlatform.HERMES, success.platform)
        assertEquals("Hermes Relay", success.label)
    }

    @Test
    fun parsesLegacyAgentIdUrlAsOpenClaw() {
        var parsed: QRParseResult? = null

        parseQRPack("openclaw://connect?gateway=ws%3A%2F%2Flocalhost%3A8765&agentId=legacy-agent") {
            parsed = it
        }

        val success = parsed as QRParseResult.Success
        assertEquals("ws://localhost:8765", success.gatewayUrl)
        assertEquals("legacy-agent", success.backendId)
        assertEquals(AgentPlatform.OPENCLAW, success.platform)
        assertEquals(null, success.label)
    }

    @Test
    fun parsesJsonBackendLabel() {
        var parsed: QRParseResult? = null

        parseQRPack(
            """
            {
              "gateway": "wss://boson-tech.top/ws",
              "backendId": "bk_hermes",
              "token": "token-json",
              "platform": "hermes",
              "backendLabel": "Hermes BosonRelay"
            }
            """.trimIndent()
        ) { parsed = it }

        val success = parsed as QRParseResult.Success
        assertEquals("bk_hermes", success.backendId)
        assertEquals("token-json", success.token)
        assertEquals(AgentPlatform.HERMES, success.platform)
        assertEquals("Hermes BosonRelay", success.label)
    }

    @Test
    fun rejectsMissingBackendId() {
        var parsed: QRParseResult? = null

        parseQRPack("openclaw://connect?gateway=wss%3A%2F%2Fboson-tech.top%2Fws") {
            parsed = it
        }

        val error = parsed as QRParseResult.Error
        assertTrue(error.message.contains("backendId"))
    }
}
