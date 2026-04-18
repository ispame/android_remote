package com.openclaw.remote.viewmodel

import com.openclaw.remote.data.ChatMessage
import com.openclaw.remote.data.GatewayConfig
import com.openclaw.remote.data.SettingsManager
import com.openclaw.remote.domain.ConnectionState
import com.openclaw.remote.domain.PairingState
import com.openclaw.remote.network.WebSocketManager
import com.openclaw.remote.network.WsMessageEvent
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*
import java.text.SimpleDateFormat
import java.util.*

/**
 * Chat ViewModel - shared across platforms.
 * Note: This is a base implementation. Platform-specific wrappers handle lifecycle.
 */
class ChatViewModel(
    private val settingsManager: SettingsManager
) {
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
    private val viewModelScope = CoroutineScope(Dispatchers.Main + SupervisorJob())

    init {
        viewModelScope.launch {
            settingsManager.configFlow.collect { config ->
                reconnect(config)
            }
        }
    }

    private fun reconnect(config: GatewayConfig) {
        wsManager?.disconnect()

        val deviceId = config.deviceId.ifEmpty {
            "device_${UUID.randomUUID().toString().take(8)}"
        }

        viewModelScope.launch {
            if (config.deviceId.isEmpty()) {
                settingsManager.updateDeviceId(deviceId)
            }
        }

        if (config.pairedBackendId != null) {
            _pairedBackendLabel.value = config.pairedBackendLabel
        }

        wsManager = WebSocketManager(
            wsUrl = config.gatewayUrl,
            deviceId = deviceId,
            deviceLabel = config.deviceLabel.ifEmpty { "我的设备" },
            token = config.token,
        )

        viewModelScope.launch {
            wsManager!!.connectionState.collect { _connectionState.value = it }
        }

        viewModelScope.launch {
            wsManager!!.pairingState.collect { state ->
                _pairingState.value = state
                if (state != PairingState.PAIRED) {
                    _pairedBackendLabel.value = null
                }
            }
        }

        viewModelScope.launch {
            wsManager!!.messageChannel.receiveAsFlow().collect { event ->
                when (event) {
                    is WsMessageEvent.Registered -> {
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

        wsManager?.connect()
    }

    fun connect() {
        viewModelScope.launch {
            val config = settingsManager.configFlow.first()
            reconnect(config)
        }
    }

    fun requestPair(backendId: String) {
        wsManager?.requestPair(backendId)
    }

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

    fun sendAudio(audioData: ByteArray) {
        if (_pairingState.value != PairingState.PAIRED) return
        val ts = SimpleDateFormat("HH:mm", Locale.getDefault()).format(Date())
        _messages.value = _messages.value + ChatMessage("发送语音...", ts, "user")
        wsManager?.sendAudio(audioData)
    }

    fun loadMoreHistory() {
        _isLoadingHistory.value = true
    }

    fun unpair() {
        wsManager?.unpair()
    }

    fun disconnect() {
        wsManager?.disconnect()
    }

    fun onCleared() {
        viewModelScope.cancel()
    }
}
