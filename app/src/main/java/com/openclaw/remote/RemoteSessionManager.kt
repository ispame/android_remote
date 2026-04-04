package com.openclaw.remote

import android.content.Context
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

interface RemoteClient {
    val supportsStreamingAudio: Boolean

    fun connect()

    fun disconnect()

    fun sendText(text: String)

    fun startAudioStream()

    fun sendAudioChunk(chunk: ByteArray, isLast: Boolean)

    fun endAudioStream()
}

interface RemoteClientCallbacks {
    fun onStatusChanged(isConnected: Boolean, statusText: String)

    fun onError(errorText: String?)

    fun onMessagesReplaced(messages: List<ChatMessage>)

    fun onMessage(role: ChatRole, content: String, timestampMs: Long = System.currentTimeMillis())

    fun onStreamingTextChanged(text: String?)

    fun onAsrPartial(text: String)

    fun onAsrDone()
}

class RemoteSessionManager(
    context: Context,
    private val settingsStore: SettingsStore,
) : RemoteClientCallbacks {
    private val appContext = context.applicationContext
    private var client: RemoteClient? = null

    private val _settings = MutableStateFlow(settingsStore.load())
    val settings: StateFlow<RemoteSettings> = _settings.asStateFlow()

    private val _messages = MutableStateFlow<List<ChatMessage>>(emptyList())
    val messages: StateFlow<List<ChatMessage>> = _messages.asStateFlow()

    private val _statusText = MutableStateFlow("尚未连接")
    val statusText: StateFlow<String> = _statusText.asStateFlow()

    private val _isConnected = MutableStateFlow(false)
    val isConnected: StateFlow<Boolean> = _isConnected.asStateFlow()

    private val _errorText = MutableStateFlow<String?>(null)
    val errorText: StateFlow<String?> = _errorText.asStateFlow()

    private val _asrPartialText = MutableStateFlow("")
    val asrPartialText: StateFlow<String> = _asrPartialText.asStateFlow()

    private val _streamingAssistantText = MutableStateFlow<String?>(null)
    val streamingAssistantText: StateFlow<String?> = _streamingAssistantText.asStateFlow()

    private val _supportsStreamingAudio = MutableStateFlow(_settings.value.backend == BackendKind.NANOBOT)
    val supportsStreamingAudio: StateFlow<Boolean> = _supportsStreamingAudio.asStateFlow()

    fun updateSettings(transform: (RemoteSettings) -> RemoteSettings) {
        val updated = transform(_settings.value)
        if (updated == _settings.value) {
            return
        }

        _settings.value = updated
        settingsStore.save(updated)
        _supportsStreamingAudio.value = updated.backend == BackendKind.NANOBOT

        if (client != null) {
            client?.disconnect()
            client = null
            _isConnected.value = false
            _statusText.value = "配置已更改，请重新连接"
            _streamingAssistantText.value = null
            _asrPartialText.value = ""
        }
    }

    fun connect() {
        val currentSettings = _settings.value
        val host = currentSettings.host.trim()
        val port = currentSettings.resolvedPort()

        if (host.isEmpty()) {
            _errorText.value = "请先填写服务器地址"
            return
        }
        if (port == null) {
            _errorText.value = "端口必须在 1-65535 之间"
            return
        }

        _errorText.value = null
        _asrPartialText.value = ""
        _streamingAssistantText.value = null
        _messages.value = emptyList()

        client?.disconnect()
        client = when (currentSettings.backend) {
            BackendKind.NANOBOT -> NanobotRemoteClient(currentSettings, this)
            BackendKind.OPENCLAW -> OpenClawGatewayClient(appContext, currentSettings, this)
        }
        _supportsStreamingAudio.value = client?.supportsStreamingAudio == true
        client?.connect()
    }

    fun disconnect() {
        client?.disconnect()
        client = null
        _isConnected.value = false
        _statusText.value = "已断开连接"
        _streamingAssistantText.value = null
        _asrPartialText.value = ""
    }

    fun sendText(text: String) {
        val trimmed = text.trim()
        if (trimmed.isEmpty()) {
            return
        }
        if (client == null) {
            _errorText.value = "请先连接服务器"
            return
        }
        _errorText.value = null
        client?.sendText(trimmed)
    }

    fun startAudioStream(): Boolean {
        if (client == null) {
            _errorText.value = "请先连接服务器"
            return false
        }
        if (!_supportsStreamingAudio.value) {
            _errorText.value = "当前后端不支持这套语音流协议"
            return false
        }
        _errorText.value = null
        client?.startAudioStream()
        return true
    }

    fun sendAudioChunk(chunk: ByteArray, isLast: Boolean) {
        client?.sendAudioChunk(chunk, isLast)
    }

    fun endAudioStream() {
        client?.endAudioStream()
        _asrPartialText.value = ""
    }

    override fun onStatusChanged(isConnected: Boolean, statusText: String) {
        _isConnected.value = isConnected
        _statusText.value = statusText
    }

    override fun onError(errorText: String?) {
        _errorText.value = errorText
    }

    override fun onMessagesReplaced(messages: List<ChatMessage>) {
        _messages.value = messages
    }

    override fun onMessage(role: ChatRole, content: String, timestampMs: Long) {
        _messages.value = _messages.value + ChatMessage(
            role = role,
            content = content,
            timestampMs = timestampMs,
        )
    }

    override fun onStreamingTextChanged(text: String?) {
        _streamingAssistantText.value = text
    }

    override fun onAsrPartial(text: String) {
        _asrPartialText.value = text
    }

    override fun onAsrDone() {
        _asrPartialText.value = ""
    }
}
