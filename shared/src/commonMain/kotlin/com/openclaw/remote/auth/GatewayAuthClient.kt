package com.openclaw.remote.auth

import com.openclaw.remote.data.RecordingWorkflow
import com.openclaw.remote.data.parseRecordingWorkflow
import com.openclaw.remote.network.Base64
import io.ktor.client.call.body
import io.ktor.client.HttpClient
import io.ktor.client.plugins.contentnegotiation.ContentNegotiation
import io.ktor.client.request.get
import io.ktor.client.request.header
import io.ktor.client.request.post
import io.ktor.client.request.put
import io.ktor.client.request.setBody
import io.ktor.client.statement.HttpResponse
import io.ktor.client.statement.bodyAsText
import io.ktor.http.ContentType
import io.ktor.http.HttpHeaders
import io.ktor.http.contentType
import io.ktor.serialization.kotlinx.json.json
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
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
    val displayName: String?,
    val accountDisplayName: String,
    val phoneNumberMasked: String,
    val activeTerminalLabel: String?,
    val activeTerminalConnectedAt: String?,
    val pairedBackendsCount: Int,
)

data class AccountAgentProfileResult(
    val agentProfileId: String,
    val platform: String,
    val displayName: String,
    val gatewayUrl: String,
    val backendId: String,
    val backendLabel: String?,
    val isPaired: Boolean,
    val asrMode: String,
    val sortOrder: Int,
    val pinned: Boolean,
)

data class BillingProductResult(
    val productId: String,
    val kind: String,
    val title: String,
    val subtitle: String,
    val displayName: String,
    val amountCents: Int,
    val currency: String,
    val billingPeriod: String,
    val benefits: List<String>,
    val badge: String?,
    val sortOrder: Int,
    val availableProviders: List<String>,
)

data class BillingProductsResult(
    val walletProducts: List<BillingProductResult>,
    val plans: List<BillingProductResult>,
)

data class BillingWalletResult(
    val balanceCents: Int,
    val currency: String,
)

data class BillingSubscriptionResult(
    val subscriptionId: String,
    val productId: String,
    val status: String,
    val currentPeriodEnd: String,
)

data class BillingOrderResult(
    val orderId: String,
    val productId: String,
    val productKind: String,
    val provider: String,
    val status: String,
    val amountCents: Int,
    val currency: String,
    val expiresAt: String,
    val paymentUrl: String,
    val copyText: String,
    val qrImageUrl: String,
    val pollAfterMs: Int,
)

data class BillingUsageEventResult(
    val usageEventId: String,
    val usageType: String,
    val quantity: Int,
    val amountCents: Int,
    val backendId: String?,
    val createdAt: String,
)

data class BillingSummaryResult(
    val accountId: String,
    val wallet: BillingWalletResult,
    val currentSubscription: BillingSubscriptionResult?,
    val products: BillingProductsResult,
    val recentOrders: List<BillingOrderResult>,
    val recentUsageEvents: List<BillingUsageEventResult>,
)

data class LongRecordingAsrJobResult(
    val jobId: String,
    val status: String,
    val progress: Double,
    val uploadUrl: String?,
    val pollAfterMs: Int,
    val text: String?,
    val error: String?,
)

class GatewayAuthClient(
    private val client: HttpClient = HttpClient {
        install(ContentNegotiation) {
            json(Json { ignoreUnknownKeys = true })
        }
    }
) {
    suspend fun aiChat(
        gatewayUrl: String,
        accessToken: String,
        choice: com.openclaw.remote.data.AiServiceChoice,
        messages: List<AiChatMessage>,
    ): String {
        val response = client.post("${requireAuthBaseUrl(gatewayUrl)}/api/v2/ai/chat") {
            header(HttpHeaders.Authorization, "Bearer ${accessToken.trim()}")
            contentType(ContentType.Application.Json)
            setBody(
                buildJsonObject {
                    put("mode", choice.mode)
                    put("profile_id", choice.profileId)
                    put("provider_id", choice.providerId)
                    put("model", choice.model)
                    put("messages", buildJsonArray {
                        messages.forEach { message ->
                            add(
                                buildJsonObject {
                                    put("role", message.role)
                                    put("content", message.content)
                                }
                            )
                        }
                    })
                }.toString()
            )
        }
        val obj = requireJson(response)
        return obj.string("text").ifBlank {
            obj["message"]?.jsonObject?.get("content")?.jsonPrimitive?.contentOrNull
                ?: obj["choices"]?.jsonArray?.firstOrNull()
                    ?.jsonObject?.get("message")?.jsonObject?.get("content")
                    ?.jsonPrimitive?.contentOrNull
                ?: obj.string("content")
        }
    }

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
        return parseAuthMe(requireJson(response))
    }

    suspend fun updateAccountDisplayName(
        gatewayUrl: String,
        accessToken: String,
        displayName: String,
    ): AuthMeResult {
        val response = client.put("${requireAuthBaseUrl(gatewayUrl)}/api/v2/auth/me") {
            header(HttpHeaders.Authorization, "Bearer ${accessToken.trim()}")
            contentType(ContentType.Application.Json)
            setBody(
                buildJsonObject {
                    put("display_name", displayName.trim())
                }.toString()
            )
        }
        return parseAuthMe(requireJson(response))
    }

    suspend fun listAccountAgents(
        gatewayUrl: String,
        accessToken: String,
    ): List<AccountAgentProfileResult> {
        val response = client.get("${requireAuthBaseUrl(gatewayUrl)}/api/v2/account/agents") {
            header(HttpHeaders.Authorization, "Bearer ${accessToken.trim()}")
        }
        val body = requireJson(response)
        val agents = body["agents"] as? JsonArray ?: return emptyList()
        return agents.mapNotNull { element ->
            val agent = element as? JsonObject ?: return@mapNotNull null
            AccountAgentProfileResult(
                agentProfileId = agent.string("agent_profile_id"),
                platform = agent.string("platform").ifBlank { "openclaw" },
                displayName = agent.string("display_name").ifBlank { "Agent" },
                gatewayUrl = agent.string("gateway_url"),
                backendId = agent.string("backend_id"),
                backendLabel = agent.stringOrNull("backend_label"),
                isPaired = agent.boolean("is_paired"),
                asrMode = agent.string("asr_mode").ifBlank { "router" },
                sortOrder = agent.int("sort_order"),
                pinned = agent.boolean("pinned"),
            )
        }
    }

    suspend fun upsertAccountAgent(
        gatewayUrl: String,
        accessToken: String,
        profile: AccountAgentProfileResult,
    ): AccountAgentProfileResult {
        val response = client.put("${requireAuthBaseUrl(gatewayUrl)}/api/v2/account/agents") {
            header(HttpHeaders.Authorization, "Bearer ${accessToken.trim()}")
            contentType(ContentType.Application.Json)
            setBody(
                buildJsonObject {
                    put("agent_profile_id", profile.agentProfileId)
                    put("platform", profile.platform)
                    put("display_name", profile.displayName)
                    put("gateway_url", profile.gatewayUrl)
                    put("backend_id", profile.backendId)
                    profile.backendLabel?.let { put("backend_label", it) }
                    put("asr_mode", profile.asrMode)
                    put("sort_order", profile.sortOrder)
                    put("pinned", profile.pinned)
                }.toString()
            )
        }
        val body = requireJson(response)
        val agent = body["agent"] as? JsonObject ?: throw IllegalStateException("Invalid account agent response")
        return AccountAgentProfileResult(
            agentProfileId = agent.string("agent_profile_id"),
            platform = agent.string("platform").ifBlank { "openclaw" },
            displayName = agent.string("display_name").ifBlank { "Agent" },
            gatewayUrl = agent.string("gateway_url"),
            backendId = agent.string("backend_id"),
            backendLabel = agent.stringOrNull("backend_label"),
            isPaired = agent.boolean("is_paired"),
            asrMode = agent.string("asr_mode").ifBlank { "router" },
            sortOrder = agent.int("sort_order"),
            pinned = agent.boolean("pinned"),
        )
    }

    suspend fun billingSummary(
        gatewayUrl: String,
        accessToken: String,
    ): BillingSummaryResult {
        val response = client.get("${requireAuthBaseUrl(gatewayUrl)}/api/v2/billing/summary") {
            header(HttpHeaders.Authorization, "Bearer ${accessToken.trim()}")
        }
        return parseBillingSummary(requireJson(response))
    }

    suspend fun billingProducts(
        gatewayUrl: String,
        accessToken: String,
    ): BillingProductsResult {
        val response = client.get("${requireAuthBaseUrl(gatewayUrl)}/api/v2/billing/products") {
            header(HttpHeaders.Authorization, "Bearer ${accessToken.trim()}")
        }
        return parseBillingProducts(requireJson(response))
    }

    suspend fun createBillingOrder(
        gatewayUrl: String,
        accessToken: String,
        productId: String,
        provider: String = "manual_qr",
    ): BillingOrderResult {
        val response = client.post("${requireAuthBaseUrl(gatewayUrl)}/api/v2/billing/orders") {
            header(HttpHeaders.Authorization, "Bearer ${accessToken.trim()}")
            contentType(ContentType.Application.Json)
            setBody(
                buildJsonObject {
                    put("product_id", productId)
                    put("provider", provider)
                }.toString()
            )
        }
        return parseBillingOrder(requireJson(response))
    }

    suspend fun billingOrder(
        gatewayUrl: String,
        accessToken: String,
        orderId: String,
    ): BillingOrderResult {
        val response = client.get("${requireAuthBaseUrl(gatewayUrl)}/api/v2/billing/orders/${orderId.trim()}") {
            header(HttpHeaders.Authorization, "Bearer ${accessToken.trim()}")
        }
        return parseBillingOrder(requireJson(response))
    }

    suspend fun billingOrderQrBytes(
        gatewayUrl: String,
        accessToken: String,
        orderId: String,
    ): ByteArray {
        val response = client.get("${requireAuthBaseUrl(gatewayUrl)}/api/v2/billing/orders/${orderId.trim()}/qr.png") {
            header(HttpHeaders.Authorization, "Bearer ${accessToken.trim()}")
        }
        if (response.status.value !in 200..299) {
            val rawBody = response.bodyAsText()
            throw gatewayAuthError(response, rawBody)
        }
        return response.body()
    }

    suspend fun createLongRecordingAsrJob(
        gatewayUrl: String,
        accessToken: String,
        recordingId: String,
        filename: String,
        mimeType: String,
        sizeBytes: Long,
        recordingType: String,
        asrProfileId: String?,
        agentPrompt: String? = null,
    ): LongRecordingAsrJobResult {
        val response = client.post("${requireAuthBaseUrl(gatewayUrl)}/api/recordings/asr-jobs") {
            header(HttpHeaders.Authorization, "Bearer ${accessToken.trim()}")
            contentType(ContentType.Application.Json)
            setBody(
                buildLongRecordingAsrJobPayload(
                    recordingId = recordingId,
                    filename = filename,
                    mimeType = mimeType,
                    sizeBytes = sizeBytes,
                    recordingType = recordingType,
                    asrProfileId = asrProfileId,
                    agentPrompt = agentPrompt,
                ).toString()
            )
        }
        return parseLongRecordingAsrJob(requireJson(response))
    }

    suspend fun uploadLongRecordingAsrChunk(
        gatewayUrl: String,
        accessToken: String,
        jobId: String,
        chunkIndex: Int,
        totalChunks: Int,
        bytes: ByteArray,
    ): LongRecordingAsrJobResult {
        val response = client.post("${requireAuthBaseUrl(gatewayUrl)}/api/recordings/asr-jobs/${jobId.trim()}/chunks") {
            header(HttpHeaders.Authorization, "Bearer ${accessToken.trim()}")
            contentType(ContentType.Application.Json)
            setBody(
                buildJsonObject {
                    put("chunk_index", chunkIndex)
                    put("total_chunks", totalChunks)
                    put("content_base64", Base64.encode(bytes))
                }.toString()
            )
        }
        return parseLongRecordingAsrJob(requireJson(response))
    }

    suspend fun completeLongRecordingAsrJob(
        gatewayUrl: String,
        accessToken: String,
        jobId: String,
    ): LongRecordingAsrJobResult {
        val response = client.post("${requireAuthBaseUrl(gatewayUrl)}/api/recordings/asr-jobs/${jobId.trim()}/complete") {
            header(HttpHeaders.Authorization, "Bearer ${accessToken.trim()}")
            contentType(ContentType.Application.Json)
            setBody(buildJsonObject {}.toString())
        }
        return parseLongRecordingAsrJob(requireJson(response))
    }

    suspend fun longRecordingAsrJobStatus(
        gatewayUrl: String,
        accessToken: String,
        jobId: String,
    ): LongRecordingAsrJobResult {
        val response = client.get("${requireAuthBaseUrl(gatewayUrl)}/api/recordings/asr-jobs/${jobId.trim()}") {
            header(HttpHeaders.Authorization, "Bearer ${accessToken.trim()}")
        }
        return parseLongRecordingAsrJob(requireJson(response))
    }

    suspend fun recordingWorkflowTaskAction(
        gatewayUrl: String,
        accessToken: String,
        workflowId: String,
        taskId: String,
        action: String,
        expectedRevision: Int,
        idempotencyKey: String,
    ): RecordingWorkflow {
        val response = client.post(
            "${requireAuthBaseUrl(gatewayUrl)}/api/recording-workflows/" +
                "${workflowId.trim()}/tasks/${taskId.trim()}/${action.trim()}"
        ) {
            header(HttpHeaders.Authorization, "Bearer ${accessToken.trim()}")
            contentType(ContentType.Application.Json)
            setBody(
                buildJsonObject {
                    put("expected_revision", expectedRevision)
                    put("idempotency_key", idempotencyKey)
                }.toString()
            )
        }
        return requireJson(response).recordingWorkflow()
    }

    suspend fun recordingWorkflowAction(
        gatewayUrl: String,
        accessToken: String,
        workflowId: String,
        action: String,
        expectedRevision: Int,
        idempotencyKey: String,
    ): RecordingWorkflow {
        val response = client.post(
            "${requireAuthBaseUrl(gatewayUrl)}/api/recording-workflows/" +
                "${workflowId.trim()}/${action.trim()}"
        ) {
            header(HttpHeaders.Authorization, "Bearer ${accessToken.trim()}")
            contentType(ContentType.Application.Json)
            setBody(
                buildJsonObject {
                    put("expected_revision", expectedRevision)
                    put("idempotency_key", idempotencyKey)
                }.toString()
            )
        }
        return requireJson(response).recordingWorkflow()
    }

    suspend fun updateRecordingWorkflowTask(
        gatewayUrl: String,
        accessToken: String,
        workflowId: String,
        taskId: String,
        expectedRevision: Int,
        idempotencyKey: String,
        prompt: String,
        executorHint: String?,
        modelHint: String?,
        sourceConstraints: List<String>,
        maxAttempts: Int,
    ): RecordingWorkflow {
        val response = client.put(
            "${requireAuthBaseUrl(gatewayUrl)}/api/recording-workflows/" +
                "${workflowId.trim()}/tasks/${taskId.trim()}"
        ) {
            header(HttpHeaders.Authorization, "Bearer ${accessToken.trim()}")
            contentType(ContentType.Application.Json)
            setBody(
                buildJsonObject {
                    put("expected_revision", expectedRevision)
                    put("idempotency_key", idempotencyKey)
                    put("prompt", prompt)
                    put("executor_hint", JsonPrimitive(executorHint))
                    put("model_hint", JsonPrimitive(modelHint))
                    put("source_constraints", JsonArray(sourceConstraints.map(::JsonPrimitive)))
                    put("max_attempts", maxAttempts)
                }.toString()
            )
        }
        return requireJson(response).recordingWorkflow()
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

private fun JsonObject.recordingWorkflow(): RecordingWorkflow {
    val workflow = this["workflow"] as? JsonObject
        ?: throw IllegalStateException("Recording workflow response is missing workflow")
    return parseRecordingWorkflow(workflow)
}

internal fun parseAuthMe(body: JsonObject): AuthMeResult {
    val activeTerminal = body["active_terminal"] as? JsonObject
    val phoneMasked = body.string("phone_number_masked")
    return AuthMeResult(
        accountId = body.string("account_id"),
        displayName = body.stringOrNull("display_name"),
        accountDisplayName = body.string("account_display_name").ifBlank { phoneMasked },
        phoneNumberMasked = phoneMasked,
        activeTerminalLabel = activeTerminal?.stringOrNull("terminal_label"),
        activeTerminalConnectedAt = activeTerminal?.stringOrNull("connected_at"),
        pairedBackendsCount = body.int("paired_backends_count"),
    )
}

internal fun parseBillingSummary(body: JsonObject): BillingSummaryResult {
    val products = parseBillingProducts(body["products"] as? JsonObject ?: JsonObject(emptyMap()))
    val usage = body["usage"] as? JsonObject
    return BillingSummaryResult(
        accountId = body.string("account_id"),
        wallet = parseBillingWallet(body["wallet"] as? JsonObject ?: JsonObject(emptyMap())),
        currentSubscription = (body["current_subscription"] as? JsonObject)?.let(::parseBillingSubscription),
        products = products,
        recentOrders = body.array("recent_orders").mapNotNull { (it as? JsonObject)?.let(::parseBillingOrder) },
        recentUsageEvents = usage?.array("recent_events")?.mapNotNull { (it as? JsonObject)?.let(::parseBillingUsageEvent) }.orEmpty(),
    )
}

internal fun parseBillingProducts(body: JsonObject): BillingProductsResult =
    BillingProductsResult(
        walletProducts = body.array("wallet_products").mapNotNull { (it as? JsonObject)?.let(::parseBillingProduct) },
        plans = body.array("plans").mapNotNull { (it as? JsonObject)?.let(::parseBillingProduct) },
    )

internal fun parseBillingProduct(body: JsonObject): BillingProductResult =
    BillingProductResult(
        productId = body.string("product_id"),
        kind = body.string("kind"),
        title = body.string("title").ifBlank { body.string("display_name") },
        subtitle = body.string("subtitle"),
        displayName = body.string("display_name"),
        amountCents = body.int("amount_cents"),
        currency = body.string("currency").ifBlank { "CNY" },
        billingPeriod = body.string("billing_period").ifBlank { "none" },
        benefits = body.array("benefits").mapNotNull { it.jsonStringOrNull() },
        badge = body.stringOrNull("badge"),
        sortOrder = body.int("sort_order"),
        availableProviders = body.array("available_providers").mapNotNull { it.jsonStringOrNull() },
    )

internal fun parseBillingOrder(body: JsonObject): BillingOrderResult =
    BillingOrderResult(
        orderId = body.string("order_id"),
        productId = body.string("product_id"),
        productKind = body.string("product_kind"),
        provider = body.string("provider"),
        status = body.string("status"),
        amountCents = body.int("amount_cents"),
        currency = body.string("currency").ifBlank { "CNY" },
        expiresAt = body.string("expires_at"),
        paymentUrl = body.string("payment_url"),
        copyText = body.string("copy_text"),
        qrImageUrl = body.string("qr_image_url"),
        pollAfterMs = body.int("poll_after_ms").takeIf { it > 0 } ?: 3000,
    )

fun formatBillingAmountCents(amountCents: Int, currency: String): String {
    val major = amountCents / 100
    val minor = kotlin.math.abs(amountCents % 100)
    val formatted = "$major.${minor.toString().padStart(2, '0')}"
    return if (currency.equals("CNY", ignoreCase = true)) "¥$formatted" else "${currency.uppercase()} $formatted"
}

fun billingPaymentClipboardText(order: BillingOrderResult): String =
    order.paymentUrl.trim().ifBlank { order.copyText }

internal fun buildLongRecordingAsrJobPayload(
    recordingId: String,
    filename: String,
    mimeType: String,
    sizeBytes: Long,
    recordingType: String,
    asrProfileId: String?,
    agentPrompt: String? = null,
): JsonObject =
    buildJsonObject {
        put("recording_id", recordingId.trim())
        put("filename", filename.trim())
        put("mime_type", mimeType.trim().ifBlank { "audio/wav" })
        put("size_bytes", sizeBytes)
        put("recording_type", recordingType.trim().ifBlank { "meeting" })
        asrProfileId?.trim()?.takeIf { it.isNotEmpty() }?.let { put("asr_profile_id", it) }
        agentPrompt?.trim()?.takeIf { it.isNotEmpty() }?.let { put("agent_prompt", it) }
    }

internal fun parseLongRecordingAsrJob(body: JsonObject): LongRecordingAsrJobResult {
    val job = body["job"] as? JsonObject ?: body
    return LongRecordingAsrJobResult(
        jobId = job.string("job_id"),
        status = job.string("status").ifBlank { "processing" },
        progress = job.double("progress"),
        uploadUrl = job.stringOrNull("upload_url"),
        pollAfterMs = job.int("poll_after_ms").takeIf { it > 0 } ?: 1000,
        text = job.stringOrNull("text"),
        error = job.stringOrNull("error"),
    )
}

private fun parseBillingWallet(body: JsonObject): BillingWalletResult =
    BillingWalletResult(
        balanceCents = body.int("balance_cents"),
        currency = body.string("currency").ifBlank { "CNY" },
    )

private fun parseBillingSubscription(body: JsonObject): BillingSubscriptionResult =
    BillingSubscriptionResult(
        subscriptionId = body.string("subscription_id"),
        productId = body.string("product_id").ifBlank { body.string("plan_id") },
        status = body.string("status"),
        currentPeriodEnd = body.string("current_period_end"),
    )

private fun parseBillingUsageEvent(body: JsonObject): BillingUsageEventResult =
    BillingUsageEventResult(
        usageEventId = body.string("usage_event_id"),
        usageType = body.string("usage_type"),
        quantity = body.int("quantity"),
        amountCents = body.int("amount_cents"),
        backendId = body.stringOrNull("backend_id"),
        createdAt = body.string("created_at"),
    )

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

private fun JsonObject.double(name: String): Double =
    this[name]?.jsonPrimitive?.doubleOrNull ?: 0.0

private fun JsonObject.boolean(name: String): Boolean =
    this[name]?.jsonPrimitive?.booleanOrNull ?: false

private fun JsonObject.array(name: String): List<JsonElement> =
    (this[name] as? JsonArray)?.toList().orEmpty()

private fun JsonElement.jsonStringOrNull(): String? =
    this.jsonPrimitive.contentOrNull?.trim()?.takeIf { it.isNotEmpty() }
