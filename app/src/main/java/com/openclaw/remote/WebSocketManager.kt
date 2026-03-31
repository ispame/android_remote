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

    // 流式音频状态
    private var isStreamingAudio = false
    private var chunkSeq = 0

    // ASR 实时回调
    var onAsrPartial: ((String) -> Unit)? = null
    var onAsrDone: (() -> Unit)? = null

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

    // ─── 流式音频 API ────────────────────────────────────────────

    /**
     * 开始流式音频: 发送 audio_start 消息
     */
    fun startAudioStream() {
        isStreamingAudio = true
        chunkSeq = 0
        val json = JSONObject().apply {
            put("type", "audio_start")
            put("sender_id", "android_${android.os.Build.MODEL}")
        }
        webSocket?.send(json.toString())
    }

    /**
     * 发送一个音频chunk
     */
    fun sendAudioChunk(chunk: ByteArray, isLast: Boolean = false) {
        if (!isStreamingAudio) return
        chunkSeq++
        val base64Audio = Base64.encodeToString(chunk, Base64.NO_WRAP)
        val json = JSONObject().apply {
            put("type", "audio_chunk")
            put("seq", chunkSeq)
            put("data", base64Audio)
            put("is_last", isLast)
            put("sender_id", "android_${android.os.Build.MODEL}")
        }
        webSocket?.send(json.toString())
    }

    /**
     * 结束流式音频: 发送 audio_end 消息
     */
    fun endAudioStream() {
        isStreamingAudio = false
        val json = JSONObject().apply {
            put("type", "audio_end")
            put("sender_id", "android_${android.os.Build.MODEL}")
        }
        webSocket?.send(json.toString())
    }

    // ─── 消息处理 ────────────────────────────────────────────────

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
            // ASR 实时部分识别结果
            "asr_partial" -> {
                val content = json.optString("content", "")
                onAsrPartial?.invoke(content)
            }
            // ASR 识别完成
            "asr_done" -> {
                onAsrDone?.invoke()
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
