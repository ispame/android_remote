package com.openclaw.remote.viewmodel

import com.openclaw.remote.data.ChatMessage
import com.openclaw.remote.data.GatewayConfig
import com.openclaw.remote.data.MessageStatus
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
    private var lastAutoHistoryRequestAt = 0L
    private var generatedDeviceId: String? = null
    private var activeConnectionKey: ChatConnectionKey? = null
    private var activeManagerJobs: List<Job> = emptyList()
    private var latestConfig = GatewayConfig()
    private var loadedHistoryKeys = emptySet<String>()

    init {
        viewModelScope.launch {
            settingsManager.configFlow.collect { config ->
                latestConfig = config
                reconnectIfNeeded(config)
            }
        }
    }

    private fun reconnectIfNeeded(config: GatewayConfig, force: Boolean = false) {
        val deviceId = effectiveDeviceId(config)
        val nextConnectionKey = config.toChatConnectionKey(deviceId)
        if (!force && !shouldReconnectForConfig(activeConnectionKey, nextConnectionKey)) {
            return
        }
        reconnect(config, deviceId, nextConnectionKey)
    }

    private fun effectiveDeviceId(config: GatewayConfig): String {
        if (config.deviceId.isNotEmpty()) return config.deviceId
        val deviceId = generatedDeviceId ?: "device_${UUID.randomUUID().toString().take(8)}"
            .also { generatedDeviceId = it }
        viewModelScope.launch {
            settingsManager.updateDeviceId(deviceId)
        }
        return deviceId
    }

    private fun reconnect(config: GatewayConfig, deviceId: String, connectionKey: ChatConnectionKey) {
        activeManagerJobs.forEach { it.cancel() }
        activeManagerJobs = emptyList()
        wsManager?.disconnect()
        activeConnectionKey = connectionKey

        val configuredBackendLabel = config.pairedBackendLabel ?: config.pairedBackendId
        if (configuredBackendLabel != null) {
            _pairedBackendLabel.value = configuredBackendLabel
        }

        wsManager = WebSocketManager(
            wsUrl = config.gatewayUrl,
            deviceId = deviceId,
            deviceLabel = config.deviceLabel.ifEmpty { "我的设备" },
            token = config.token,
            preferredBackendId = config.pairedBackendId,
            asrMode = config.asrMode,
            asrProfileId = config.asrProfileId,
        )
        val manager = wsManager!!

        activeManagerJobs = listOf(
            viewModelScope.launch {
                manager.connectionState.collect { _connectionState.value = it }
            },
            viewModelScope.launch {
                manager.pairingState.collect { state ->
                    _pairingState.value = state
                    when {
                        state == PairingState.PENDING && configuredBackendLabel != null -> {
                            _pairedBackendLabel.value = configuredBackendLabel
                        }
                        state != PairingState.PAIRED -> {
                            _pairedBackendLabel.value = null
                        }
                    }
                }
            },
            viewModelScope.launch {
                manager.messageChannel.receiveAsFlow().collect { event ->
                    when (event) {
                        is WsMessageEvent.Registered -> Unit
                        is WsMessageEvent.Paired -> {
                            _pairedBackendLabel.value = event.backendLabel
                            if (shouldPersistPairedBackend(latestConfig, event.backendId, event.backendLabel)) {
                                latestConfig = latestConfig.copy(
                                    pairedBackendId = event.backendId,
                                    pairedBackendLabel = event.backendLabel,
                                )
                                viewModelScope.launch {
                                    settingsManager.updatePairedBackend(event.backendId, event.backendLabel)
                                }
                            }
                            requestAutoHistorySync()
                        }
                        is WsMessageEvent.NewMessage -> {
                            val displayMessage = event.message.sanitizedForDisplay() ?: return@collect
                            _messages.value = _messages.value + displayMessage
                        }
                        is WsMessageEvent.HistoryResponse -> {
                            _isLoadingHistory.value = false
                            if (!event.error.isNullOrBlank()) {
                                _hasMoreHistory.value = false
                                return@collect
                            }
                            val mergeResult = mergeHistoryMessages(
                                existingMessages = _messages.value,
                                loadedHistoryKeys = loadedHistoryKeys,
                                incomingMessages = event.messages,
                            )
                            _messages.value = mergeResult.messages
                            loadedHistoryKeys = mergeResult.loadedHistoryKeys
                            _hasMoreHistory.value = event.hasMore
                        }
                        is WsMessageEvent.AsrResult -> {
                            if (!event.success && event.clientMessageId != null && event.error in hiddenAsrErrors) {
                                _messages.value = _messages.value.filter { message ->
                                    message.clientMessageId != event.clientMessageId
                                }
                                return@collect
                            }
                            _messages.value = _messages.value.map { message ->
                                if (event.clientMessageId != null && message.clientMessageId == event.clientMessageId) {
                                    message.copy(
                                        content = if (event.success) event.text.orEmpty() else "语音识别失败: ${event.error ?: "unknown"}",
                                        status = if (event.success) MessageStatus.DELIVERED else MessageStatus.FAILED,
                                    )
                                } else {
                                    message
                                }
                            }
                        }
                        is WsMessageEvent.Unpaired -> {
                            _pairedBackendLabel.value = null
                            loadedHistoryKeys = emptySet()
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
            },
        )

        manager.connect()
    }

    fun connect() {
        viewModelScope.launch {
            wsManager?.let { manager ->
                manager.connect()
                return@launch
            }
            val config = settingsManager.configFlow.first()
            latestConfig = config
            reconnectIfNeeded(config)
        }
    }

    fun requestPair(backendId: String) {
        wsManager?.requestPair(backendId)
    }

    fun sendText(text: String) {
        if (_pairingState.value != PairingState.PAIRED) {
            _messages.value = _messages.value + ChatMessage(
                "请先配对后端 Agent",
                SimpleDateFormat("HH:mm", Locale.getDefault()).format(Date()),
                "assistant"
            )
            return
        }
        wsManager?.sendText(text)
    }

    fun sendAudio(audioData: ByteArray) {
        if (_pairingState.value != PairingState.PAIRED) {
            _messages.value = _messages.value + ChatMessage(
                "请先配对后端 Agent",
                SimpleDateFormat("HH:mm", Locale.getDefault()).format(Date()),
                "assistant"
            )
            return
        }
        wsManager?.sendAudio(audioData)
    }

    fun loadMoreHistory() {
        _isLoadingHistory.value = true
        wsManager?.requestRecentHistory()
    }

    fun unpair() {
        wsManager?.unpair()
    }

    fun disconnect() {
        wsManager?.disconnect()
    }

    fun onCleared() {
        activeManagerJobs.forEach { it.cancel() }
        viewModelScope.cancel()
    }

    private fun requestAutoHistorySync() {
        val now = System.currentTimeMillis()
        if (now - lastAutoHistoryRequestAt < 3000) return
        lastAutoHistoryRequestAt = now
        wsManager?.requestRecentHistory()
    }

    private companion object {
        val hiddenAsrErrors = setOf("ASR_AUDIO_EMPTY", "ASR_EMPTY_TRANSCRIPT")
    }
}

internal data class ChatConnectionKey(
    val gatewayUrl: String,
    val deviceId: String,
    val deviceLabel: String,
    val token: String,
    val pairedBackendId: String?,
    val asrMode: String,
    val asrProfileId: String,
)

internal fun GatewayConfig.toChatConnectionKey(effectiveDeviceId: String): ChatConnectionKey =
    ChatConnectionKey(
        gatewayUrl = gatewayUrl,
        deviceId = effectiveDeviceId,
        deviceLabel = deviceLabel,
        token = token,
        pairedBackendId = pairedBackendId,
        asrMode = asrMode,
        asrProfileId = asrProfileId,
    )

internal fun shouldReconnectForConfig(previous: ChatConnectionKey?, next: ChatConnectionKey): Boolean =
    previous != next

internal fun shouldPersistPairedBackend(config: GatewayConfig, backendId: String?, backendLabel: String?): Boolean =
    config.pairedBackendId != backendId || config.pairedBackendLabel != backendLabel
