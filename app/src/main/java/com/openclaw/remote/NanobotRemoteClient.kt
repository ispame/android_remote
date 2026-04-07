package com.openclaw.remote

import android.os.Build
import android.util.Base64
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import org.json.JSONObject

class NanobotRemoteClient(
    private val settings: RemoteSettings,
    private val callbacks: RemoteClientCallbacks,
) : RemoteClient {
    override val supportsStreamingAudio: Boolean = true

    private val client = OkHttpClient()
    private var webSocket: WebSocket? = null
    private var manualDisconnect = false
    private var isStreamingAudio = false
    private var chunkSeq = 0

    override fun connect() {
        manualDisconnect = false
        callbacks.onError(null)
        callbacks.onStatusChanged(false, "正在连接 Nanobot…")

        val request = Request.Builder()
            .url(buildWebSocketUrl())
            .build()

        webSocket = client.newWebSocket(request, object : WebSocketListener() {
            override fun onOpen(webSocket: WebSocket, response: Response) {
                callbacks.onStatusChanged(true, "已连接到 Nanobot")
            }

            override fun onMessage(webSocket: WebSocket, text: String) {
                handleMessage(text)
            }

            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                callbacks.onError("Nanobot 连接失败: ${t.message ?: "未知错误"}")
                callbacks.onStatusChanged(false, "Nanobot 连接失败")
            }

            override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                if (!manualDisconnect) {
                    callbacks.onStatusChanged(false, "Nanobot 已断开连接")
                }
            }
        })
    }

    override fun disconnect() {
        manualDisconnect = true
        webSocket?.close(1000, "User disconnect")
        webSocket = null
        callbacks.onStatusChanged(false, "已断开连接")
    }

    override fun sendText(text: String) {
        val json = JSONObject().apply {
            put("type", "text")
            put("content", text)
            put("sender_id", senderId())
        }
        if (sendJson(json)) {
            callbacks.onMessage(ChatRole.USER, text)
        }
    }

    override fun startAudioStream() {
        isStreamingAudio = true
        chunkSeq = 0
        val json = JSONObject().apply {
            put("type", "audio_start")
            put("sender_id", senderId())
        }
        sendJson(json)
    }

    override fun sendAudioChunk(chunk: ByteArray, isLast: Boolean) {
        if (!isStreamingAudio) {
            return
        }
        chunkSeq += 1
        val json = JSONObject().apply {
            put("type", "audio_chunk")
            put("seq", chunkSeq)
            put("data", Base64.encodeToString(chunk, Base64.NO_WRAP))
            put("is_last", isLast)
            put("sender_id", senderId())
        }
        sendJson(json)
    }

    override fun endAudioStream() {
        isStreamingAudio = false
        val json = JSONObject().apply {
            put("type", "audio_end")
            put("sender_id", senderId())
        }
        sendJson(json)
    }

    private fun handleMessage(text: String) {
        val json = JSONObject(text)
        when (json.optString("type")) {
            "message" -> {
                val content = json.optString("content").trim()
                if (content.isNotEmpty()) {
                    callbacks.onMessage(ChatRole.ASSISTANT, content)
                }
            }

            "status" -> {
                if (json.optString("status") == "error") {
                    callbacks.onError(json.optString("message").ifBlank { "Nanobot 返回错误" })
                }
            }

            "asr_partial" -> {
                callbacks.onAsrPartial(json.optString("content", ""))
            }

            "asr_done" -> {
                callbacks.onAsrDone()
            }
        }
    }

    private fun sendJson(json: JSONObject): Boolean {
        val sent = webSocket?.send(json.toString()) == true
        if (!sent) {
            callbacks.onError("消息发送失败，当前连接不可用")
        }
        return sent
    }

    private fun buildWebSocketUrl(): String {
        val scheme = if (settings.useTls) "wss" else "ws"
        val port = settings.resolvedPort() ?: defaultPortFor(BackendKind.NANOBOT).toInt()
        return "$scheme://${formatHostAuthority(settings.host)}:$port${settings.effectiveNanobotPath()}"
    }

    private fun senderId(): String {
        return "android_${Build.MODEL}"
    }
}
