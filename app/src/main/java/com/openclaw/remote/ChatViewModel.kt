package com.openclaw.remote

import android.content.Context
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.launch
import java.text.SimpleDateFormat
import java.util.*

class ChatViewModel(
    private val settingsManager: SettingsManager
) : ViewModel() {

    private val _messages = MutableStateFlow<List<ChatMessage>>(emptyList())
    val messages: StateFlow<List<ChatMessage>> = _messages.asStateFlow()

    private val _connectionState = MutableStateFlow(ConnectionState.DISCONNECTED)
    val connectionState: StateFlow<ConnectionState> = _connectionState.asStateFlow()

    private val _pairingState = MutableStateFlow(PairingState.UNPAIRED)
    val pairingState: StateFlow<PairingState> = _pairingState.asStateFlow()

    private val _pairedBackendLabel = MutableStateFlow<String?>(null)
    val pairedBackendLabel: StateFlow<String?> = _pairedBackendLabel.asStateFlow()

    private val _isLoadingHistory = MutableStateFlow(false)
    val isLoadingHistory: StateFlow<Boolean> = _isLoadingHistory.asStateFlow()

    private val _hasMoreHistory = MutableStateFlow(true)
    val hasMoreHistory: StateFlow<Boolean> = _hasMoreHistory.asStateFlow()

    private var wsManager: WebSocketManager? = null

    init {
        // 监听配置变化，重建连接
        viewModelScope.launch {
            settingsManager.configFlow.collect { config ->
                reconnect(config)
            }
        }

        // 监听连接状态
        viewModelScope.launch {
            _connectionState.collect { }
        }

        // 监听配对状态
        viewModelScope.launch {
            _pairingState.collect { }
        }
    }

    private fun reconnect(config: GatewayConfig) {
        wsManager?.disconnect()

        // 生成设备 ID（首次使用随机 ID）
        val deviceId = config.deviceId.ifEmpty {
            "android_${UUID.randomUUID().toString().take(8)}"
        }

        // 保存 deviceId
        viewModelScope.launch {
            if (config.deviceId.isEmpty()) {
                settingsManager.updateDeviceId(deviceId)
            }
        }

        // 加载已保存的配对信息
        if (config.pairedBackendId != null) {
            _pairedBackendLabel.value = config.pairedBackendLabel
        }

        // 创建 WebSocketManager
        wsManager = WebSocketManager(
            wsUrl = config.gatewayUrl,
            deviceId = deviceId,
            deviceLabel = config.deviceLabel.ifEmpty { "我的手机" },
        )

        // 收集连接状态
        viewModelScope.launch {
            wsManager!!.connectionState.collect { _connectionState.value = it }
        }

        // 收集配对状态
        viewModelScope.launch {
            wsManager!!.pairingState.collect { state ->
                _pairingState.value = state
                if (state != PairingState.PAIRED) {
                    _pairedBackendLabel.value = null
                }
            }
        }

        // 收集消息事件
        viewModelScope.launch {
            wsManager!!.messageChannel.receiveAsFlow().collect { event ->
                when (event) {
                    is WsMessageEvent.Registered -> {
                        // 注册成功，检查是否需要自动发起配对
                        config.pairedBackendId?.let { backendId ->
                            wsManager?.requestPair(backendId)
                        }
                    }
                    is WsMessageEvent.Paired -> {
                        _pairedBackendLabel.value = event.backendLabel
                        viewModelScope.launch {
                            settingsManager.updatePairedBackend(event.backendId, event.backendLabel)
                        }
                        _messages.value = _messages.value + ChatMessage(
                            "已成功配对 OpenClaw: ${event.backendLabel}",
                            SimpleDateFormat("HH:mm", Locale.getDefault()).format(Date()),
                            "assistant"
                        )
                    }
                    is WsMessageEvent.NewMessage -> {
                        _messages.value = _messages.value + event.message
                    }
                    is WsMessageEvent.Unpaired -> {
                        _pairedBackendLabel.value = null
                        viewModelScope.launch {
                            settingsManager.updatePairedBackend(null, null)
                        }
                        _messages.value = _messages.value + ChatMessage(
                            "已解除配对",
                            SimpleDateFormat("HH:mm", Locale.getDefault()).format(Date()),
                            "assistant"
                        )
                    }
                    is WsMessageEvent.Error -> {
                        _messages.value = _messages.value + ChatMessage(
                            "错误 (${event.code}): ${event.message}",
                            SimpleDateFormat("HH:mm", Locale.getDefault()).format(Date()),
                            "assistant"
                        )
                    }
                }
            }
        }

        // 发起连接
        wsManager?.connect()
    }

    /**
     * 手动连接（由 UI 触发）
     */
    fun connect() {
        viewModelScope.launch {
            val config = settingsManager.configFlow.first()
            reconnect(config)
        }
    }

    /**
     * 发起配对请求（扫码后调用）
     */
    fun requestPair(backendId: String) {
        wsManager?.requestPair(backendId)
    }

    /**
     * 发送文字消息
     */
    fun sendText(text: String) {
        if (_pairingState.value != PairingState.PAIRED) {
            _messages.value = _messages.value + ChatMessage(
                "请先配对 OpenClaw",
                SimpleDateFormat("HH:mm", Locale.getDefault()).format(Date()),
                "assistant"
            )
            return
        }
        val ts = SimpleDateFormat("HH:mm", Locale.getDefault()).format(Date())
        _messages.value = _messages.value + ChatMessage(text, ts, "user")
        wsManager?.sendText(text)
    }

    /**
     * 发送语音消息
     */
    fun sendAudio(audioData: ByteArray) {
        if (_pairingState.value != PairingState.PAIRED) return
        val ts = SimpleDateFormat("HH:mm", Locale.getDefault()).format(Date())
        _messages.value = _messages.value + ChatMessage("发送语音...", ts, "user")
        wsManager?.sendAudio(audioData)
    }

    /**
     * 加载更多历史消息
     */
    fun loadMoreHistory() {
        _isLoadingHistory.value = true
        // Phase 3: history loading via Gateway (future)
    }

    /**
     * 取消配对
     */
    fun unpair() {
        wsManager?.unpair()
    }

    /**
     * 断开连接
     */
    fun disconnect() {
        wsManager?.disconnect()
    }

    class Factory(private val context: Context) : ViewModelProvider.Factory {
        @Suppress("UNCHECKED_CAST")
        override fun <T : ViewModel> create(modelClass: Class<T>): T {
            return ChatViewModel(SettingsManager(context)) as T
        }
    }
}
