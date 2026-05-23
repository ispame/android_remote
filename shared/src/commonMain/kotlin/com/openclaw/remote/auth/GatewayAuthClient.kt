package com.openclaw.remote.auth

import io.ktor.client.HttpClient
import io.ktor.client.plugins.contentnegotiation.ContentNegotiation
import io.ktor.client.request.get
import io.ktor.client.request.header
import io.ktor.client.request.post
import io.ktor.client.request.setBody
import io.ktor.client.statement.HttpResponse
import io.ktor.client.statement.bodyAsText
import io.ktor.http.ContentType
import io.ktor.http.HttpHeaders
import io.ktor.http.contentType
import io.ktor.serialization.kotlinx.json.json
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put

data class SmsRequestResult(
    val requestId: String,
    val retryAfterSeconds: Int,
)

data class AuthSessionResult(
    val accountId: String,
    val accessToken: String,
    val refreshToken: String,
    val accessExpiresAt: String,
    val refreshExpiresAt: String,
)

data class AuthMeResult(
    val accountId: String,
    val phoneNumberMasked: String,
    val activeTerminalLabel: String?,
    val activeTerminalConnectedAt: String?,
    val pairedBackendsCount: Int,
)

class GatewayAuthClient(
    private val client: HttpClient = HttpClient {
        install(ContentNegotiation) {
            json(Json { ignoreUnknownKeys = true })
        }
    }
) {
    suspend fun requestSms(
        gatewayUrl: String,
        phoneNumber: String,
        purpose: String = "login",
    ): SmsRequestResult {
        val response = client.post("${requireAuthBaseUrl(gatewayUrl)}/api/v2/auth/sms/request") {
            contentType(ContentType.Application.Json)
            setBody(
                buildJsonObject {
                    put("phone_number", phoneNumber.trim())
                    put("purpose", purpose)
                }.toString()
            )
        }
        val body = requireJson(response)
        return SmsRequestResult(
            requestId = body.string("request_id"),
            retryAfterSeconds = body.int("retry_after_seconds"),
        )
    }

    suspend fun verifySms(
        gatewayUrl: String,
        phoneNumber: String,
        code: String,
        terminalLabel: String,
        platform: String = "android",
    ): AuthSessionResult {
        val response = client.post("${requireAuthBaseUrl(gatewayUrl)}/api/v2/auth/sms/verify") {
            contentType(ContentType.Application.Json)
            setBody(
                buildJsonObject {
                    put("phone_number", phoneNumber.trim())
                    put("code", code.trim())
                    put("terminal_label", terminalLabel.trim())
                    put("platform", platform)
                }.toString()
            )
        }
        return parseAuthSession(response)
    }

    suspend fun registerPassword(
        gatewayUrl: String,
        phoneNumber: String,
        code: String,
        password: String,
        terminalLabel: String,
        platform: String = "android",
    ): AuthSessionResult {
        val response = client.post("${requireAuthBaseUrl(gatewayUrl)}/api/v2/auth/password/register") {
            contentType(ContentType.Application.Json)
            setBody(
                buildJsonObject {
                    put("phone_number", phoneNumber.trim())
                    put("code", code.trim())
                    put("password", password)
                    put("terminal_label", terminalLabel.trim())
                    put("platform", platform)
                }.toString()
            )
        }
        return parseAuthSession(response)
    }

    suspend fun loginPassword(
        gatewayUrl: String,
        phoneNumber: String,
        password: String,
        terminalLabel: String,
        platform: String = "android",
    ): AuthSessionResult {
        val response = client.post("${requireAuthBaseUrl(gatewayUrl)}/api/v2/auth/password/login") {
            contentType(ContentType.Application.Json)
            setBody(
                buildJsonObject {
                    put("phone_number", phoneNumber.trim())
                    put("password", password)
                    put("terminal_label", terminalLabel.trim())
                    put("platform", platform)
                }.toString()
            )
        }
        return parseAuthSession(response)
    }

    suspend fun requestPasswordReset(
        gatewayUrl: String,
        phoneNumber: String,
    ): SmsRequestResult = requestSms(
        gatewayUrl = gatewayUrl,
        phoneNumber = phoneNumber,
        purpose = "password_reset",
    )

    suspend fun resetPassword(
        gatewayUrl: String,
        phoneNumber: String,
        code: String,
        password: String,
    ): AuthSessionResult {
        val response = client.post("${requireAuthBaseUrl(gatewayUrl)}/api/v2/auth/password/forgot/reset") {
            contentType(ContentType.Application.Json)
            setBody(
                buildJsonObject {
                    put("phone_number", phoneNumber.trim())
                    put("code", code.trim())
                    put("password", password)
                }.toString()
            )
        }
        return parseAuthSession(response)
    }

    suspend fun changePassword(
        gatewayUrl: String,
        accessToken: String,
        currentPassword: String,
        newPassword: String,
    ): AuthSessionResult {
        val response = client.post("${requireAuthBaseUrl(gatewayUrl)}/api/v2/auth/password/change") {
            header(HttpHeaders.Authorization, "Bearer ${accessToken.trim()}")
            contentType(ContentType.Application.Json)
            setBody(
                buildJsonObject {
                    put("current_password", currentPassword)
                    put("new_password", newPassword)
                }.toString()
            )
        }
        return parseAuthSession(response)
    }

    suspend fun refresh(
        gatewayUrl: String,
        refreshToken: String,
    ): AuthSessionResult {
        val response = client.post("${requireAuthBaseUrl(gatewayUrl)}/api/v2/auth/refresh") {
            contentType(ContentType.Application.Json)
            setBody(
                buildJsonObject {
                    put("refresh_token", refreshToken.trim())
                }.toString()
            )
        }
        return parseAuthSession(response)
    }

    suspend fun logout(
        gatewayUrl: String,
        refreshToken: String,
    ) {
        val response = client.post("${requireAuthBaseUrl(gatewayUrl)}/api/v2/auth/logout") {
            contentType(ContentType.Application.Json)
            setBody(
                buildJsonObject {
                    put("refresh_token", refreshToken.trim())
                }.toString()
            )
        }
        if (response.status.value !in 200..299) {
            val rawBody = response.bodyAsText()
            throw gatewayAuthError(response, rawBody)
        }
    }

    suspend fun me(
        gatewayUrl: String,
        accessToken: String,
    ): AuthMeResult {
        val response = client.get("${requireAuthBaseUrl(gatewayUrl)}/api/v2/auth/me") {
            header(HttpHeaders.Authorization, "Bearer ${accessToken.trim()}")
        }
        val body = requireJson(response)
        val activeTerminal = body["active_terminal"] as? JsonObject
        return AuthMeResult(
            accountId = body.string("account_id"),
            phoneNumberMasked = body.string("phone_number_masked"),
            activeTerminalLabel = activeTerminal?.stringOrNull("terminal_label"),
            activeTerminalConnectedAt = activeTerminal?.stringOrNull("connected_at"),
            pairedBackendsCount = body.int("paired_backends_count"),
        )
    }

    fun close() {
        client.close()
    }

    private suspend fun parseAuthSession(response: HttpResponse): AuthSessionResult {
        val body = requireJson(response)
        return AuthSessionResult(
            accountId = body.string("account_id"),
            accessToken = body.string("access_token"),
            refreshToken = body.string("refresh_token"),
            accessExpiresAt = body.string("access_expires_at"),
            refreshExpiresAt = body.string("refresh_expires_at"),
        )
    }

    private suspend fun requireJson(response: HttpResponse): JsonObject {
        val text = response.bodyAsText()
        val json = runCatching { Json.parseToJsonElement(text) as? JsonObject }.getOrNull()
        if (response.status.value !in 200..299) {
            throw gatewayAuthError(response, text, json)
        }
        return json ?: throw IllegalStateException("Invalid JSON response")
    }
}

internal fun authBaseUrlFromGatewayUrl(gatewayUrl: String): String? {
    val trimmed = gatewayUrl.trim().removeSuffix("/")
    if (trimmed.isEmpty()) return null
    val normalizedScheme = when {
        trimmed.startsWith("wss://", ignoreCase = true) -> "https://${trimmed.removePrefix("wss://")}"
        trimmed.startsWith("ws://", ignoreCase = true) -> "http://${trimmed.removePrefix("ws://")}"
        trimmed.startsWith("https://", ignoreCase = true) -> trimmed
        trimmed.startsWith("http://", ignoreCase = true) -> trimmed
        else -> return null
    }
    return normalizedScheme.removeSuffix("/ws").removeSuffix("/")
}

private fun requireAuthBaseUrl(gatewayUrl: String): String =
    authBaseUrlFromGatewayUrl(gatewayUrl) ?: throw IllegalArgumentException("Invalid gateway URL")

private fun gatewayAuthError(
    response: HttpResponse,
    rawBody: String,
    body: JsonObject? = runCatching { Json.parseToJsonElement(rawBody) as? JsonObject }.getOrNull(),
): IllegalStateException {
    val code = body?.stringOrNull("error") ?: body?.stringOrNull("code")
    val message = body?.stringOrNull("message")
    val statusPrefix = "HTTP ${response.status.value}"
    return IllegalStateException(
        listOfNotNull(statusPrefix, code, message)
            .joinToString(": ")
    )
}

private fun JsonObject.string(name: String): String =
    this[name]?.jsonPrimitive?.contentOrNull?.trim().orEmpty()

private fun JsonObject.stringOrNull(name: String): String? =
    this[name]?.jsonPrimitive?.contentOrNull?.trim()?.takeIf { it.isNotEmpty() }

private fun JsonObject.int(name: String): Int =
    this[name]?.jsonPrimitive?.contentOrNull?.toIntOrNull() ?: 0
