package com.openclaw.remote.viewmodel

import com.openclaw.remote.data.AgentAvailabilityStatus
import com.openclaw.remote.data.AgentProfile
import com.openclaw.remote.data.AgentProfilesState
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

    private val _profiles = MutableStateFlow<List<AgentProfile>>(emptyList())
    val profiles: StateFlow<List<AgentProfile>> = _profiles.asStateFlow()

    private val _selectedProfileId = MutableStateFlow("")
    val selectedProfileId: StateFlow<String> = _selectedProfileId.asStateFlow()

    private val _unreadCounts = MutableStateFlow<Map<String, Int>>(emptyMap())
    val unreadCounts: StateFlow<Map<String, Int>> = _unreadCounts.asStateFlow()

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
    private val profileStates = mutableMapOf<String, ChatProfileRuntimeState>()

    init {
        viewModelScope.launch {
            settingsManager.profilesFlow.collect { state ->
                applyProfilesState(state)
            }
        }
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

    private fun applyProfilesState(state: AgentProfilesState) {
        val previousSelectedId = _selectedProfileId.value
        if (previousSelectedId.isNotBlank() && previousSelectedId != state.selectedProfileId) {
            persistActiveRuntimeState(previousSelectedId)
        }

        val knownIds = state.profiles.map { it.id }.toSet()
        profileStates.keys.retainAll(knownIds)
        state.profiles.forEach { profile ->
            val existing = profileStates[profile.id]
            if (existing == null) {
                profileStates[profile.id] = ChatProfileRuntimeState.fromProfile(profile)
            } else {
                profileStates[profile.id] = existing.withProfilePairing(profile)
            }
        }

        _profiles.value = state.profiles
        _selectedProfileId.value = state.selectedProfileId
        _unreadCounts.value = _unreadCounts.value.filterKeys { it in knownIds } +
            knownIds.associateWith { _unreadCounts.value[it] ?: 0 }

        if (previousSelectedId != state.selectedProfileId) {
            loadRuntimeState(state.selectedProfileId)
        }
    }

    private fun reconnect(config: GatewayConfig, deviceId: String, connectionKey: ChatConnectionKey) {
        if (_selectedProfileId.value.isNotBlank()) {
            persistActiveRuntimeState(_selectedProfileId.value)
        }
        activeManagerJobs.forEach { it.cancel() }
        activeManagerJobs = emptyList()
        wsManager?.disconnect()
        activeConnectionKey = connectionKey
        if (config.profileId.isNotBlank()) {
            _selectedProfileId.value = config.profileId
            loadRuntimeState(config.profileId)
        }

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
                            val profileId = resolveProfileIdForBackendId(
                                profiles = _profiles.value,
                                backendId = event.backendId,
                                activeProfileId = _selectedProfileId.value,
                            ) ?: return@collect
                            updateProfileState(profileId) { state ->
                                state.copy(
                                    registeredBackendId = event.backendId,
                                    pairedBackendLabel = event.backendLabel,
                                    pairingState = PairingState.PAIRED,
                                )
                            }
                            if (profileId == _selectedProfileId.value) {
                                _pairedBackendLabel.value = event.backendLabel
                            }
                            viewModelScope.launch {
                                settingsManager.updatePairedBackend(event.backendId, event.backendLabel, profileId)
                            }
                            if (profileId == _selectedProfileId.value) {
                                requestAutoHistorySync()
                            }
                        }
                        is WsMessageEvent.NewMessage -> {
                            val displayMessage = event.message.sanitizedForDisplay() ?: return@collect
                            val profileId = resolveProfileIdForBackendId(
                                profiles = _profiles.value,
                                backendId = event.backendId,
                                activeProfileId = _selectedProfileId.value,
                            ) ?: return@collect
                            appendMessageToProfile(profileId, displayMessage)
                        }
                        is WsMessageEvent.HistoryResponse -> {
                            val profileId = resolveProfileIdForBackendId(
                                profiles = _profiles.value,
                                backendId = event.backendId,
                                activeProfileId = _selectedProfileId.value,
                            ) ?: return@collect
                            val currentState = profileStates[profileId] ?: ChatProfileRuntimeState()
                            if (!event.error.isNullOrBlank()) {
                                updateProfileState(profileId) {
                                    currentState.copy(isLoadingHistory = false, hasMoreHistory = false)
                                }
                                return@collect
                            }
                            val mergeResult = mergeHistoryMessages(
                                existingMessages = currentState.messages,
                                loadedHistoryKeys = currentState.loadedHistoryKeys,
                                incomingMessages = event.messages,
                            )
                            updateProfileState(profileId) {
                                currentState.copy(
                                    messages = mergeResult.messages,
                                    loadedHistoryKeys = mergeResult.loadedHistoryKeys,
                                    isLoadingHistory = false,
                                    hasMoreHistory = event.hasMore,
                                )
                            }
                        }
                        is WsMessageEvent.AsrResult -> {
                            val profileId = profileIdForClientMessage(event.clientMessageId) ?: return@collect
                            val currentState = profileStates[profileId] ?: ChatProfileRuntimeState()
                            if (!event.success && event.clientMessageId != null && event.error in hiddenAsrErrors) {
                                updateProfileState(profileId) {
                                    currentState.copy(
                                        messages = currentState.messages.filter { message ->
                                            message.clientMessageId != event.clientMessageId
                                        }
                                    )
                                }
                                return@collect
                            }
                            val updatedMessages = currentState.messages.map { message ->
                                if (event.clientMessageId != null && message.clientMessageId == event.clientMessageId) {
                                    message.copy(
                                        content = if (event.success) event.text.orEmpty() else "语音识别失败: ${event.error ?: "unknown"}",
                                        status = if (event.success) MessageStatus.DELIVERED else MessageStatus.FAILED,
                                    )
                                } else {
                                    message
                                }
                            }
                            updateProfileState(profileId) { currentState.copy(messages = updatedMessages) }
                        }
                        is WsMessageEvent.Unpaired -> {
                            val profileId = resolveProfileIdForBackendId(
                                profiles = _profiles.value,
                                backendId = event.backendId,
                                activeProfileId = _selectedProfileId.value,
                            ) ?: return@collect
                            updateProfileState(profileId) { state ->
                                state.copy(
                                    registeredBackendId = null,
                                    pairedBackendLabel = null,
                                    pairingState = PairingState.UNPAIRED,
                                    loadedHistoryKeys = emptySet(),
                                )
                            }
                            viewModelScope.launch {
                                settingsManager.updatePairedBackend(null, null, profileId)
                            }
                            appendMessageToProfile(
                                profileId,
                                ChatMessage(
                                    "已解除配对",
                                    SimpleDateFormat("HH:mm", Locale.getDefault()).format(Date()),
                                    "assistant"
                                )
                            )
                        }
                        is WsMessageEvent.Error -> {
                            addLocalMessage(
                                "错误 (${event.code}): ${event.message}",
                                "assistant",
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

    fun requestPair(profileId: String, backendId: String) {
        updateProfileState(profileId) { state ->
            state.copy(pairingState = PairingState.PENDING, pairedBackendLabel = backendId)
        }
        viewModelScope.launch {
            if (profileId != _selectedProfileId.value) {
                settingsManager.selectProfile(profileId)
                delay(1000)
            }
            wsManager?.requestPair(backendId)
        }
    }

    fun selectProfile(profileId: String) {
        persistActiveRuntimeState(_selectedProfileId.value)
        loadRuntimeState(profileId)
        _unreadCounts.value = _unreadCounts.value + (profileId to 0)
        viewModelScope.launch {
            settingsManager.selectProfile(profileId)
        }
    }

    fun pairingStateFor(profile: AgentProfile): PairingState =
        if (profile.id == _selectedProfileId.value) {
            _pairingState.value
        } else {
            profileStates[profile.id]?.pairingState ?: if (profile.isPaired) PairingState.PAIRED else PairingState.UNPAIRED
        }

    fun availabilityStatus(profile: AgentProfile): AgentAvailabilityStatus {
        return agentAvailabilityForStatus(
            hasBackendId = profile.backendId.isNotBlank(),
            pairingState = pairingStateFor(profile),
            connectionState = _connectionState.value,
        )
    }

    fun addLocalMessage(content: String, senderId: String = "assistant") {
        appendMessageToProfile(
            _selectedProfileId.value,
            ChatMessage(
                content,
                SimpleDateFormat("HH:mm", Locale.getDefault()).format(Date()),
                senderId,
            )
        )
    }

    fun sendText(text: String) {
        if (!canSendChatPayload(_pairingState.value, _connectionState.value)) {
            addLocalMessage(
                "请先配对后端 Agent",
                "assistant"
            )
            return
        }
        wsManager?.sendText(text)
    }

    fun sendAudio(audioData: ByteArray) {
        if (!canSendChatPayload(_pairingState.value, _connectionState.value)) {
            addLocalMessage(
                "请先配对后端 Agent",
                "assistant"
            )
            return
        }
        wsManager?.sendAudio(audioData)
    }

    fun loadMoreHistory() {
        _isLoadingHistory.value = true
        updateProfileState(_selectedProfileId.value) { state ->
            state.copy(isLoadingHistory = true)
        }
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

    private fun appendMessageToProfile(profileId: String, message: ChatMessage) {
        if (profileId.isBlank()) {
            _messages.value = _messages.value + message
            return
        }
        val state = profileStates[profileId] ?: ChatProfileRuntimeState()
        val updated = state.copy(messages = state.messages + message)
        profileStates[profileId] = updated
        if (profileId == _selectedProfileId.value) {
            loadRuntimeState(profileId)
        } else if (shouldIncrementUnreadCount(profileId, _selectedProfileId.value, message.senderId)) {
            _unreadCounts.value = _unreadCounts.value + (profileId to ((_unreadCounts.value[profileId] ?: 0) + 1))
        }
    }

    private fun updateProfileState(
        profileId: String,
        transform: (ChatProfileRuntimeState) -> ChatProfileRuntimeState,
    ) {
        if (profileId.isBlank()) return
        val updated = transform(profileStates[profileId] ?: ChatProfileRuntimeState())
        profileStates[profileId] = updated
        if (profileId == _selectedProfileId.value) {
            loadRuntimeState(profileId)
        }
    }

    private fun persistActiveRuntimeState(profileId: String) {
        if (profileId.isBlank()) return
        profileStates[profileId] = ChatProfileRuntimeState(
            registeredBackendId = latestConfig.pairedBackendId,
            pairedBackendLabel = _pairedBackendLabel.value,
            pairingState = _pairingState.value,
            messages = _messages.value,
            isLoadingHistory = _isLoadingHistory.value,
            hasMoreHistory = _hasMoreHistory.value,
            loadedHistoryKeys = loadedHistoryKeys,
        )
    }

    private fun loadRuntimeState(profileId: String) {
        val state = profileStates[profileId] ?: ChatProfileRuntimeState()
        _messages.value = state.messages
        _pairingState.value = state.pairingState
        _pairedBackendLabel.value = state.pairedBackendLabel
        _isLoadingHistory.value = state.isLoadingHistory
        _hasMoreHistory.value = state.hasMoreHistory
        loadedHistoryKeys = state.loadedHistoryKeys
    }

    private fun profileIdForClientMessage(clientMessageId: String?): String? {
        if (clientMessageId == null) return null
        return profileStates.entries.firstOrNull { (_, state) ->
            state.messages.any { it.clientMessageId == clientMessageId }
        }?.key
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
    val profileId: String,
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
        profileId = profileId,
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

internal data class ChatProfileRuntimeState(
    val registeredBackendId: String? = null,
    val pairedBackendLabel: String? = null,
    val pairingState: PairingState = PairingState.UNPAIRED,
    val messages: List<ChatMessage> = emptyList(),
    val isLoadingHistory: Boolean = false,
    val hasMoreHistory: Boolean = true,
    val loadedHistoryKeys: Set<String> = emptySet(),
) {
    fun withProfilePairing(profile: AgentProfile): ChatProfileRuntimeState {
        if (profile.backendId.isBlank()) {
            return copy(
                registeredBackendId = null,
                pairedBackendLabel = null,
                pairingState = PairingState.UNPAIRED,
            )
        }
        if (profile.isPaired || pairingState == PairingState.PAIRED) {
            return copy(
                registeredBackendId = profile.backendId,
                pairedBackendLabel = profile.backendLabel ?: profile.resolvedDisplayName,
                pairingState = PairingState.PAIRED,
            )
        }
        return this
    }

    companion object {
        fun fromProfile(profile: AgentProfile): ChatProfileRuntimeState =
            ChatProfileRuntimeState().withProfilePairing(profile)
    }
}

internal fun resolveProfileIdForBackendId(
    profiles: List<AgentProfile>,
    backendId: String?,
    activeProfileId: String?,
): String? {
    val normalizedBackendId = backendId?.trim().orEmpty()
    if (normalizedBackendId.isNotEmpty()) {
        profiles.firstOrNull { it.backendId == normalizedBackendId }?.let { return it.id }
    }
    return activeProfileId?.takeIf { it.isNotBlank() }
}

internal fun shouldIncrementUnreadCount(
    targetProfileId: String?,
    activeProfileId: String?,
    senderId: String,
): Boolean =
    !targetProfileId.isNullOrBlank() &&
        targetProfileId != activeProfileId &&
        senderId != "user"

internal fun agentAvailabilityForStatus(
    hasBackendId: Boolean,
    pairingState: PairingState,
    connectionState: ConnectionState,
): AgentAvailabilityStatus {
    if (!hasBackendId) return AgentAvailabilityStatus.UNCONFIGURED
    return when (pairingState) {
        PairingState.PENDING -> AgentAvailabilityStatus.PAIRING
        PairingState.UNPAIRED -> AgentAvailabilityStatus.UNPAIRED
        PairingState.PAIRED -> when (connectionState) {
            ConnectionState.PAIRED -> AgentAvailabilityStatus.AVAILABLE
            ConnectionState.CONNECTING, ConnectionState.CONNECTED, ConnectionState.REGISTERED -> AgentAvailabilityStatus.CONNECTING
            ConnectionState.DISCONNECTED -> AgentAvailabilityStatus.OFFLINE
        }
    }
}

internal fun canSendChatPayload(pairingState: PairingState, connectionState: ConnectionState): Boolean =
    pairingState == PairingState.PAIRED && connectionState == ConnectionState.PAIRED
