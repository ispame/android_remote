package com.openclaw.remote.network

import java.text.SimpleDateFormat
import java.util.Locale
import java.util.TimeZone

internal enum class AuthRecoveryAction {
    NONE,
    REFRESH_SESSION,
    REQUIRE_LOGIN,
}

private const val ACCESS_REFRESH_SKEW_MS = 2 * 60 * 1000L

internal fun authRecoveryActionForWsError(code: String): AuthRecoveryAction {
    return when (code.trim().uppercase()) {
        "INVALID_ACCESS_TOKEN",
        "EXPIRED_ACCESS_TOKEN",
        "ACCESS_TOKEN_EXPIRED" -> AuthRecoveryAction.REFRESH_SESSION
        "REFRESH_TOKEN_EXPIRED",
        "INVALID_REFRESH_TOKEN",
        "ACCESS_TOKEN_REVOKED" -> AuthRecoveryAction.REQUIRE_LOGIN
        else -> AuthRecoveryAction.NONE
    }
}

internal fun isAccessTokenRefreshableError(code: String): Boolean =
    authRecoveryActionForWsError(code) == AuthRecoveryAction.REFRESH_SESSION

fun refreshFailureRequiresLogin(message: String): Boolean {
    val normalized = message.uppercase()
    return "REFRESH_TOKEN_EXPIRED" in normalized ||
        "INVALID_REFRESH_TOKEN" in normalized ||
        "ACCESS_TOKEN_REVOKED" in normalized
}

fun shouldRefreshAccessToken(
    accessExpiresAt: String,
    nowMillis: Long = System.currentTimeMillis(),
    skewMillis: Long = ACCESS_REFRESH_SKEW_MS,
): Boolean {
    val expiresAtMillis = parseAuthIsoTimestampMillis(accessExpiresAt) ?: return true
    return expiresAtMillis - nowMillis <= skewMillis
}

fun accessTokenRefreshDelayMillis(
    accessExpiresAt: String,
    nowMillis: Long = System.currentTimeMillis(),
    skewMillis: Long = ACCESS_REFRESH_SKEW_MS,
): Long {
    val expiresAtMillis = parseAuthIsoTimestampMillis(accessExpiresAt) ?: return 0L
    return (expiresAtMillis - skewMillis - nowMillis).coerceAtLeast(0L)
}

private fun parseAuthIsoTimestampMillis(value: String): Long? {
    if (value.isBlank()) return null
    val patterns = listOf("yyyy-MM-dd'T'HH:mm:ss.SSSX", "yyyy-MM-dd'T'HH:mm:ssX")
    return patterns.firstNotNullOfOrNull { pattern ->
        runCatching {
            SimpleDateFormat(pattern, Locale.US).apply {
                timeZone = TimeZone.getTimeZone("UTC")
            }.parse(value)?.time
        }.getOrNull()
    }
}
