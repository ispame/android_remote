package com.openclaw.remote

import android.util.Base64
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import okhttp3.*
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.*

enum class ConnectionState { CONNECTING, CONNECTED, DISCONNECTED }

class WebSocketManager(private val host: String, private val port: Int) {
    private var webSocket: WebSocket? = null
    private val client = OkHttpClient()

    private val _messages = MutableStateFlow<List<ChatMessage>>(emptyList())
    val messages: StateFlow<List<ChatMessage>> = _messages

    private val _connectionState = MutableStateFlow(ConnectionState.DISCONNECTED)
    val connectionState: StateFlow<ConnectionState> = _connectionState

    fun connect() {
        _connectionState.value = ConnectionState.CONNECTING
        val request = Request.Builder()
            .url("ws://$host:$port/ws")
            .build()

        webSocket = client.newWebSocket(request, object : WebSocketListener() {
            override fun onOpen(webSocket: WebSocket, response: Response) {
                _connectionState.value = ConnectionState.CONNECTED
            }

            override fun onMessage(webSocket: WebSocket, text: String) {
                handleMessage(text)
            }

            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                _connectionState.value = ConnectionState.DISCONNECTED
                addMessage("连接失败: ${t.message}", senderId = "assistant")
            }

            override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                _connectionState.value = ConnectionState.DISCONNECTED
            }
        })
    }

    fun sendText(text: String) {
        val json = JSONObject().apply {
            put("type", "text")
            put("content", text)
            put("sender_id", "user")
        }
        webSocket?.send(json.toString())
        // 添加用户消息，不含前缀
        addMessage(text, senderId = "user")
    }

    fun sendAudio(audioData: ByteArray) {
        val base64Audio = Base64.encodeToString(audioData, Base64.NO_WRAP)
        val json = JSONObject().apply {
            put("type", "audio")
            put("audio_data", base64Audio)
            put("sender_id", "user")
        }
        webSocket?.send(json.toString())
        addMessage("发送语音...", senderId = "user")
    }

    private fun handleMessage(text: String) {
        val json = JSONObject(text)
        val type = json.optString("type")

        when (type) {
            "message" -> {
                val content = json.optString("content")
                addMessage(content, senderId = "assistant")
            }
            "status" -> {
                val status = json.optString("status")
                if (status == "error") {
                    addMessage("错误: ${json.optString("message")}", senderId = "assistant")
                }
            }
        }
    }

    private fun addMessage(content: String, senderId: String) {
        val timestamp = SimpleDateFormat("HH:mm", Locale.getDefault()).format(Date())
        val newMessage = ChatMessage(content, timestamp, senderId)
        _messages.value = _messages.value + newMessage
    }

    fun disconnect() {
        webSocket?.close(1000, "User disconnect")
    }
}
