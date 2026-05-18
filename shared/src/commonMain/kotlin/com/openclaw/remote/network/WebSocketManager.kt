package com.openclaw.remote.network

import com.openclaw.remote.data.ChatMessage
import com.openclaw.remote.data.MessageStatus
import com.openclaw.remote.domain.ConnectionState
import com.openclaw.remote.domain.PairingState
import com.openclaw.remote.viewmodel.historyChatMessage
import io.ktor.client.*
import io.ktor.client.plugins.websocket.*
import io.ktor.websocket.*
import kotlinx.coroutines.*
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.UUID

/**
 * WebSocket Manager for Phase 3 Gateway Router protocol.
 * Uses Ktor for cross-platform WebSocket support.
 * Implements reliable delivery: sends ack for received messages,
 * tracks outgoing message seq for delivery confirmation.
 */
class WebSocketManager(
    private val wsUrl: String,
    private val deviceId: String,
    private val deviceLabel: String,
    private val token: String = "",
    private val preferredBackendId: String? = null,
    private val asrMode: String = "router",
    private val asrProfileId: String = "",
) {
    private val instanceId = UUID.randomUUID().toString().take(8)
    private var webSocketSession: WebSocketSession? = null
    private val client = HttpClient {
        install(WebSockets)
    }
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    private val _connectionState = MutableStateFlow(ConnectionState.DISCONNECTED)
    val connectionState: StateFlow<ConnectionState> = _connectionState

    private val _pairingState = MutableStateFlow(
        if (preferredBackendId.isNullOrBlank()) PairingState.UNPAIRED else PairingState.PENDING
    )
    val pairingState: StateFlow<PairingState> = _pairingState

    private val _messageChannel = Channel<WsMessageEvent>(Channel.BUFFERED)
    val messageChannel = _messageChannel

    private var registeredBackendId: String? = null
    private var restorableBackendId: String? = preferredBackendId?.takeIf { it.isNotBlank() }
    private var pendingPairBackendId: String? = null

    private var reconnectAttempts = 0
    private var reconnectJob: Job? = null
    @Volatile private var intentionalDisconnect = false
    @Volatile private var connectAttemptInFlight = false
    private var socketGeneration = 0L

    /** True when reconnecting with a previously paired backend (suppresses pairing message). */
    private var isRestoringPairing = false
    private var autoPairEnabled = !preferredBackendId.isNullOrBlank()

    /** seq → callback to invoke when delivery is confirmed or failed. */
    private val pendingAcks = mutableMapOf<Int, (MessageStatus) -> Unit>()
    private val pendingAudioTimeouts = mutableMapOf<String, Job>()

    fun connect() {
        if (shouldIgnoreConnectRequest(webSocketSession != null, connectAttemptInFlight, reconnectJob != null, intentionalDisconnect)) {
            log(
                "connect ignored active=${webSocketSession != null} " +
                    "inFlight=$connectAttemptInFlight reconnectScheduled=${reconnectJob != null}"
            )
            return
        }
        intentionalDisconnect = false
        cancelReconnect()
        reconnectAttempts = 0
        startSocketAttempt()
    }

    private fun startSocketAttempt() {
        if (webSocketSession != null || connectAttemptInFlight) return
        _connectionState.value = ConnectionState.CONNECTING
        connectAttemptInFlight = true
        val generation = ++socketGeneration
        log("start socket generation=$generation")

        scope.launch {
            try {
                val finalUrl = if (wsUrl.endsWith("/ws")) wsUrl else "$wsUrl/ws"
                val session = client.webSocketSession(finalUrl)
                if (intentionalDisconnect || generation != socketGeneration) {
                    session.close()
                    return@launch
                }
                webSocketSession = session
                log("socket connected generation=$generation")
                _connectionState.value = ConnectionState.CONNECTED
                sendRegister()
                listenForMessages(session, generation)
            } catch (e: Exception) {
                if (intentionalDisconnect || generation != socketGeneration) {
                    return@launch
                }
                offerEvent(
                    WsMessageEvent.NewMessage(
                        ChatMessage("连接失败: ${e.message}", timestamp(), "assistant")
                    )
                )
                handleTransientDisconnect(generation)
            } finally {
                if (generation == socketGeneration) {
                    connectAttemptInFlight = false
                }
            }
        }
    }

    private suspend fun listenForMessages(session: WebSocketSession, generation: Long) {
        try {
            for (frame in session.incoming) {
                when (frame) {
                    is Frame.Text -> handleMessage(frame.readText(), generation)
                    else -> {}
                }
            }
        } catch (e: Exception) {
            log("ws listen failed error=${e.message}")
        } finally {
            logSocketClosed(session, generation)
            if (!intentionalDisconnect && generation == socketGeneration && webSocketSession === session) {
                handleTransientDisconnect(generation)
            }
        }
    }

    private fun handleTransientDisconnect(generation: Long) {
        if (intentionalDisconnect || generation != socketGeneration) return
        restorableBackendId = resolveAutoPairBackendId(
            configuredBackendId = preferredBackendId,
            registeredBackendId = registeredBackendId ?: restorableBackendId,
        )
        registeredBackendId = null
        pendingPairBackendId = null
        webSocketSession = null
        _pairingState.value = transientDisconnectPairingState(
            pairingState = _pairingState.value,
            hasRestorablePairing = hasRestorablePairing(restorableBackendId, preferredBackendId),
        )
        _connectionState.value = transientDisconnectConnectionState(
            pairingState = _pairingState.value,
            hasRestorablePairing = hasRestorablePairing(restorableBackendId, preferredBackendId),
        )
        scheduleReconnect()
    }

    fun disconnect() {
        intentionalDisconnect = true
        cancelReconnect()
        socketGeneration += 1
        connectAttemptInFlight = false
        scope.launch {
            webSocketSession?.close()
            webSocketSession = null
            pendingAudioTimeouts.values.forEach { it.cancel() }
            pendingAudioTimeouts.clear()
            registeredBackendId = null
            pendingPairBackendId = null
            restorableBackendId = preferredBackendId?.takeIf { it.isNotBlank() }
            _connectionState.value = ConnectionState.DISCONNECTED
            _pairingState.value = PairingState.UNPAIRED
        }
    }

    fun requestPair(backendId: String) {
        val normalizedBackendId = backendId.trim()
        if (normalizedBackendId.isEmpty()) {
            return
        }
        if (
            shouldSkipPairRequest(
                connectionState = _connectionState.value,
                pairingState = _pairingState.value,
                registeredBackendId = registeredBackendId,
                pendingPairBackendId = pendingPairBackendId,
                requestedBackendId = normalizedBackendId,
            )
        ) {
            log("pair request skipped backend=$normalizedBackendId state=${_connectionState.value}/${_pairingState.value}")
            return
        }
        if (_connectionState.value != ConnectionState.REGISTERED) {
            _pairingState.value = PairingState.PENDING
            pendingPairBackendId = normalizedBackendId
            log("pair request deferred backend=$normalizedBackendId state=${_connectionState.value}")
            return
        }
        sendPairRequest(normalizedBackendId)
    }

    private fun sendPairRequest(backendId: String) {
        _pairingState.value = PairingState.PENDING
        pendingPairBackendId = backendId
        val frame = buildJsonObject {
            put("type", "pair_request")
            put("target_backend_id", backendId)
        }
        send(frame.toString())
    }

    fun cancelPair() {
        pendingPairBackendId = null
        _pairingState.value = PairingState.UNPAIRED
    }

    fun sendText(text: String) {
        if (!canSendUserPayload(_pairingState.value, registeredBackendId)) {
            return
        }
        val frame = buildJsonObject {
            put("type", "message")
            put("to", registeredBackendId)
            put("content", text)
        }
        // Emit a "sending" placeholder so UI can show spinner immediately
        val placeholderMsg = ChatMessage(
            content = text,
            timestamp = timestamp(),
            senderId = "user",
            status = MessageStatus.SENDING,
        )
        offerEvent(WsMessageEvent.NewMessage(placeholderMsg))
        // Actual send will happen async; the placeholder carries the pending status
        send(frame.toString())
    }

    fun sendAudio(audioData: ByteArray) {
        if (!canSendUserPayload(_pairingState.value, registeredBackendId)) return
        val base64Audio = Base64.encode(audioData)
        val clientMessageId = UUID.randomUUID().toString()
        val audioSummary = AudioPayloadInspector.describe(audioData)
        log(
            "sendAudio id=$clientMessageId bytes=${audioData.size} " +
                "summary=$audioSummary asrMode=${if (asrMode == "backend") "backend" else "router"} " +
                "asrProfile=${asrProfileId.ifBlank { "-" }}"
        )
        val frame = buildJsonObject {
            put("type", "message")
            put("to", registeredBackendId)
            put("client_message_id", clientMessageId)
            put("content", base64Audio)
            put("content_type", "audio")
            putJsonObject("audio") {
                put("format", "wav")
                put("codec", "pcm_s16le")
                put("sample_rate", 16000)
                put("channels", 1)
            }
            putJsonObject("asr") {
                put("mode", if (asrMode == "backend") "backend" else "router")
                if (asrProfileId.isNotEmpty()) {
                    put("profile_id", asrProfileId)
                }
            }
        }
        offerEvent(
            WsMessageEvent.NewMessage(
                ChatMessage(
                    content = "正在识别...",
                    timestamp = timestamp(),
                    senderId = "user",
                    status = MessageStatus.SENDING,
                    clientMessageId = clientMessageId,
                )
            )
        )
        scheduleAudioAsrTimeout(clientMessageId)
        send(
            text = frame.toString(),
            label = "audio:$clientMessageId",
            onFailure = { reason ->
                pendingAudioTimeouts.remove(clientMessageId)?.cancel()
                offerEvent(WsMessageEvent.AsrResult(clientMessageId, false, null, reason))
            },
        )
    }

    fun requestRecentHistory(rounds: Int = 15) {
        val backendId = registeredBackendId ?: return
        if (_pairingState.value != PairingState.PAIRED) return
        val frame = buildJsonObject {
            put("type", "history_request")
            put("app_id", deviceId)
            put("target_backend_id", backendId)
            put("session_key", "current")
            put("limit", maxOf(1, rounds) * 2)
        }
        send(frame.toString())
    }

    fun unpair() {
        if (registeredBackendId == null) return
        autoPairEnabled = false
        val frame = buildJsonObject {
            put("type", "unpair")
            put("target_id", registeredBackendId)
        }
        send(frame.toString())
        registeredBackendId = null
        pendingPairBackendId = null
        _pairingState.value = PairingState.UNPAIRED
    }

    private fun sendRegister() {
        val frame = buildJsonObject {
            put("type", "register")
            put("client_type", "app")
            put("client_id", deviceId)
            put("label", deviceLabel)
            if (token.isNotEmpty()) {
                put("token", token)
            }
        }
        send(frame.toString(), label = "register")
    }

    private fun send(text: String, label: String = "frame", onFailure: ((String) -> Unit)? = null) {
        scope.launch {
            val session = webSocketSession
            if (intentionalDisconnect || session == null) {
                log("ws tx dropped label=$label reason=${if (intentionalDisconnect) "INTENTIONAL_DISCONNECT" else "NO_WEBSOCKET_SESSION"}")
                onFailure?.invoke("NO_WEBSOCKET_SESSION")
                return@launch
            }
            try {
                session.send(Frame.Text(text))
                log("ws tx label=$label ${summarizeJsonFrame(text)}")
            } catch (e: Exception) {
                log("ws tx failed label=$label error=${e.message}")
                onFailure?.invoke("SEND_FAILED:${e.message ?: e::class.simpleName}")
            }
        }
    }

    /** Send an ack frame in response to a received message. */
    private fun sendAck(seq: Int) {
        val frame = buildJsonObject {
            put("type", "ack")
            put("seq", seq)
        }
        send(frame.toString(), label = "ack:$seq")
    }

    private fun handleMessage(text: String, generation: Long) {
        if (!shouldProcessIncomingFrame(intentionalDisconnect, generation, socketGeneration)) {
            log("ws rx ignored stale generation=$generation current=$socketGeneration")
            return
        }
        try {
            val json = Json.parseToJsonElement(text)
            val obj = json as? kotlinx.serialization.json.JsonObject ?: return
            val type = obj["type"]?.jsonPrimitive?.content ?: return
            log("ws rx ${summarizeJsonObject(obj)}")

            when (type) {
                "registered" -> {
                    val success = obj["success"]?.jsonPrimitive?.content?.toBoolean() ?: false
                    if (success) {
                        _connectionState.value = registeredConnectionState(_pairingState.value)
                        reconnectAttempts = 0
                        cancelReconnect()
                        val pendingBackendId = pendingPairBackendId
                        val restoreBackendId = resolveAutoPairBackendId(
                            configuredBackendId = preferredBackendId,
                            registeredBackendId = restorableBackendId ?: registeredBackendId,
                        ).takeIf { autoPairEnabled }
                        val autoPairBackendId = pendingBackendId ?: restoreBackendId
                        if (autoPairBackendId != null) {
                            isRestoringPairing = pendingBackendId == null
                            sendPairRequest(autoPairBackendId)
                        }
                        offerEvent(WsMessageEvent.Registered(deviceId))
                    }
                }
                "pair_response" -> {
                    val approve = obj["approve"]?.jsonPrimitive?.content?.toBoolean() ?: false
                    val backendId = obj["backend_id"]?.jsonPrimitive?.content ?: ""
                    val backendLabel = obj["backend_label"]?.jsonPrimitive?.content ?: backendId
                    if (approve) {
                        registeredBackendId = backendId
                        restorableBackendId = backendId
                        pendingPairBackendId = null
                        _connectionState.value = pairedConnectionState()
                        _pairingState.value = PairingState.PAIRED
                        offerEvent(WsMessageEvent.Paired(backendId, backendLabel, isRestoringPairing))
                        isRestoringPairing = false
                    } else {
                        pendingPairBackendId = null
                        _pairingState.value = PairingState.UNPAIRED
                        isRestoringPairing = false
                        offerEvent(
                            WsMessageEvent.NewMessage(
                                ChatMessage("配对请求被拒绝", timestamp(), "assistant")
                            )
                        )
                    }
                }
                "message" -> {
                    val content = obj["content"]?.jsonPrimitive?.content ?: ""
                    val ts = obj["timestamp"]?.jsonPrimitive?.content ?: timestamp()
                    val seq = obj["seq"]?.jsonPrimitive?.content?.toIntOrNull()
                    val backendId = obj["from"]?.jsonPrimitive?.contentOrNull ?: registeredBackendId

                    // Immediately ack this message so the sender (plugin) gets delivery confirmation
                    if (seq != null) {
                        sendAck(seq)
                    }

                    offerEvent(WsMessageEvent.NewMessage(ChatMessage(content, ts, "assistant"), backendId))
                }
                "history_response" -> {
                    val backendId = obj["backend_id"]?.jsonPrimitive?.contentOrNull
                        ?: obj["target_backend_id"]?.jsonPrimitive?.contentOrNull
                    val messages = obj["messages"]?.jsonArray?.mapNotNull { element ->
                        val item = element as? JsonObject ?: return@mapNotNull null
                        val content = item["content"]?.jsonPrimitive?.content ?: return@mapNotNull null
                        val role = item["role"]?.jsonPrimitive?.content ?: "assistant"
                        val rawTimestamp = item["timestamp"]?.jsonPrimitive?.content ?: timestamp()
                        historyChatMessage(content, role, rawTimestamp)
                    }.orEmpty()
                    val hasMore = obj["has_more"]?.jsonPrimitive?.content?.toBoolean() ?: false
                    val error = obj["error"]?.jsonPrimitive?.contentOrNull
                    offerEvent(WsMessageEvent.HistoryResponse(messages, hasMore, error, backendId))
                }
                "asr_result" -> {
                    val clientMessageId = obj["client_message_id"]?.jsonPrimitive?.content
                    val success = obj["success"]?.jsonPrimitive?.content?.toBoolean() ?: false
                    val transcript = obj["text"]?.jsonPrimitive?.content
                    val error = obj["error"]?.jsonPrimitive?.content
                    if (clientMessageId != null) {
                        pendingAudioTimeouts.remove(clientMessageId)?.cancel()
                    }
                    offerEvent(WsMessageEvent.AsrResult(clientMessageId, success, transcript, error))
                }
                "ack" -> {
                    // Server acks our sent message — we don't need to act on it here
                    // because we don't track per-message delivery state at the app level
                }
                "delivery_failed" -> {
                    val seq = obj["seq"]?.jsonPrimitive?.content?.toIntOrNull()
                    val reason = obj["reason"]?.jsonPrimitive?.content ?: "unknown"
                    if (seq != null) {
                        pendingAcks.remove(seq)?.invoke(MessageStatus.FAILED)
                    }
                    offerEvent(
                        WsMessageEvent.NewMessage(
                            ChatMessage("消息发送失败: $reason", timestamp(), "assistant")
                        )
                    )
                }
                "ping" -> {
                    send(
                        buildJsonObject {
                            put("type", "pong")
                        }.toString(),
                        label = "pong",
                    )
                }
                "pong" -> {}
                "unpaired" -> {
                    val targetId = obj["target_id"]?.jsonPrimitive?.content ?: ""
                    if (targetId == registeredBackendId) {
                        autoPairEnabled = false
                        registeredBackendId = null
                        restorableBackendId = null
                        pendingPairBackendId = null
                        _pairingState.value = PairingState.UNPAIRED
                        offerEvent(WsMessageEvent.Unpaired(targetId))
                    }
                }
                "error" -> {
                    val code = obj["code"]?.jsonPrimitive?.content ?: "unknown"
                    val msg = obj["message"]?.jsonPrimitive?.content ?: "未知错误"
                    val wasPairing = _pairingState.value == PairingState.PENDING
                    if (wasPairing) {
                        val recovery = recoverPairingAfterRouterError(
                            pairingState = _pairingState.value,
                            pendingPairBackendId = pendingPairBackendId,
                        )
                        pendingPairBackendId = recovery.pendingPairBackendId
                        _pairingState.value = recovery.pairingState
                        isRestoringPairing = false
                    }
                    offerEvent(
                        WsMessageEvent.NewMessage(
                            ChatMessage(
                                if (wasPairing) "配对失败 ($code): $msg" else "错误 ($code): $msg",
                                timestamp(),
                                "assistant",
                            )
                        )
                    )
                }
            }
        } catch (e: Exception) {
            log("ws rx parse failed error=${e.message} raw=${text.take(240)}")
        }
    }

    private fun scheduleAudioAsrTimeout(clientMessageId: String) {
        pendingAudioTimeouts.remove(clientMessageId)?.cancel()
        pendingAudioTimeouts[clientMessageId] = scope.launch {
            delay(ASR_RESULT_TIMEOUT_MS)
            pendingAudioTimeouts.remove(clientMessageId)
            log("asr timeout id=$clientMessageId")
            offerEvent(WsMessageEvent.AsrResult(clientMessageId, false, null, "ASR_TIMEOUT_NO_RESULT"))
        }
    }

    private fun offerEvent(event: WsMessageEvent) {
        scope.launch {
            _messageChannel.send(event)
        }
    }

    private fun timestamp(): String {
        return SimpleDateFormat("HH:mm", Locale.getDefault()).format(Date())
    }

    private fun summarizeJsonFrame(text: String): String {
        return runCatching {
            val obj = Json.parseToJsonElement(text) as? JsonObject ?: return@runCatching "bytes=${text.length}"
            summarizeJsonObject(obj)
        }.getOrDefault("bytes=${text.length}")
    }

    private fun summarizeJsonObject(obj: JsonObject): String {
        val type = obj.stringField("type")
        val contentType = obj.stringField("content_type")
        val clientMessageId = obj.stringField("client_message_id")
        val error = obj.stringField("error") ?: obj.stringField("message")
        val contentLength = obj["content"]?.jsonPrimitive?.contentOrNull?.length
        return buildString {
            append("type=${type ?: "-"}")
            if (contentType != null) append(" contentType=$contentType")
            if (clientMessageId != null) append(" id=$clientMessageId")
            if (contentLength != null) append(" contentChars=$contentLength")
            if (error != null) append(" error=$error")
        }
    }

    private fun JsonObject.stringField(name: String): String? =
        this[name]?.jsonPrimitive?.contentOrNull

    private fun log(message: String) {
        println("$LOG_TAG [$instanceId] $message")
    }

    private suspend fun logSocketClosed(session: WebSocketSession, generation: Long) {
        val reason = runCatching {
            withTimeoutOrNull(200) {
                (session as? DefaultWebSocketSession)?.closeReason?.await()
            }
        }.getOrNull()
        log(
            "ws listen ended generation=$generation current=$socketGeneration " +
                "intentional=$intentionalDisconnect closeReason=${reason?.let { "${it.code}:${it.message}" } ?: "-"}"
        )
    }

    private fun scheduleReconnect() {
        if (intentionalDisconnect) return
        cancelReconnect()
        val delay = minOf(RECONNECT_BASE_DELAY_MS * (1 shl reconnectAttempts), RECONNECT_MAX_DELAY_MS)
        reconnectAttempts++
        log("scheduleReconnect delay=${delay}ms attempts=$reconnectAttempts")
        reconnectJob = scope.launch {
            delay(delay)
            if (!intentionalDisconnect) {
                startSocketAttempt()
            }
        }
    }

    private fun cancelReconnect() {
        reconnectJob?.cancel()
        reconnectJob = null
    }

    private companion object {
        private const val LOG_TAG = "OpenClawWS"
        private const val ASR_RESULT_TIMEOUT_MS = 30_000L
        private const val RECONNECT_BASE_DELAY_MS = 2_000L
        private const val RECONNECT_MAX_DELAY_MS = 30_000L
    }
}

internal fun resolveAutoPairBackendId(configuredBackendId: String?, registeredBackendId: String?): String? {
    return registeredBackendId?.takeIf { it.isNotBlank() }
        ?: configuredBackendId?.takeIf { it.isNotBlank() }
}

internal fun transientDisconnectConnectionState(
    pairingState: PairingState,
    hasRestorablePairing: Boolean,
): ConnectionState {
    return if (pairingState == PairingState.PAIRED || pairingState == PairingState.PENDING || hasRestorablePairing) {
        ConnectionState.CONNECTING
    } else {
        ConnectionState.DISCONNECTED
    }
}

internal fun transientDisconnectPairingState(
    pairingState: PairingState,
    hasRestorablePairing: Boolean,
): PairingState {
    return if (pairingState == PairingState.PAIRED || pairingState == PairingState.PENDING || hasRestorablePairing) {
        PairingState.PENDING
    } else {
        PairingState.UNPAIRED
    }
}

internal fun registeredConnectionState(pairingState: PairingState): ConnectionState =
    if (pairingState == PairingState.PAIRED) ConnectionState.PAIRED else ConnectionState.REGISTERED

internal fun pairedConnectionState(): ConnectionState = ConnectionState.PAIRED

internal fun canSendUserPayload(pairingState: PairingState, registeredBackendId: String?): Boolean =
    pairingState == PairingState.PAIRED && !registeredBackendId.isNullOrBlank()

internal fun shouldSkipPairRequest(
    connectionState: ConnectionState,
    pairingState: PairingState,
    registeredBackendId: String?,
    pendingPairBackendId: String?,
    requestedBackendId: String,
): Boolean {
    val normalizedBackendId = requestedBackendId.trim()
    return normalizedBackendId.isEmpty() ||
        (connectionState == ConnectionState.PAIRED &&
            pairingState == PairingState.PAIRED &&
            registeredBackendId == normalizedBackendId) ||
        (pairingState == PairingState.PENDING &&
            pendingPairBackendId == normalizedBackendId)
}

internal fun shouldProcessIncomingFrame(
    intentionalDisconnect: Boolean,
    frameGeneration: Long,
    currentGeneration: Long,
): Boolean =
    !intentionalDisconnect && frameGeneration == currentGeneration

internal fun shouldIgnoreConnectRequest(
    hasActiveSession: Boolean,
    connectAttemptInFlight: Boolean,
    reconnectScheduled: Boolean,
    intentionalDisconnect: Boolean,
): Boolean =
    !intentionalDisconnect && (hasActiveSession || connectAttemptInFlight || reconnectScheduled)

internal data class PairingErrorRecovery(
    val pairingState: PairingState,
    val pendingPairBackendId: String?,
)

internal fun recoverPairingAfterRouterError(
    pairingState: PairingState,
    pendingPairBackendId: String?,
): PairingErrorRecovery =
    if (pairingState == PairingState.PENDING && !pendingPairBackendId.isNullOrBlank()) {
        PairingErrorRecovery(PairingState.UNPAIRED, null)
    } else {
        PairingErrorRecovery(pairingState, pendingPairBackendId)
    }

private fun hasRestorablePairing(registeredBackendId: String?, configuredBackendId: String?): Boolean {
    return !registeredBackendId.isNullOrBlank() || !configuredBackendId.isNullOrBlank()
}

/**
 * Lightweight WAV summary for diagnosing app → Router ASR mismatches.
 */
private object AudioPayloadInspector {
    fun describe(data: ByteArray): String {
        if (data.size < 44) return "invalid=too_short"
        val riff = data.ascii(0, 4)
        val wave = data.ascii(8, 4)
        val fmt = data.ascii(12, 4)
        val channels = data.uint16LE(22)
        val sampleRate = data.uint32LE(24)
        val bitsPerSample = data.uint16LE(34)
        val dataMarker = data.ascii(36, 4)
        val declaredDataSize = data.uint32LE(40)
        val actualDataSize = data.size - 44
        val durationMs = if (sampleRate > 0 && channels > 0 && bitsPerSample > 0) {
            actualDataSize * 8L * 1_000L / (sampleRate.toLong() * channels.toLong() * bitsPerSample.toLong())
        } else {
            0L
        }
        val averageAbs = pcmAverageAbs(data, 44)
        return "riff=$riff wave=$wave fmt=$fmt data=$dataMarker channels=$channels " +
            "sampleRate=$sampleRate bits=$bitsPerSample declaredData=$declaredDataSize " +
            "actualData=$actualDataSize durationMs=$durationMs avgAbs=$averageAbs"
    }

    private fun pcmAverageAbs(data: ByteArray, offset: Int): Int {
        if (data.size <= offset + 1) return 0
        val sampleCount = (data.size - offset) / 2
        if (sampleCount <= 0) return 0
        var total = 0L
        for (index in 0 until sampleCount) {
            val sampleOffset = offset + index * 2
            val sample = (data[sampleOffset].toInt() and 0xFF) or (data[sampleOffset + 1].toInt() shl 8)
            val signed = sample.toShort().toInt()
            val absValue = if (signed == Short.MIN_VALUE.toInt()) 32768 else kotlin.math.abs(signed)
            total += absValue
        }
        return (total / sampleCount).toInt()
    }

    private fun ByteArray.ascii(offset: Int, length: Int): String {
        if (offset + length > size) return "-"
        return copyOfRange(offset, offset + length).toString(Charsets.US_ASCII)
    }

    private fun ByteArray.uint16LE(offset: Int): Int {
        if (offset + 1 >= size) return 0
        return (this[offset].toInt() and 0xFF) or ((this[offset + 1].toInt() and 0xFF) shl 8)
    }

    private fun ByteArray.uint32LE(offset: Int): Long {
        if (offset + 3 >= size) return 0
        return (this[offset].toLong() and 0xFF) or
            ((this[offset + 1].toLong() and 0xFF) shl 8) or
            ((this[offset + 2].toLong() and 0xFF) shl 16) or
            ((this[offset + 3].toLong() and 0xFF) shl 24)
    }
}

/**
 * Platform-specific Base64 encoding
 */
expect object Base64 {
    fun encode(data: ByteArray): String
}
