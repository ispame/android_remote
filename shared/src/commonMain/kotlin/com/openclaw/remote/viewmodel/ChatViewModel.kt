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
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
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
    private var activeRouterConnectionState = ConnectionState.DISCONNECTED
    private var latestConfig = GatewayConfig()
    private var loadedHistoryKeys = emptySet<String>()
    private val profileStates = mutableMapOf<String, ChatProfileRuntimeState>()
    private val connectionMutex = Mutex()

    init {
        viewModelScope.launch {
            settingsManager.profilesFlow.collect { state ->
                applyProfilesState(state)
            }
        }
        viewModelScope.launch {
            settingsManager.configFlow.collect { config ->
                latestConfig = config
                connectionMutex.withLock {
                    reconnectIfNeeded(config)
                }
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
        val managerProfileId = connectionKey.profileId

        activeManagerJobs = listOf(
            viewModelScope.launch {
                manager.connectionState.collect { state ->
                    activeRouterConnectionState = state
                    updateProfileState(managerProfileId) { it.copy(connectionState = state) }
                    if (managerProfileId == _selectedProfileId.value) {
                        _connectionState.value = state
                    }
                }
            },
            viewModelScope.launch {
                manager.pairingState.collect { state ->
                    updateProfileState(managerProfileId) { currentState ->
                        currentState.copy(
                            pairingState = state,
                            pairedBackendLabel = when {
                                state == PairingState.PENDING && configuredBackendLabel != null -> configuredBackendLabel
                                state != PairingState.PAIRED -> null
                                else -> currentState.pairedBackendLabel
                            },
                        )
                    }
                    if (managerProfileId == _selectedProfileId.value) {
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
                                activeProfileId = managerProfileId,
                            ) ?: managerProfileId.takeIf { it.isNotBlank() } ?: return@collect
                            updateProfileState(profileId) { state ->
                                state.copy(
                                    registeredBackendId = event.backendId,
                                    pairedBackendLabel = event.backendLabel,
                                    pairingState = PairingState.PAIRED,
                                    connectionState = ConnectionState.PAIRED,
                                )
                            }
                            if (profileId == _selectedProfileId.value) {
                                _pairedBackendLabel.value = event.backendLabel
                            }
                            val selectedProfileAlreadyPersisted = _profiles.value
                                .firstOrNull { it.id == profileId }
                                ?.isPaired == true
                            if (
                                profileId != _selectedProfileId.value ||
                                !selectedProfileAlreadyPersisted ||
                                shouldPersistPairedBackend(latestConfig, event.backendId, event.backendLabel)
                            ) {
                                viewModelScope.launch {
                                    settingsManager.updatePairedBackend(event.backendId, event.backendLabel, profileId)
                                }
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
                                activeProfileId = managerProfileId,
                            ) ?: return@collect
                            appendMessageToProfile(profileId, displayMessage)
                        }
                        is WsMessageEvent.HistoryResponse -> {
                            val profileId = resolveProfileIdForBackendId(
                                profiles = _profiles.value,
                                backendId = event.backendId,
                                activeProfileId = managerProfileId,
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
                                activeProfileId = managerProfileId,
                            ) ?: return@collect
                            updateProfileState(profileId) { state ->
                                state.copy(
                                    registeredBackendId = null,
                                    pairedBackendLabel = null,
                                    pairingState = PairingState.UNPAIRED,
                                    connectionState = ConnectionState.REGISTERED,
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
                            appendMessageToProfile(
                                managerProfileId,
                                ChatMessage(
                                    "错误 (${event.code}): ${event.message}",
                                    SimpleDateFormat("HH:mm", Locale.getDefault()).format(Date()),
                                    "assistant",
                                )
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
            connectionMutex.withLock {
                wsManager?.let { manager ->
                    manager.connect()
                    return@withLock
                }
                val config = settingsManager.configFlow.first()
                latestConfig = config
                reconnectIfNeeded(config)
            }
        }
    }

    fun requestPair(backendId: String) {
        requestPair(_selectedProfileId.value, backendId)
    }

    fun requestPair(profileId: String, backendId: String) {
        val normalizedBackendId = backendId.trim()
        if (profileId.isBlank() || normalizedBackendId.isBlank()) return
        viewModelScope.launch {
            connectionMutex.withLock {
                if (profileId != _selectedProfileId.value) {
                    persistActiveRuntimeState(_selectedProfileId.value)
                    prepareRuntimeStateForSelection(profileId)
                    _selectedProfileId.value = profileId
                    loadRuntimeState(profileId)
                    settingsManager.selectProfile(profileId)
                }
                updateProfileState(profileId) { state ->
                    state.copy(
                        pairingState = PairingState.PENDING,
                        connectionState = ConnectionState.CONNECTING,
                        pairedBackendLabel = normalizedBackendId,
                    )
                }
                val config = settingsManager.configFlow.first { it.profileId == profileId }
                latestConfig = config
                val deviceId = effectiveDeviceId(config)
                val nextConnectionKey = config.toChatConnectionKey(deviceId)
                if (shouldRefreshConnectionForPairRequest(activeConnectionKey, nextConnectionKey)) {
                    reconnect(config, deviceId, nextConnectionKey)
                }
                wsManager?.requestPair(normalizedBackendId)
            }
        }
    }

    fun selectProfile(profileId: String) {
        if (profileId.isBlank()) return
        if (profileId != _selectedProfileId.value) {
            persistActiveRuntimeState(_selectedProfileId.value)
        }
        prepareRuntimeStateForSelection(profileId)
        _selectedProfileId.value = profileId
        loadRuntimeState(profileId)
        _unreadCounts.value = _unreadCounts.value + (profileId to 0)
        viewModelScope.launch {
            settingsManager.selectProfile(profileId)
        }
    }

    fun pairingStateFor(profile: AgentProfile): PairingState =
        if (profile.id == _selectedProfileId.value && activeConnectionKey?.profileId == profile.id) {
            _pairingState.value
        } else {
            profileStates[profile.id]?.pairingState ?: if (profile.isPaired) PairingState.PAIRED else PairingState.UNPAIRED
        }

    fun availabilityStatus(profile: AgentProfile): AgentAvailabilityStatus {
        return agentAvailabilityForStatus(
            hasBackendId = profile.backendId.isNotBlank(),
            pairingState = pairingStateFor(profile),
            connectionState = connectionStateForProfileAvailability(
                profileId = profile.id,
                selectedProfileId = _selectedProfileId.value,
                activeConnectionProfileId = activeConnectionKey?.profileId,
                activeConnectionState = activeRouterConnectionState,
            ),
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
        val route = currentPayloadRouteCheck()
        logPayloadRoute("text", route)
        if (!route.canSend) {
            addLocalMessage(
                "请先配对当前 Agent",
                "assistant"
            )
            return
        }
        wsManager?.sendText(text)
    }

    fun sendAudio(audioData: ByteArray) {
        val route = currentPayloadRouteCheck()
        logPayloadRoute("audio", route)
        if (!route.canSend) {
            addLocalMessage(
                "请先配对当前 Agent",
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
        wsManager?.disconnect()
        wsManager = null
        activeManagerJobs.forEach { it.cancel() }
        activeManagerJobs = emptyList()
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
        val existingState = profileStates[profileId]
        val isManagerForProfile = activeConnectionKey?.profileId == profileId
        profileStates[profileId] = ChatProfileRuntimeState(
            registeredBackendId = if (isManagerForProfile) {
                wsManager?.currentRegisteredBackendId
            } else {
                existingState?.registeredBackendId
            },
            pairedBackendLabel = _pairedBackendLabel.value,
            pairingState = _pairingState.value,
            connectionState = if (isManagerForProfile) _connectionState.value else existingState?.connectionState ?: ConnectionState.DISCONNECTED,
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
        _connectionState.value = state.connectionState
        _pairedBackendLabel.value = state.pairedBackendLabel
        _isLoadingHistory.value = state.isLoadingHistory
        _hasMoreHistory.value = state.hasMoreHistory
        loadedHistoryKeys = state.loadedHistoryKeys
    }

    private fun prepareRuntimeStateForSelection(profileId: String) {
        val profile = _profiles.value.firstOrNull { it.id == profileId } ?: return
        if (activeConnectionKey?.profileId == profileId) return
        val currentState = profileStates[profileId] ?: ChatProfileRuntimeState.fromProfile(profile)
        profileStates[profileId] = when {
            profile.backendId.isBlank() -> currentState.copy(
                registeredBackendId = null,
                pairedBackendLabel = null,
                pairingState = PairingState.UNPAIRED,
                connectionState = ConnectionState.DISCONNECTED,
            )
            profile.isPaired -> currentState.copy(
                registeredBackendId = null,
                pairedBackendLabel = profile.backendLabel ?: profile.resolvedDisplayName,
                pairingState = PairingState.PENDING,
                connectionState = ConnectionState.CONNECTING,
            )
            else -> currentState.copy(
                registeredBackendId = null,
                pairedBackendLabel = null,
                pairingState = PairingState.UNPAIRED,
                connectionState = ConnectionState.DISCONNECTED,
            )
        }
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

    private fun currentPayloadRouteCheck(): ChatPayloadRouteCheck {
        val selectedProfile = _profiles.value.firstOrNull { it.id == _selectedProfileId.value }
        return checkSelectedProfilePayloadRoute(
            selectedProfileId = _selectedProfileId.value,
            activeConnectionProfileId = activeConnectionKey?.profileId,
            selectedBackendId = selectedProfile?.backendId,
            registeredBackendId = wsManager?.currentRegisteredBackendId,
            pairingState = _pairingState.value,
            connectionState = _connectionState.value,
        )
    }

    private fun logPayloadRoute(payloadType: String, route: ChatPayloadRouteCheck) {
        val selectedProfile = _profiles.value.firstOrNull { it.id == _selectedProfileId.value }
        println(
            "OpenClawChat send.$payloadType " +
                "selectedProfileId=${_selectedProfileId.value.ifBlank { "-" }} " +
                "activeProfileId=${activeConnectionKey?.profileId ?: "-"} " +
                "selectedBackendId=${selectedProfile?.backendId?.ifBlank { "-" } ?: "-"} " +
                "registeredBackendId=${wsManager?.currentRegisteredBackendId ?: "-"} " +
                "connectionState=${_connectionState.value} pairingState=${_pairingState.value} " +
                "allowed=${route.canSend} reason=${route.reason ?: "-"}"
        )
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
        asrMode = asrMode,
        asrProfileId = asrProfileId,
    )

internal fun shouldReconnectForConfig(previous: ChatConnectionKey?, next: ChatConnectionKey): Boolean =
    previous != next

internal fun shouldRefreshConnectionForPairRequest(previous: ChatConnectionKey?, next: ChatConnectionKey): Boolean =
    shouldReconnectForConfig(previous, next)

internal fun shouldPersistPairedBackend(config: GatewayConfig, backendId: String?, backendLabel: String?): Boolean =
    config.pairedBackendId != backendId || config.pairedBackendLabel != backendLabel

internal data class ChatProfileRuntimeState(
    val registeredBackendId: String? = null,
    val pairedBackendLabel: String? = null,
    val pairingState: PairingState = PairingState.UNPAIRED,
    val connectionState: ConnectionState = ConnectionState.DISCONNECTED,
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
                connectionState = ConnectionState.DISCONNECTED,
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
        return profiles.firstOrNull { it.backendId == normalizedBackendId }?.id
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
    if (!hasBackendId) return AgentAvailabilityStatus.UNPAIRED
    return when (pairingState) {
        PairingState.PENDING -> AgentAvailabilityStatus.CONNECTING
        PairingState.UNPAIRED -> AgentAvailabilityStatus.UNPAIRED
        PairingState.PAIRED -> when (connectionState) {
            ConnectionState.PAIRED, ConnectionState.REGISTERED -> AgentAvailabilityStatus.AVAILABLE
            ConnectionState.CONNECTING, ConnectionState.CONNECTED, ConnectionState.DISCONNECTED -> AgentAvailabilityStatus.CONNECTING
        }
    }
}

internal fun canSendChatPayload(pairingState: PairingState, connectionState: ConnectionState): Boolean =
    pairingState == PairingState.PAIRED && connectionState == ConnectionState.PAIRED

internal enum class ChatPayloadRouteBlockReason {
    NO_SELECTED_PROFILE,
    BACKEND_NOT_CONFIGURED,
    PROFILE_NOT_ACTIVE,
    NOT_PAIRED,
    BACKEND_NOT_REGISTERED,
    BACKEND_MISMATCH,
}

internal data class ChatPayloadRouteCheck(
    val canSend: Boolean,
    val reason: ChatPayloadRouteBlockReason? = null,
)

internal fun checkSelectedProfilePayloadRoute(
    selectedProfileId: String,
    activeConnectionProfileId: String?,
    selectedBackendId: String?,
    registeredBackendId: String?,
    pairingState: PairingState,
    connectionState: ConnectionState,
): ChatPayloadRouteCheck {
    val normalizedSelectedProfileId = selectedProfileId.trim()
    val normalizedSelectedBackendId = selectedBackendId?.trim().orEmpty()
    val normalizedRegisteredBackendId = registeredBackendId?.trim().orEmpty()
    return when {
        normalizedSelectedProfileId.isEmpty() ->
            ChatPayloadRouteCheck(false, ChatPayloadRouteBlockReason.NO_SELECTED_PROFILE)
        normalizedSelectedBackendId.isEmpty() ->
            ChatPayloadRouteCheck(false, ChatPayloadRouteBlockReason.BACKEND_NOT_CONFIGURED)
        activeConnectionProfileId != normalizedSelectedProfileId ->
            ChatPayloadRouteCheck(false, ChatPayloadRouteBlockReason.PROFILE_NOT_ACTIVE)
        !canSendChatPayload(pairingState, connectionState) ->
            ChatPayloadRouteCheck(false, ChatPayloadRouteBlockReason.NOT_PAIRED)
        normalizedRegisteredBackendId.isEmpty() ->
            ChatPayloadRouteCheck(false, ChatPayloadRouteBlockReason.BACKEND_NOT_REGISTERED)
        normalizedRegisteredBackendId != normalizedSelectedBackendId ->
            ChatPayloadRouteCheck(false, ChatPayloadRouteBlockReason.BACKEND_MISMATCH)
        else ->
            ChatPayloadRouteCheck(true)
    }
}

internal fun connectionStateForProfileAvailability(
    profileId: String,
    selectedProfileId: String,
    activeConnectionProfileId: String?,
    activeConnectionState: ConnectionState,
): ConnectionState =
    if (profileId.isNotBlank()) {
        activeConnectionState
    } else {
        ConnectionState.DISCONNECTED
    }
