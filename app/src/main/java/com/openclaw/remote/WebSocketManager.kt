package com.openclaw.remote

import android.util.Base64
import kotlinx.coroutines.*
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import okhttp3.*
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Connection states for WebSocket connection to Gateway.
 */
enum class ConnectionState {
    DISCONNECTED,    // 未连接
    CONNECTING,      // 连接中
    CONNECTED,       // 已连接（未注册）
    REGISTERED,      // 已注册（未配对）
    PAIRED,          // 已配对
}

/**
 * Pairing states for app ↔ backend pairing.
 */
enum class PairingState {
    UNPAIRED,    // 未配对
    PENDING,     // 配对请求已发送，等待响应
    PAIRED,      // 配对成功
}

/**
 * WebSocket Manager for Phase 3 Gateway Router protocol.
 * App connects to Gateway, then pairs with an OpenClaw backend via QR scan.
 */
class WebSocketManager(
    private val wsUrl: String,
    private val deviceId: String,
    private val deviceLabel: String,
) {
    private var webSocket: WebSocket? = null
    private val client = OkHttpClient()
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

        val finalUrl = if (wsUrl.endsWith("/ws")) wsUrl else "$wsUrl/ws"
        val request = Request.Builder().url(finalUrl).build()

        webSocket = client.newWebSocket(request, object : WebSocketListener() {
            override fun onOpen(webSocket: WebSocket, response: Response) {
                _connectionState.value = ConnectionState.CONNECTED
                sendRegister()
            }

            override fun onMessage(webSocket: WebSocket, text: String) {
                handleMessage(text)
            }

            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                _connectionState.value = ConnectionState.DISCONNECTED
                _pairingState.value = PairingState.UNPAIRED
                offerEvent(
                    WsMessageEvent.NewMessage(
                        ChatMessage("连接失败: ${t.message}", timestamp(), "assistant")
                    )
                )
            }

            override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                _connectionState.value = ConnectionState.DISCONNECTED
                _pairingState.value = PairingState.UNPAIRED
            }
        })
    }

    fun disconnect() {
        webSocket?.close(1000, "User disconnect")
        webSocket = null
        _connectionState.value = ConnectionState.DISCONNECTED
        _pairingState.value = PairingState.UNPAIRED
    }

    /**
     * Request pairing with a backend by its agentId.
     * Must be called after connected + registered.
     */
    fun requestPair(backendId: String) {
        if (_connectionState.value != ConnectionState.REGISTERED) {
            android.util.Log.w("WebSocketManager", "Cannot pair: not registered yet")
            return
        }
        _pairingState.value = PairingState.PENDING
        val frame = JSONObject().apply {
            put("type", "pair_request")
            put("target_backend_id", backendId)
        }
        send(frame)
    }

    /**
     * Cancel current pending pair request.
     */
    fun cancelPair() {
        _pairingState.value = PairingState.UNPAIRED
    }

    /**
     * Send text message to the paired backend.
     */
    fun sendText(text: String) {
        if (_pairingState.value != PairingState.PAIRED || registeredBackendId == null) {
            android.util.Log.w("WebSocketManager", "Cannot send: not paired")
            return
        }
        val frame = JSONObject().apply {
            put("type", "message")
            put("to", registeredBackendId)
            put("content", text)
        }
        send(frame)
    }

    /**
     * Send audio data to the paired backend.
     */
    fun sendAudio(audioData: ByteArray) {
        if (_pairingState.value != PairingState.PAIRED || registeredBackendId == null) return
        val base64Audio = Base64.encodeToString(audioData, Base64.NO_WRAP)
        val frame = JSONObject().apply {
            put("type", "message")
            put("to", registeredBackendId)
            put("content", base64Audio)
            put("content_type", "audio")
        }
        send(frame)
    }

    /**
     * Unpair from the current backend.
     */
    fun unpair() {
        if (registeredBackendId == null) return
        val frame = JSONObject().apply {
            put("type", "unpair")
            put("target_id", registeredBackendId)
        }
        send(frame)
        registeredBackendId = null
        _pairingState.value = PairingState.UNPAIRED
    }

    private fun sendRegister() {
        val frame = JSONObject().apply {
            put("type", "register")
            put("client_type", "app")
            put("client_id", deviceId)
            put("label", deviceLabel)
        }
        send(frame)
    }

    private fun send(json: JSONObject) {
        android.util.Log.d("WebSocketManager", "Sending: ${json}")
        webSocket?.send(json.toString())
    }

    private fun handleMessage(text: String) {
        try {
            val json = JSONObject(text)
            val type = json.optString("type")
            android.util.Log.d("WebSocketManager", "Received: $type")

            when (type) {
                "registered" -> {
                    val success = json.optBoolean("success", false)
                    if (success) {
                        _connectionState.value = ConnectionState.REGISTERED
                        offerEvent(WsMessageEvent.Registered(deviceId))
                    }
                }

                "pair_response" -> {
                    val approve = json.optBoolean("approve", false)
                    val backendId = json.optString("backend_id")
                    val backendLabel = json.optString("backend_label", backendId)
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
                    val content = json.optString("content")
                    val ts = json.optString("timestamp", timestamp())
                    offerEvent(WsMessageEvent.NewMessage(ChatMessage(content, ts, "assistant")))
                }

                "pong" -> {
                    // Heartbeat response, ignore
                }

                "unpaired" -> {
                    val targetId = json.optString("target_id")
                    if (targetId == registeredBackendId) {
                        registeredBackendId = null
                        _pairingState.value = PairingState.UNPAIRED
                        offerEvent(WsMessageEvent.Unpaired)
                    }
                }

                "error" -> {
                    val code = json.optString("code", "unknown")
                    val msg = json.optString("message", "未知错误")
                    offerEvent(
                        WsMessageEvent.NewMessage(
                            ChatMessage("错误 ($code): $msg", timestamp(), "assistant")
                        )
                    )
                }
            }
        } catch (e: Exception) {
            android.util.Log.e("WebSocketManager", "Error parsing message: ${e.message}")
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

// WebSocket message events
sealed class WsMessageEvent {
    data class Registered(val deviceId: String) : WsMessageEvent()
    data class Paired(val backendId: String, val backendLabel: String) : WsMessageEvent()
    data class NewMessage(val message: ChatMessage) : WsMessageEvent()
    object Unpaired : WsMessageEvent()
    data class Error(val code: String, val message: String) : WsMessageEvent()
}
