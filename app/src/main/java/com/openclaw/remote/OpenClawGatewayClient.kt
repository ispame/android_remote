package com.openclaw.remote

import android.content.Context
import android.os.Build
import java.util.Locale
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withTimeout
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import org.json.JSONArray
import org.json.JSONObject

class OpenClawGatewayClient(
    context: Context,
    private val settings: RemoteSettings,
    private val callbacks: RemoteClientCallbacks,
) : RemoteClient {
    override val supportsStreamingAudio: Boolean = false

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val identityStore = DeviceIdentityStore(context.applicationContext)
    private val deviceAuthStore = DeviceAuthStore(context.applicationContext)
    private val pending = ConcurrentHashMap<String, CompletableDeferred<RpcResponse>>()
    private val writeMutex = Mutex()
    private val httpClient = OkHttpClient.Builder()
        .readTimeout(0, TimeUnit.MILLISECONDS)
        .pingInterval(30, TimeUnit.SECONDS)
        .build()

    private var webSocket: WebSocket? = null
    private var connectNonceDeferred = CompletableDeferred<String>()
    private var manualDisconnect = false
    private var currentSessionKey = resolveSessionKey(settings.openClawSessionKey, null)

    override fun connect() {
        manualDisconnect = false
        connectNonceDeferred = CompletableDeferred()
        callbacks.onError(null)
        callbacks.onStatusChanged(false, "正在连接 OpenClaw Gateway…")

        val request = Request.Builder()
            .url(buildWebSocketUrl())
            .build()

        webSocket = httpClient.newWebSocket(request, object : WebSocketListener() {
            override fun onOpen(webSocket: WebSocket, response: Response) {
                callbacks.onStatusChanged(false, "正在完成 OpenClaw 握手…")
                scope.launch {
                    runCatching { performHandshake() }
                        .onFailure { error ->
                            callbacks.onError("OpenClaw 握手失败: ${error.message ?: "未知错误"}")
                            callbacks.onStatusChanged(false, "OpenClaw 未连接")
                            webSocket.close(1008, "Handshake failed")
                        }
                }
            }

            override fun onMessage(webSocket: WebSocket, text: String) {
                scope.launch {
                    handleFrame(text)
                }
            }

            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                failPending("OpenClaw 连接已中断")
                if (!manualDisconnect) {
                    callbacks.onError("OpenClaw 连接失败: ${t.message ?: "未知错误"}")
                    callbacks.onStatusChanged(false, "OpenClaw 连接失败")
                }
            }

            override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                failPending("OpenClaw 连接已关闭")
                if (!manualDisconnect) {
                    callbacks.onStatusChanged(false, "OpenClaw 已断开连接")
                }
            }
        })
    }

    override fun disconnect() {
        manualDisconnect = true
        callbacks.onStreamingTextChanged(null)
        failPending("OpenClaw 已断开连接")
        webSocket?.close(1000, "User disconnect")
        webSocket = null
        callbacks.onStatusChanged(false, "已断开连接")
    }

    override fun sendText(text: String) {
        scope.launch {
            runCatching {
                callbacks.onError(null)
                callbacks.onMessage(ChatRole.USER, text)
                callbacks.onStreamingTextChanged(null)

                val params = JSONObject().apply {
                    put("sessionKey", currentSessionKey)
                    put("message", text)
                    put("thinking", "off")
                    put("timeoutMs", 30_000)
                    put("idempotencyKey", UUID.randomUUID().toString())
                }
                val response = request("chat.send", params, 30_000)
                if (!response.ok) {
                    throw IllegalStateException(response.error?.toMessage() ?: "chat.send 失败")
                }
            }.onFailure { error ->
                callbacks.onError("OpenClaw 发送失败: ${error.message ?: "未知错误"}")
            }
        }
    }

    override fun startAudioStream() {
        callbacks.onError("OpenClaw Gateway 兼容模式当前只接入文本聊天")
    }

    override fun sendAudioChunk(chunk: ByteArray, isLast: Boolean) {
        callbacks.onError("OpenClaw Gateway 兼容模式当前只接入文本聊天")
    }

    override fun endAudioStream() {
        callbacks.onAsrDone()
    }

    private suspend fun performHandshake() {
        val nonce = withTimeout(2_000) {
            connectNonceDeferred.await()
        }
        val identity = identityStore.loadOrCreate()
        val storedToken = deviceAuthStore.loadToken(identity.deviceId, ROLE_OPERATOR)
        val explicitSharedToken = settings.openClawSharedToken.trim().takeIf { it.isNotEmpty() }
        val explicitBootstrapToken = settings.openClawBootstrapToken.trim().takeIf { it.isNotEmpty() }
        val explicitPassword = settings.openClawPassword.trim().takeIf { it.isNotEmpty() }

        var auth = selectAuth(
            explicitSharedToken = explicitSharedToken,
            explicitBootstrapToken = explicitBootstrapToken,
            explicitPassword = explicitPassword,
            storedToken = storedToken,
            tryDeviceRetry = false,
        )
        var response = request("connect", buildConnectParams(identity, nonce, auth), 12_000)

        if (
            !response.ok &&
            explicitSharedToken != null &&
            storedToken != null &&
            shouldRetryWithDeviceToken(response.error)
        ) {
            auth = selectAuth(
                explicitSharedToken = explicitSharedToken,
                explicitBootstrapToken = explicitBootstrapToken,
                explicitPassword = explicitPassword,
                storedToken = storedToken,
                tryDeviceRetry = true,
            )
            response = request("connect", buildConnectParams(identity, nonce, auth), 12_000)
            if (!response.ok && response.error?.detailCode == "AUTH_DEVICE_TOKEN_MISMATCH") {
                deviceAuthStore.clearToken(identity.deviceId, ROLE_OPERATOR)
            }
        }

        if (!response.ok) {
            throw IllegalStateException(response.error?.toMessage() ?: "connect 失败")
        }

        val payload = JSONObject(response.payloadJson ?: "{}")
        handleConnectSuccess(identity.deviceId, auth, payload)
        callbacks.onError(null)
        callbacks.onStatusChanged(
            true,
            payload.optJSONObject("server")?.optString("host")?.takeIf { it.isNotBlank() }
                ?.let { "已连接到 OpenClaw: $it" }
                ?: "已连接到 OpenClaw Gateway",
        )

        runCatching {
            subscribeToChat()
        }
        loadHistory()
    }

    private fun handleConnectSuccess(deviceId: String, auth: SelectedAuth, payload: JSONObject) {
        val authObject = payload.optJSONObject("auth")
        authObject?.optString("deviceToken")?.takeIf { it.isNotBlank() }?.let { token ->
            deviceAuthStore.saveToken(deviceId, ROLE_OPERATOR, token)
        }

        if (auth.source == AuthSource.BOOTSTRAP) {
            val deviceTokens = authObject?.optJSONArray("deviceTokens")
            if (deviceTokens != null) {
                for (index in 0 until deviceTokens.length()) {
                    val entry = deviceTokens.optJSONObject(index) ?: continue
                    if (entry.optString("role") == ROLE_OPERATOR) {
                        entry.optString("deviceToken").takeIf { it.isNotBlank() }?.let { token ->
                            deviceAuthStore.saveToken(deviceId, ROLE_OPERATOR, token)
                        }
                    }
                }
            }
        }

        val mainSessionKey = payload
            .optJSONObject("snapshot")
            ?.optJSONObject("sessionDefaults")
            ?.optString("mainSessionKey")
            ?.takeIf { it.isNotBlank() }
        currentSessionKey = resolveSessionKey(settings.openClawSessionKey, mainSessionKey)
    }

    private suspend fun subscribeToChat() {
        val payload = JSONObject().apply {
            put("event", "chat.subscribe")
            put("payloadJSON", JSONObject().put("sessionKey", currentSessionKey).toString())
        }
        request("node.event", payload, 8_000)
    }

    private suspend fun loadHistory() {
        runCatching {
            val response = request(
                "chat.history",
                JSONObject().put("sessionKey", currentSessionKey),
                15_000,
            )
            if (!response.ok) {
                throw IllegalStateException(response.error?.toMessage() ?: "chat.history 失败")
            }
            callbacks.onMessagesReplaced(parseHistory(response.payloadJson))
        }.onFailure { error ->
            callbacks.onError("OpenClaw 历史消息加载失败: ${error.message ?: "未知错误"}")
        }
    }

    private suspend fun handleFrame(text: String) {
        val frame = JSONObject(text)
        when (frame.optString("type")) {
            "res" -> handleResponse(frame)
            "event" -> handleEvent(frame)
        }
    }

    private fun handleResponse(frame: JSONObject) {
        val id = frame.optString("id")
        if (id.isBlank()) {
            return
        }

        val error = frame.optJSONObject("error")?.let { errorObject ->
            RpcError(
                code = errorObject.optString("code", "UNAVAILABLE"),
                message = errorObject.optString("message", "request failed"),
                detailCode = errorObject.optJSONObject("details")?.optString("code"),
                canRetryWithDeviceToken = errorObject.optJSONObject("details")?.optBoolean("canRetryWithDeviceToken") == true,
                recommendedNextStep = errorObject.optJSONObject("details")?.optString("recommendedNextStep"),
            )
        }

        pending.remove(id)?.complete(
            RpcResponse(
                ok = frame.optBoolean("ok"),
                payloadJson = when {
                    frame.has("payload") && !frame.isNull("payload") -> frame.get("payload").toString()
                    else -> null
                },
                error = error,
            ),
        )
    }

    private suspend fun handleEvent(frame: JSONObject) {
        val event = frame.optString("event")
        val payloadJson = when {
            frame.has("payload") && !frame.isNull("payload") -> frame.get("payload").toString()
            frame.has("payloadJSON") && !frame.isNull("payloadJSON") -> frame.getString("payloadJSON")
            else -> null
        }

        when (event) {
            "connect.challenge" -> {
                val nonce = payloadJson?.let(::JSONObject)?.optString("nonce")?.trim().orEmpty()
                if (nonce.isNotEmpty() && !connectNonceDeferred.isCompleted) {
                    connectNonceDeferred.complete(nonce)
                }
            }

            "chat" -> {
                if (payloadJson != null) {
                    handleChatEvent(JSONObject(payloadJson))
                }
            }

            "agent" -> {
                if (payloadJson != null) {
                    handleAgentEvent(JSONObject(payloadJson))
                }
            }

            "health" -> {
                callbacks.onStatusChanged(true, "已连接到 OpenClaw Gateway")
            }

            "seqGap" -> {
                callbacks.onError("OpenClaw 事件流中断，请重新连接或刷新历史")
            }
        }
    }

    private fun handleChatEvent(payload: JSONObject) {
        val sessionKey = payload.optString("sessionKey").trim()
        if (sessionKey.isNotEmpty() && sessionKey != currentSessionKey) {
            return
        }

        when (payload.optString("state")) {
            "delta" -> {
                val message = payload.optJSONObject("message") ?: return
                parseAssistantDeltaText(message)?.let { text ->
                    callbacks.onStreamingTextChanged(text)
                }
            }

            "final", "aborted", "error" -> {
                callbacks.onStreamingTextChanged(null)
                if (payload.optString("state") == "error") {
                    callbacks.onError(payload.optString("errorMessage").ifBlank { "OpenClaw 会话失败" })
                }
                scope.launch {
                    loadHistory()
                }
            }
        }
    }

    private fun handleAgentEvent(payload: JSONObject) {
        val sessionKey = payload.optString("sessionKey").trim()
        if (sessionKey.isNotEmpty() && sessionKey != currentSessionKey) {
            return
        }

        when (payload.optString("stream")) {
            "assistant" -> {
                val text = payload.optJSONObject("data")?.optString("text")?.trim().orEmpty()
                if (text.isNotEmpty()) {
                    callbacks.onStreamingTextChanged(text)
                }
            }

            "error" -> {
                callbacks.onError("OpenClaw 事件流中断，请刷新会话")
            }
        }
    }

    private fun parseAssistantDeltaText(message: JSONObject): String? {
        if (message.optString("role") != "assistant") {
            return null
        }
        val content = message.optJSONArray("content") ?: return null
        for (index in 0 until content.length()) {
            val item = content.optJSONObject(index) ?: continue
            if (item.optString("type") == "text") {
                val text = item.optString("text").trim()
                if (text.isNotEmpty()) {
                    return text
                }
            }
        }
        return null
    }

    private fun parseHistory(payloadJson: String?): List<ChatMessage> {
        val payload = JSONObject(payloadJson ?: "{}")
        val messages = payload.optJSONArray("messages") ?: JSONArray()
        val parsed = mutableListOf<ChatMessage>()

        for (index in 0 until messages.length()) {
            val message = messages.optJSONObject(index) ?: continue
            val role = when (message.optString("role").lowercase()) {
                "user" -> ChatRole.USER
                "assistant" -> ChatRole.ASSISTANT
                else -> ChatRole.SYSTEM
            }
            val content = parseMessageContent(message.optJSONArray("content"))
            if (content.isBlank()) {
                continue
            }
            parsed += ChatMessage(
                role = role,
                content = content,
                timestampMs = message.optLong("timestamp").takeIf { it > 0 } ?: System.currentTimeMillis(),
            )
        }

        return parsed
    }

    private fun parseMessageContent(parts: JSONArray?): String {
        if (parts == null || parts.length() == 0) {
            return ""
        }

        val lines = mutableListOf<String>()
        for (index in 0 until parts.length()) {
            val item = parts.optJSONObject(index) ?: continue
            when (item.optString("type")) {
                "text" -> {
                    val text = item.optString("text").trim()
                    if (text.isNotEmpty()) {
                        lines += text
                    }
                }

                else -> {
                    val type = item.optString("type").ifBlank { "attachment" }
                    val fileName = item.optString("fileName").takeIf { it.isNotBlank() }
                    lines += listOfNotNull("[$type]", fileName).joinToString(" ")
                }
            }
        }
        return lines.joinToString("\n")
    }

    private suspend fun request(method: String, params: JSONObject?, timeoutMs: Long): RpcResponse {
        val socket = webSocket ?: throw IllegalStateException("WebSocket 尚未建立")
        val id = UUID.randomUUID().toString()
        val deferred = CompletableDeferred<RpcResponse>()
        pending[id] = deferred

        val frame = JSONObject().apply {
            put("type", "req")
            put("id", id)
            put("method", method)
            if (params != null) {
                put("params", params)
            }
        }

        writeMutex.withLock {
            val sent = socket.send(frame.toString())
            if (!sent) {
                pending.remove(id)
                throw IllegalStateException("WebSocket 写入失败")
            }
        }

        return try {
            withTimeout(timeoutMs.toLong()) {
                deferred.await()
            }
        } finally {
            pending.remove(id)
        }
    }

    private fun buildConnectParams(identity: DeviceIdentity, nonce: String, auth: SelectedAuth): JSONObject {
        val clientId = "android_remote"
        val clientMode = "mobile"
        val platform = "android"
        val deviceFamily = "android"
        val scopes = listOf(
            "operator.approvals",
            "operator.read",
            "operator.talk.secrets",
            "operator.write",
        )
        val signedAtMs = System.currentTimeMillis()
        val payload = DeviceAuthPayload.buildV3(
            deviceId = identity.deviceId,
            clientId = clientId,
            clientMode = clientMode,
            role = ROLE_OPERATOR,
            scopes = scopes,
            signedAtMs = signedAtMs,
            token = auth.signatureToken,
            nonce = nonce,
            platform = platform,
            deviceFamily = deviceFamily,
        )
        val signature = identityStore.signPayload(payload, identity)
        val publicKey = identityStore.publicKeyBase64Url(identity)

        val params = JSONObject().apply {
            put("minProtocol", 3)
            put("maxProtocol", 3)
            put("client", JSONObject().apply {
                put("id", clientId)
                put("displayName", Build.MODEL)
                put("version", BuildConfig.VERSION_NAME)
                put("platform", platform)
                put("mode", clientMode)
                put("instanceId", "${Build.MANUFACTURER}-${Build.MODEL}")
                put("deviceFamily", deviceFamily)
                put("modelIdentifier", Build.MODEL)
            })
            put("role", ROLE_OPERATOR)
            put("scopes", JSONArray(scopes))
            put("locale", Locale.getDefault().toLanguageTag())
            put("userAgent", "android_remote/${BuildConfig.VERSION_NAME}")
        }

        val authObject = when {
            auth.authToken != null -> JSONObject().apply {
                put("token", auth.authToken)
                auth.authDeviceToken?.let { put("deviceToken", it) }
            }

            auth.authBootstrapToken != null -> JSONObject().apply {
                put("bootstrapToken", auth.authBootstrapToken)
            }

            auth.authPassword != null -> JSONObject().apply {
                put("password", auth.authPassword)
            }

            else -> null
        }
        authObject?.let { params.put("auth", it) }

        if (!signature.isNullOrBlank() && !publicKey.isNullOrBlank()) {
            params.put("device", JSONObject().apply {
                put("id", identity.deviceId)
                put("publicKey", publicKey)
                put("signature", signature)
                put("signedAt", signedAtMs)
                put("nonce", nonce)
            })
        }

        return params
    }

    private fun selectAuth(
        explicitSharedToken: String?,
        explicitBootstrapToken: String?,
        explicitPassword: String?,
        storedToken: String?,
        tryDeviceRetry: Boolean,
    ): SelectedAuth {
        val authToken = explicitSharedToken
            ?: if (explicitPassword == null && (explicitBootstrapToken == null || storedToken != null)) {
                storedToken
            } else {
                null
            }
        val authDeviceToken = if (tryDeviceRetry) storedToken else null
        val authBootstrapToken = if (authToken == null) explicitBootstrapToken else null
        val source = when {
            authDeviceToken != null || (explicitSharedToken == null && authToken != null) -> AuthSource.DEVICE_TOKEN
            authToken != null -> AuthSource.SHARED_TOKEN
            authBootstrapToken != null -> AuthSource.BOOTSTRAP
            explicitPassword != null -> AuthSource.PASSWORD
            else -> AuthSource.NONE
        }
        return SelectedAuth(
            authToken = authToken,
            authBootstrapToken = authBootstrapToken,
            authDeviceToken = authDeviceToken,
            authPassword = explicitPassword,
            signatureToken = authToken ?: authBootstrapToken,
            source = source,
        )
    }

    private fun shouldRetryWithDeviceToken(error: RpcError?): Boolean {
        if (error == null) {
            return false
        }
        return error.canRetryWithDeviceToken ||
            error.recommendedNextStep == "retry_with_device_token" ||
            error.detailCode == "AUTH_TOKEN_MISMATCH"
    }

    private fun failPending(message: String) {
        val error = IllegalStateException(message)
        pending.forEach { (_, deferred) ->
            deferred.completeExceptionally(error)
        }
        pending.clear()
    }

    private fun buildWebSocketUrl(): String {
        val scheme = if (settings.useTls) "wss" else "ws"
        val port = settings.resolvedPort() ?: defaultPortFor(BackendKind.OPENCLAW).toInt()
        return "$scheme://${formatHostAuthority(settings.host)}:$port"
    }

    private fun resolveSessionKey(requestedSessionKey: String, mainSessionKey: String?): String {
        val trimmed = requestedSessionKey.trim()
        if (trimmed.isEmpty()) {
            return mainSessionKey?.takeIf { it.isNotBlank() } ?: "main"
        }
        if (trimmed == "main" && !mainSessionKey.isNullOrBlank()) {
            return mainSessionKey
        }
        return trimmed
    }

    private data class RpcResponse(
        val ok: Boolean,
        val payloadJson: String?,
        val error: RpcError?,
    )

    private data class RpcError(
        val code: String,
        val message: String,
        val detailCode: String?,
        val canRetryWithDeviceToken: Boolean,
        val recommendedNextStep: String?,
    ) {
        fun toMessage(): String {
            val detail = detailCode?.takeIf { it.isNotBlank() }?.let { " ($it)" }.orEmpty()
            return "$code: $message$detail"
        }
    }

    private data class SelectedAuth(
        val authToken: String?,
        val authBootstrapToken: String?,
        val authDeviceToken: String?,
        val authPassword: String?,
        val signatureToken: String?,
        val source: AuthSource,
    )

    private enum class AuthSource {
        DEVICE_TOKEN,
        SHARED_TOKEN,
        BOOTSTRAP,
        PASSWORD,
        NONE,
    }

    private companion object {
        const val ROLE_OPERATOR = "operator"
    }
}
