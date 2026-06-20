package com.openclaw.remote.ui.screen

import com.openclaw.remote.auth.AuthSessionResult
import com.openclaw.remote.data.AgentProfile

enum class AuthModeSpec(val label: String) {
    LOGIN("登录"),
    REGISTER("注册"),
    FORGOT("找回密码"),
}

enum class AuthLoginModeSpec(val label: String) {
    PASSWORD("密码"),
    SMS("验证码");

    companion object {
        fun fromLabel(value: String): AuthLoginModeSpec =
            entries.firstOrNull { it.label == value.trim() } ?: PASSWORD
    }
}

data class AuthUiState(
    val mode: AuthModeSpec,
    val loginMode: AuthLoginModeSpec,
    val gatewayUrl: String,
    val terminalLabel: String,
    val phoneNumber: String,
)

data class AuthSuccessPayload(
    val session: AuthSessionResult,
    val gatewayUrl: String,
    val terminalLabel: String,
    val loginMode: String,
    val phoneNumber: String,
)

fun initialAuthUiState(
    gatewayUrl: String,
    deviceLabel: String,
    lastLoginMode: String,
    lastPhoneNumber: String,
): AuthUiState =
    AuthUiState(
        mode = AuthModeSpec.LOGIN,
        loginMode = AuthLoginModeSpec.fromLabel(lastLoginMode),
        gatewayUrl = gatewayUrl.normalizedGatewayUrl(),
        terminalLabel = deviceLabel.normalizedTerminalLabel(),
        phoneNumber = lastPhoneNumber.trim(),
    )

fun buildAuthSuccessPayload(
    session: AuthSessionResult,
    gatewayUrl: String,
    terminalLabel: String,
    loginMode: AuthLoginModeSpec,
    phoneNumber: String,
): AuthSuccessPayload =
    AuthSuccessPayload(
        session = session,
        gatewayUrl = gatewayUrl.normalizedGatewayUrl(),
        terminalLabel = terminalLabel.normalizedTerminalLabel(),
        loginMode = loginMode.label,
        phoneNumber = phoneNumber.trim(),
    )

fun String.normalizedGatewayUrl(): String =
    AgentProfile.canonicalWebSocketGatewayUrl(this)

fun String.normalizedTerminalLabel(): String =
    trim().ifEmpty { "我的设备" }
