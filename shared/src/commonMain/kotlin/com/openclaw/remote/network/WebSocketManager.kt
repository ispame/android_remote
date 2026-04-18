package com.openclaw.remote.network

import com.openclaw.remote.data.ChatMessage
import com.openclaw.remote.domain.ConnectionState
import com.openclaw.remote.domain.PairingState
import io.ktor.client.*
import io.ktor.client.plugins.websocket.*
import io.ktor.websocket.*
import kotlinx.coroutines.*
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.jsonPrimitive
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * WebSocket Manager for Phase 3 Gateway Router protocol.
 * Uses Ktor for cross-platform WebSocket support.
 */
class WebSocketManager(
    private val wsUrl: String,
    private val deviceId: String,
    private val deviceLabel: String,
    private val token: String = "",
) {
    private var webSocketSession: WebSocketSession? = null
    private val client = HttpClient {
        install(WebSocket)
    }
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    private val _connectionState = MutableStateFlow(ConnectionState.DISCONNECTED)
    val connectionState: StateFlow<ConnectionState> = _connectionState

    private val _pairingState = MutableStateFlow(PairingState.UNPAIRED)
    val pairingState: StateFlow<PairingState> = _pairingState

    private val _messageChannel = Channel<WsMessageEvent>(Channel.BUFFERED)
    val messageChannel = _messageChannel

    private var registeredBackendId: String? = null

    fun connect() {
        if (_connectionState.value != ConnectionState.DISCONNECTED) return
        _connectionState.value = ConnectionState.CONNECTING

        scope.launch {
            try {
                val finalUrl = if (wsUrl.endsWith("/ws")) wsUrl else "$wsUrl/ws"
                webSocketSession = client.webSocketSession(finalUrl)
                _connectionState.value = ConnectionState.CONNECTED
                sendRegister()
                listenForMessages()
            } catch (e: Exception) {
                _connectionState.value = ConnectionState.DISCONNECTED
                _pairingState.value = PairingState.UNPAIRED
                offerEvent(
                    WsMessageEvent.NewMessage(
                        ChatMessage("连接失败: ${e.message}", timestamp(), "assistant")
                    )
                )
            }
        }
    }

    private suspend fun listenForMessages() {
        val session = webSocketSession ?: return
        try {
            for (frame in session.incoming) {
                when (frame) {
                    is Frame.Text -> handleMessage(frame.readText())
                    else -> {}
                }
            }
        } catch (e: Exception) {
            _connectionState.value = ConnectionState.DISCONNECTED
            _pairingState.value = PairingState.UNPAIRED
        }
    }

    fun disconnect() {
        scope.launch {
            webSocketSession?.close()
            webSocketSession = null
            _connectionState.value = ConnectionState.DISCONNECTED
            _pairingState.value = PairingState.UNPAIRED
        }
    }

    fun requestPair(backendId: String) {
        if (_connectionState.value != ConnectionState.REGISTERED) {
            return
        }
        _pairingState.value = PairingState.PENDING
        val frame = buildJsonObject {
            put("type", "pair_request")
            put("target_backend_id", backendId)
        }
        send(frame.toString())
    }

    fun cancelPair() {
        _pairingState.value = PairingState.UNPAIRED
    }

    fun sendText(text: String) {
        if (_pairingState.value != PairingState.PAIRED || registeredBackendId == null) {
            return
        }
        val frame = buildJsonObject {
            put("type", "message")
            put("to", registeredBackendId)
            put("content", text)
        }
        send(frame.toString())
    }

    fun sendAudio(audioData: ByteArray) {
        if (_pairingState.value != PairingState.PAIRED || registeredBackendId == null) return
        val base64Audio = Base64.encode(audioData)
        val frame = buildJsonObject {
            put("type", "message")
            put("to", registeredBackendId)
            put("content", base64Audio)
            put("content_type", "audio")
        }
        send(frame.toString())
    }

    fun unpair() {
        if (registeredBackendId == null) return
        val frame = buildJsonObject {
            put("type", "unpair")
            put("target_id", registeredBackendId)
        }
        send(frame.toString())
        registeredBackendId = null
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
        send(frame.toString())
    }

    private fun send(text: String) {
        scope.launch {
            webSocketSession?.send(Frame.Text(text))
        }
    }

    private fun handleMessage(text: String) {
        try {
            val json = Json.parseToJsonElement(text)
            val obj = json as? kotlinx.serialization.json.JsonObject ?: return
            val type = obj["type"]?.jsonPrimitive?.content ?: return

            when (type) {
                "registered" -> {
                    val success = obj["success"]?.jsonPrimitive?.content?.toBoolean() ?: false
                    if (success) {
                        _connectionState.value = ConnectionState.REGISTERED
                        offerEvent(WsMessageEvent.Registered(deviceId))
                    }
                }
                "pair_response" -> {
                    val approve = obj["approve"]?.jsonPrimitive?.content?.toBoolean() ?: false
                    val backendId = obj["backend_id"]?.jsonPrimitive?.content ?: ""
                    val backendLabel = obj["backend_label"]?.jsonPrimitive?.content ?: backendId
                    if (approve) {
                        registeredBackendId = backendId
                        _pairingState.value = PairingState.PAIRED
                        offerEvent(WsMessageEvent.Paired(backendId, backendLabel))
                    } else {
                        _pairingState.value = PairingState.UNPAIRED
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
                    offerEvent(WsMessageEvent.NewMessage(ChatMessage(content, ts, "assistant")))
                }
                "pong" -> {}
                "unpaired" -> {
                    val targetId = obj["target_id"]?.jsonPrimitive?.content ?: ""
                    if (targetId == registeredBackendId) {
                        registeredBackendId = null
                        _pairingState.value = PairingState.UNPAIRED
                        offerEvent(WsMessageEvent.Unpaired)
                    }
                }
                "error" -> {
                    val code = obj["code"]?.jsonPrimitive?.content ?: "unknown"
                    val msg = obj["message"]?.jsonPrimitive?.content ?: "未知错误"
                    offerEvent(
                        WsMessageEvent.NewMessage(
                            ChatMessage("错误 ($code): $msg", timestamp(), "assistant")
                        )
                    )
                }
            }
        } catch (e: Exception) {
            // Log error
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
}

/**
 * Platform-specific Base64 encoding
 */
expect fun Base64.encode(data: ByteArray): String
