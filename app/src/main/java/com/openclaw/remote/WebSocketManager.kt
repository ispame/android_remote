package com.openclaw.remote

import android.util.Base64
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import okhttp3.*
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.*

class WebSocketManager(private val host: String, private val port: Int) {
    private var webSocket: WebSocket? = null
    private val client = OkHttpClient()

    private val _messages = MutableStateFlow<List<ChatMessage>>(emptyList())
    val messages: StateFlow<List<ChatMessage>> = _messages

    fun connect() {
        val request = Request.Builder()
            .url("ws://$host:$port/ws")
            .build()

        webSocket = client.newWebSocket(request, object : WebSocketListener() {
            override fun onMessage(webSocket: WebSocket, text: String) {
                handleMessage(text)
            }

            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                addMessage("连接失败: ${t.message}")
            }
        })
    }

    fun sendText(text: String) {
        val json = JSONObject().apply {
            put("type", "text")
            put("content", text)
            put("sender_id", "android_${android.os.Build.MODEL}")
        }
        webSocket?.send(json.toString())
        addMessage("我: $text")
    }

    fun sendAudio(audioData: ByteArray) {
        val base64Audio = Base64.encodeToString(audioData, Base64.NO_WRAP)
        val json = JSONObject().apply {
            put("type", "audio")
            put("audio_data", base64Audio)
            put("sender_id", "android_${android.os.Build.MODEL}")
        }
        webSocket?.send(json.toString())
        addMessage("发送语音...")
    }

    private fun handleMessage(text: String) {
        val json = JSONObject(text)
        val type = json.optString("type")

        when (type) {
            "message" -> {
                val content = json.optString("content")
                addMessage("机器人: $content")
            }
            "status" -> {
                val status = json.optString("status")
                if (status == "error") {
                    addMessage("错误: ${json.optString("message")}")
                }
            }
        }
    }

    private fun addMessage(content: String) {
        val timestamp = SimpleDateFormat("HH:mm:ss", Locale.getDefault()).format(Date())
        val newMessage = ChatMessage(content, timestamp)
        _messages.value = _messages.value + newMessage
    }

    fun disconnect() {
        webSocket?.close(1000, "User disconnect")
    }
}
