package com.openclaw.remote.ui.screen

import com.openclaw.remote.auth.AuthSessionResult
import com.openclaw.remote.data.AgentProfile
import org.junit.Assert.assertEquals
import org.junit.Test

class AuthFlowStateTest {
    @Test
    fun authModeLabelsMatchIosLoginRegisterForgotFlow() {
        assertEquals(
            listOf("登录", "注册", "找回密码"),
            AuthModeSpec.entries.map { it.label },
        )
        assertEquals(
            listOf("密码", "验证码"),
            AuthLoginModeSpec.entries.map { it.label },
        )
    }

    @Test
    fun initialAuthStateRestoresIosDefaultsFromConfig() {
        val state = initialAuthUiState(
            gatewayUrl = "",
            deviceLabel = "",
            lastLoginMode = "验证码",
            lastPhoneNumber = "+8613800138000",
        )

        assertEquals(AgentProfile.DEFAULT_GATEWAY_URL, state.gatewayUrl)
        assertEquals("我的设备", state.terminalLabel)
        assertEquals(AuthLoginModeSpec.SMS, state.loginMode)
        assertEquals("+8613800138000", state.phoneNumber)
    }

    @Test
    fun authSuccessPayloadCarriesIosSessionMetadata() {
        val payload = buildAuthSuccessPayload(
            session = AuthSessionResult(
                accountId = "acct-1",
                accessToken = "access-1",
                refreshToken = "refresh-1",
                accessExpiresAt = "2026-06-12T12:00:00Z",
                refreshExpiresAt = "2026-07-12T12:00:00Z",
            ),
            gatewayUrl = "",
            terminalLabel = "",
            loginMode = AuthLoginModeSpec.PASSWORD,
            phoneNumber = "  +8613800138000  ",
        )

        assertEquals("acct-1", payload.session.accountId)
        assertEquals(AgentProfile.DEFAULT_GATEWAY_URL, payload.gatewayUrl)
        assertEquals("我的设备", payload.terminalLabel)
        assertEquals("密码", payload.loginMode)
        assertEquals("+8613800138000", payload.phoneNumber)
    }
}
