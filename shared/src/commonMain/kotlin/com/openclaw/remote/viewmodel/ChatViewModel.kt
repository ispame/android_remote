package com.openclaw.remote.viewmodel

import com.openclaw.remote.data.AgentAvailabilityStatus
import com.openclaw.remote.data.AgentPlatform
import com.openclaw.remote.data.AgentProfile
import com.openclaw.remote.data.AgentProfilesState
import com.openclaw.remote.data.ChatMessage
import com.openclaw.remote.data.CodexSessionSummary
import com.openclaw.remote.data.GatewayConfig
import com.openclaw.remote.data.MessageStatus
import com.openclaw.remote.data.RecordingWorkflow
import com.openclaw.remote.data.SettingsManager
import com.openclaw.remote.domain.ConnectionState
import com.openclaw.remote.domain.PairingState
import com.openclaw.remote.network.AuthRecoveryAction
import com.openclaw.remote.network.WebSocketManager
import com.openclaw.remote.network.WsMessageEvent
import com.openclaw.remote.network.authRecoveryActionForWsError
import com.openclaw.remote.network.isNotPairedRouterError
import com.openclaw.remote.network.isTerminalAuthError
import com.openclaw.remote.network.shouldRefreshAccessToken
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

    private val _codexSessions = MutableStateFlow<Map<String, List<CodexSessionSummary>>>(emptyMap())
    val codexSessions: StateFlow<Map<String, List<CodexSessionSummary>>> = _codexSessions.asStateFlow()

    private val _codexArchivedSessions = MutableStateFlow<Map<String, List<CodexSessionSummary>>>(emptyMap())
    val codexArchivedSessions: StateFlow<Map<String, List<CodexSessionSummary>>> = _codexArchivedSessions.asStateFlow()

    private val _codexMessagesByProfileSession =
        MutableStateFlow<Map<String, Map<String, List<ChatMessage>>>>(emptyMap())
    val codexMessagesByProfileSession: StateFlow<Map<String, Map<String, List<ChatMessage>>>> =
        _codexMessagesByProfileSession.asStateFlow()

    private val _codexAgentPreviews = MutableStateFlow<Map<String, String>>(emptyMap())
    val codexAgentPreviews: StateFlow<Map<String, String>> = _codexAgentPreviews.asStateFlow()

    private val _codexCreatedSessionIds = MutableStateFlow<Map<String, String>>(emptyMap())
    val codexCreatedSessionIds: StateFlow<Map<String, String>> = _codexCreatedSessionIds.asStateFlow()

    private val _profiles = MutableStateFlow<List<AgentProfile>>(emptyList())
    val profiles: StateFlow<List<AgentProfile>> = _profiles.asStateFlow()

    private val _selectedProfileId = MutableStateFlow("")
    val selectedProfileId: StateFlow<String> = _selectedProfileId.asStateFlow()

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

    private val _authNotice = MutableStateFlow<String?>(null)
    val authNotice: StateFlow<String?> = _authNotice.asStateFlow()

    private val _latestRecordingWorkflow = MutableStateFlow<RecordingWorkflow?>(null)
    val latestRecordingWorkflow: StateFlow<RecordingWorkflow?> = _latestRecordingWorkflow.asStateFlow()

    private val _recordingEvents = MutableSharedFlow<WsMessageEvent.RecordingEventReceived>(extraBufferCapacity = 16)
    val recordingEvents: SharedFlow<WsMessageEvent.RecordingEventReceived> = _recordingEvents.asSharedFlow()

    private val _longRecordingAsrStatuses = MutableSharedFlow<WsMessageEvent.LongRecordingAsrStatusReceived>(extraBufferCapacity = 16)
    val longRecordingAsrStatuses: SharedFlow<WsMessageEvent.LongRecordingAsrStatusReceived> =
        _longRecordingAsrStatuses.asSharedFlow()

    private val _authRecoveryRequests = MutableSharedFlow<AuthRecoveryRequest>(extraBufferCapacity = 1)
    val authRecoveryRequests: SharedFlow<AuthRecoveryRequest> = _authRecoveryRequests.asSharedFlow()

    private val _paymentRequiredRequests = MutableSharedFlow<PaymentRequiredRequest>(extraBufferCapacity = 1)
    val paymentRequiredRequests: SharedFlow<PaymentRequiredRequest> = _paymentRequiredRequests.asSharedFlow()

    private var wsManager: WebSocketManager? = null
    private val viewModelScope = CoroutineScope(Dispatchers.Main + SupervisorJob())
    private var activeConnectionKey: ChatConnectionKey? = null
    private var activeManagerJobs: List<Job> = emptyList()
    private var activeRouterConnectionState = ConnectionState.DISCONNECTED
    private var latestConfig = GatewayConfig()
    private var loadedHistoryKeys = emptySet<String>()
    private val profileStates = mutableMapOf<String, ChatProfileRuntimeState>()
    private val startupHistoryRequestedProfileIds = mutableSetOf<String>()
    private val startupHistoryPendingBackendIds = linkedSetOf<String>()
    private val connectionMutex = Mutex()
    private var pendingPushToken: ChatPushTokenBinding? = null

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
        if (!shouldMaintainAuthenticatedConnection(config.accessToken, config.accessExpiresAt)) {
            activeManagerJobs.forEach { it.cancel() }
            activeManagerJobs = emptyList()
            wsManager?.disconnect()
            wsManager = null
            activeConnectionKey = null
            activeRouterConnectionState = ConnectionState.DISCONNECTED
            if (config.profileId.isNotBlank()) {
                updateProfileState(config.profileId) { state ->
                    state.copy(connectionState = ConnectionState.DISCONNECTED)
                }
            }
            _connectionState.value = ConnectionState.DISCONNECTED
            return
        }
        val nextConnectionKey = config.toChatConnectionKey()
        if (!force && !shouldReconnectForConfig(activeConnectionKey, nextConnectionKey)) {
            return
        }
        reconnect(config, nextConnectionKey)
    }

    private fun applyProfilesState(state: AgentProfilesState) {
        val previousSelectedId = _selectedProfileId.value

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

        val nextSelectedId = when {
            previousSelectedId in knownIds -> previousSelectedId
            state.selectedProfileId in knownIds -> state.selectedProfileId
            else -> state.profiles.firstOrNull()?.id.orEmpty()
        }

        _profiles.value = state.profiles
        _selectedProfileId.value = nextSelectedId

        if (previousSelectedId != nextSelectedId) {
            loadRuntimeState(nextSelectedId)
        }
        scheduleStartupHistoryPreload(state.profiles)
    }

    private fun reconnect(config: GatewayConfig, connectionKey: ChatConnectionKey) {
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
            deviceLabel = config.deviceLabel.ifEmpty { "我的设备" },
            accessToken = config.accessToken,
            preferredBackendId = config.pairedBackendId,
            asrMode = config.asrMode,
            asrProfileId = config.asrProfileId,
        )
        val manager = wsManager!!
        val managerProfileId = connectionKey.profileId
        pendingPushToken?.let { token ->
            manager.updatePushToken(
                token = token.token,
                platform = token.platform,
                environment = token.environment,
                appVersion = token.appVersion,
            )
        }

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
                        is WsMessageEvent.Registered -> {
                            if (event.accountId.isNotBlank() && event.accountId != latestConfig.accountId) {
                                viewModelScope.launch {
                                    settingsManager.updateConfig(latestConfig.copy(accountId = event.accountId))
                                }
                            }
                            requestPendingStartupHistory()
                        }
                        is WsMessageEvent.Paired -> {
                            val profileId = resolveProfileIdForBackendId(
                                profiles = _profiles.value,
                                backendId = event.backendId,
                                activeProfileId = managerProfileId,
                            ) ?: managerProfileId.takeIf { it.isNotBlank() } ?: return@collect
                            updateProfileState(profileId) { state ->
                                state.withReachableBackend(event.backendId).copy(
                                    pairedBackendLabel = event.backendLabel,
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
                            requestPendingStartupHistory()
                        }
                        is WsMessageEvent.NewMessage -> {
                            val displayMessage = event.message.sanitizedForDisplay() ?: return@collect
                            val profileId = resolveProfileIdForBackendId(
                                profiles = _profiles.value,
                                backendId = event.backendId,
                                activeProfileId = managerProfileId,
                            ) ?: return@collect
                            if (!event.sessionKey.isNullOrBlank() && isCodexProfile(profileId)) {
                                appendCodexMessageToSession(profileId, event.sessionKey, displayMessage)
                                return@collect
                            }
                            updateProfileState(profileId) { state ->
                                state.withReachableBackend(event.backendId)
                            }
                            appendMessageToProfile(profileId, displayMessage)
                        }
                        is WsMessageEvent.HistoryResponse -> {
                            val profileId = resolveProfileIdForBackendId(
                                profiles = _profiles.value,
                                backendId = event.backendId,
                                activeProfileId = managerProfileId,
                            ) ?: return@collect
                            if (!event.sessionKey.isNullOrBlank() && isCodexProfile(profileId)) {
                                applyCodexHistoryResponseToSession(
                                    profileId = profileId,
                                    sessionId = event.sessionKey,
                                    messages = event.messages,
                                )
                                return@collect
                            }
                            applyHistoryResponseToProfile(
                                profileId = profileId,
                                backendId = event.backendId,
                                messages = event.messages,
                                hasMore = event.hasMore,
                                error = event.error,
                            )
                        }
                        is WsMessageEvent.AsrResult -> {
                            val profileId = profileIdForClientMessage(event.clientMessageId) ?: return@collect
                            val currentState = profileStates[profileId] ?: ChatProfileRuntimeState()
                            if (!event.success) {
                                logAsrFailure(profileId, event.clientMessageId, event.error)
                                if (event.clientMessageId != null && shouldDropAsrFailureMessage(event.error)) {
                                    updateProfileState(profileId) {
                                        currentState.copy(
                                            messages = currentState.messages.filter { message ->
                                                message.clientMessageId != event.clientMessageId
                                            }
                                        )
                                    }
                                }
                                return@collect
                            }
                            val updatedMessages = currentState.messages.map { message ->
                                if (event.clientMessageId != null && message.clientMessageId == event.clientMessageId) {
                                    message.copy(
                                        content = event.text.orEmpty(),
                                        status = MessageStatus.DELIVERED,
                                    )
                                } else {
                                    message
                                }
                            }
                            updateProfileState(profileId) { currentState.copy(messages = updatedMessages) }
                        }
                        is WsMessageEvent.RecordingWorkflowUpdate -> {
                            _latestRecordingWorkflow.value = event.workflow
                        }
                        is WsMessageEvent.RecordingEventReceived -> {
                            _recordingEvents.emit(event)
                        }
                        is WsMessageEvent.LongRecordingAsrStatusReceived -> {
                            _longRecordingAsrStatuses.emit(event)
                        }
                        is WsMessageEvent.CodexSessionListResponse -> {
                            val profileId = resolveProfileIdForBackendId(
                                profiles = _profiles.value,
                                backendId = event.backendId,
                                activeProfileId = managerProfileId,
                            ) ?: return@collect
                            applyCodexSessionList(profileId, event.sessions, event.archived)
                        }
                        is WsMessageEvent.CodexSessionCreateResponse -> {
                            val profileId = resolveProfileIdForBackendId(
                                profiles = _profiles.value,
                                backendId = event.backendId,
                                activeProfileId = managerProfileId,
                            ) ?: return@collect
                            if (event.accepted && !event.sessionId.isNullOrBlank()) {
                                val session = event.session ?: CodexSessionSummary(
                                    sessionId = event.sessionId,
                                    title = "新会话",
                                )
                                upsertCodexSession(profileId, session.copy(archived = false), archived = false)
                                _codexCreatedSessionIds.value = _codexCreatedSessionIds.value + (profileId to session.sessionId)
                            }
                        }
                        is WsMessageEvent.CodexSessionArchiveResponse -> {
                            val profileId = resolveProfileIdForBackendId(
                                profiles = _profiles.value,
                                backendId = event.backendId,
                                activeProfileId = managerProfileId,
                            ) ?: return@collect
                            if (event.archived) {
                                moveCodexSession(profileId, event.sessionId, archived = true)
                            }
                        }
                        is WsMessageEvent.CodexSessionUnarchiveResponse -> {
                            val profileId = resolveProfileIdForBackendId(
                                profiles = _profiles.value,
                                backendId = event.backendId,
                                activeProfileId = managerProfileId,
                            ) ?: return@collect
                            if (event.unarchived) {
                                moveCodexSession(profileId, event.sessionId, archived = false)
                            }
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
                        is WsMessageEvent.SessionPreempted -> {
                            val notice = buildString {
                                append("账号已在另一台设备登录")
                                event.replacementTerminalLabel
                                    ?.takeIf { it.isNotBlank() }
                                    ?.let { append("：$it") }
                            }
                            updateProfileState(managerProfileId) { state ->
                                state.copy(connectionState = ConnectionState.DISCONNECTED)
                            }
                            if (managerProfileId == _selectedProfileId.value) {
                                _connectionState.value = ConnectionState.DISCONNECTED
                            }
                            appendMessageToProfile(
                                managerProfileId,
                                ChatMessage(
                                    notice,
                                    SimpleDateFormat("HH:mm", Locale.getDefault()).format(Date()),
                                    "assistant",
                                )
                            )
                            clearAuthSession(notice)
                        }
                        is WsMessageEvent.Error -> {
                            if (event.code.trim().uppercase() == "PAYMENT_REQUIRED") {
                                _paymentRequiredRequests.emit(PaymentRequiredRequest(event.message))
                            }
                            when (authRecoveryActionForWsError(event.code)) {
                                AuthRecoveryAction.REFRESH_SESSION -> {
                                    updateProfileState(managerProfileId) { state ->
                                        state.copy(connectionState = ConnectionState.DISCONNECTED)
                                    }
                                    if (managerProfileId == _selectedProfileId.value) {
                                        _connectionState.value = ConnectionState.DISCONNECTED
                                    }
                                    _authRecoveryRequests.emit(AuthRecoveryRequest(event.code, event.message))
                                    return@collect
                                }
                                AuthRecoveryAction.REQUIRE_LOGIN -> {
                                    clearAuthSession("登录状态已过期，请重新登录")
                                    return@collect
                                }
                                AuthRecoveryAction.NONE -> Unit
                            }
                            if (isNotPairedRouterError(event.code)) {
                                val profileId = managerProfileId.takeIf { it.isNotBlank() } ?: _selectedProfileId.value
                                clearProfilePairing(profileId)
                                viewModelScope.launch {
                                    settingsManager.updatePairedBackend(null, null, profileId)
                                }
                                return@collect
                            }
                            appendMessageToProfile(
                                managerProfileId,
                                ChatMessage(
                                    "错误 (${event.code}): ${event.message}",
                                    SimpleDateFormat("HH:mm", Locale.getDefault()).format(Date()),
                                    "assistant",
                                )
                            )
                            if (isTerminalAuthError(event.code)) {
                                clearAuthSession("登录状态已过期，请重新登录")
                            }
                        }
                    }
                }
            },
        )

        manager.connect()
    }

    fun updatePushToken(
        token: String,
        platform: String = "android",
        environment: String = "production",
        appVersion: String = "1.0",
    ) {
        val normalizedToken = token.trim()
        if (normalizedToken.isEmpty()) return
        val binding = ChatPushTokenBinding(
            token = normalizedToken,
            platform = platform,
            environment = environment,
            appVersion = appVersion,
        )
        pendingPushToken = binding
        wsManager?.updatePushToken(
            token = binding.token,
            platform = binding.platform,
            environment = binding.environment,
            appVersion = binding.appVersion,
        )
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

    fun applyRecordingWorkflow(workflow: RecordingWorkflow) {
        _latestRecordingWorkflow.value = workflow
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
                val nextConnectionKey = config.toChatConnectionKey()
                if (shouldRefreshConnectionForPairRequest(activeConnectionKey, nextConnectionKey)) {
                    reconnect(config, nextConnectionKey)
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
        _selectedProfileId.value = profileId
        loadRuntimeState(profileId)
    }

    fun pairingStateFor(profile: AgentProfile): PairingState =
        if (profile.id == _selectedProfileId.value && activeConnectionKey?.profileId == profile.id) {
            _pairingState.value
        } else {
            profileStates[profile.id]?.pairingState ?: if (profile.isPaired) PairingState.PAIRED else PairingState.UNPAIRED
        }

    fun availabilityStatus(profile: AgentProfile): AgentAvailabilityStatus {
        val runtimeState = profileStates[profile.id]
        return agentAvailabilityForStatus(
            hasBackendId = profile.backendId.isNotBlank(),
            pairingState = pairingStateFor(profile),
            connectionState = connectionStateForProfileAvailability(
                profileId = profile.id,
                selectedProfileId = _selectedProfileId.value,
                activeConnectionProfileId = activeConnectionKey?.profileId,
                selectedConnectionState = _connectionState.value,
                profileConnectionState = runtimeState?.connectionState,
                routerConnectionState = activeRouterConnectionState,
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
        val beforeTimestamp = oldestHistoryTimestamp(profileStates[_selectedProfileId.value]?.messages.orEmpty())
        _isLoadingHistory.value = true
        updateProfileState(_selectedProfileId.value) { state ->
            state.copy(isLoadingHistory = true)
        }
        if (wsManager?.requestRecentHistory(backendId = selectedProfileBackendId(), beforeTimestamp = beforeTimestamp) != true) {
            _isLoadingHistory.value = false
            updateProfileState(_selectedProfileId.value) { state ->
                state.copy(isLoadingHistory = false)
            }
        }
    }

    fun requestCodexSessions(profileId: String, archived: Boolean = false) {
        val backendId = backendIdForProfile(profileId) ?: return
        wsManager?.requestCodexSessions(backendId = backendId, archived = archived)
    }

    fun createCodexSession(profileId: String) {
        val backendId = backendIdForProfile(profileId) ?: return
        wsManager?.createCodexSession(backendId = backendId)
    }

    fun archiveCodexSession(profileId: String, sessionId: String) {
        val backendId = backendIdForProfile(profileId) ?: return
        wsManager?.archiveCodexSession(backendId = backendId, sessionId = sessionId)
    }

    fun unarchiveCodexSession(profileId: String, sessionId: String) {
        val backendId = backendIdForProfile(profileId) ?: return
        wsManager?.unarchiveCodexSession(backendId = backendId, sessionId = sessionId)
    }

    fun requestCodexHistory(profileId: String, sessionId: String) {
        val backendId = backendIdForProfile(profileId) ?: return
        wsManager?.requestCodexHistory(backendId = backendId, sessionId = sessionId)
    }

    fun sendCodexText(profileId: String, sessionId: String, text: String) {
        val backendId = backendIdForProfile(profileId) ?: return
        if (wsManager?.sendCodexText(text = text, backendId = backendId, sessionId = sessionId) != true) {
            appendCodexMessageToSession(
                profileId = profileId,
                sessionId = sessionId,
                message = ChatMessage(
                    content = "请先配对当前 Codex",
                    timestamp = SimpleDateFormat("HH:mm", Locale.getDefault()).format(Date()),
                    senderId = "assistant",
                ),
            )
        }
    }

    fun unpair() {
        wsManager?.unpair()
    }

    fun disconnect() {
        wsManager?.disconnect()
    }

    fun clearAuthNotice() {
        _authNotice.value = null
    }

    fun onCleared() {
        wsManager?.disconnect()
        wsManager = null
        activeManagerJobs.forEach { it.cancel() }
        activeManagerJobs = emptyList()
        viewModelScope.cancel()
    }

    private fun clearAuthSession(message: String) {
        _authNotice.value = message
        activeManagerJobs.forEach { it.cancel() }
        activeManagerJobs = emptyList()
        wsManager?.disconnect()
        wsManager = null
        activeConnectionKey = null
        activeRouterConnectionState = ConnectionState.DISCONNECTED
        _connectionState.value = ConnectionState.DISCONNECTED
        viewModelScope.launch {
            settingsManager.updateConfig(
                latestConfig.copy(
                    accountId = "",
                    accessToken = "",
                    refreshToken = "",
                    accessExpiresAt = "",
                    refreshExpiresAt = "",
                )
            )
        }
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
        }
    }

    private fun appendCodexMessageToSession(profileId: String, sessionId: String, message: ChatMessage) {
        val profileMessages = _codexMessagesByProfileSession.value[profileId].orEmpty()
        val sessionMessages = profileMessages[sessionId].orEmpty() + message
        _codexMessagesByProfileSession.value = _codexMessagesByProfileSession.value +
            (profileId to (profileMessages + (sessionId to sessionMessages)))
        if (message.senderId != "user") {
            updateCodexSessionPreview(profileId, sessionId, message)
            _codexAgentPreviews.value = _codexAgentPreviews.value +
                (profileId to message.content.compactPreview())
        }
    }

    private fun applyCodexHistoryResponseToSession(
        profileId: String,
        sessionId: String,
        messages: List<ChatMessage>,
    ) {
        val profileMessages = _codexMessagesByProfileSession.value[profileId].orEmpty()
        val existing = profileMessages[sessionId].orEmpty()
        val mergeResult = mergeHistoryMessages(
            existingMessages = existing,
            loadedHistoryKeys = existing.map(::stableHistoryKey).toSet(),
            incomingMessages = messages,
        )
        _codexMessagesByProfileSession.value = _codexMessagesByProfileSession.value +
            (profileId to (profileMessages + (sessionId to mergeResult.messages)))
        messages.lastOrNull { it.senderId != "user" }?.let { message ->
            updateCodexSessionPreview(profileId, sessionId, message)
            _codexAgentPreviews.value = _codexAgentPreviews.value + (profileId to message.content.compactPreview())
        }
    }

    private fun applyCodexSessionList(
        profileId: String,
        sessions: List<CodexSessionSummary>,
        archived: Boolean,
    ) {
        val sorted = sessions.sortedByDescending { it.updatedAt.ifBlank { it.createdAt } }
        if (archived) {
            _codexArchivedSessions.value = _codexArchivedSessions.value + (profileId to sorted)
        } else {
            _codexSessions.value = _codexSessions.value + (profileId to sorted)
            sorted.firstOrNull { it.lastAssistantPreview.isNotBlank() }?.let { session ->
                _codexAgentPreviews.value = _codexAgentPreviews.value + (profileId to session.displayPreview)
            }
        }
    }

    private fun upsertCodexSession(profileId: String, session: CodexSessionSummary, archived: Boolean) {
        val source = if (archived) _codexArchivedSessions else _codexSessions
        val sessions = source.value[profileId].orEmpty()
            .filterNot { it.sessionId == session.sessionId } + session
        source.value = source.value + (
            profileId to sessions.sortedByDescending { it.updatedAt.ifBlank { it.createdAt } }
        )
        if (!archived && session.lastAssistantPreview.isNotBlank()) {
            _codexAgentPreviews.value = _codexAgentPreviews.value + (profileId to session.displayPreview)
        }
    }

    private fun moveCodexSession(profileId: String, sessionId: String, archived: Boolean) {
        val active = _codexSessions.value[profileId].orEmpty()
        val archivedSessions = _codexArchivedSessions.value[profileId].orEmpty()
        if (archived) {
            val session = active.firstOrNull { it.sessionId == sessionId }?.copy(archived = true)
            _codexSessions.value = _codexSessions.value + (profileId to active.filterNot { it.sessionId == sessionId })
            if (session != null) upsertCodexSession(profileId, session, archived = true)
        } else {
            val session = archivedSessions.firstOrNull { it.sessionId == sessionId }?.copy(archived = false)
            _codexArchivedSessions.value = _codexArchivedSessions.value +
                (profileId to archivedSessions.filterNot { it.sessionId == sessionId })
            if (session != null) upsertCodexSession(profileId, session, archived = false)
        }
    }

    private fun updateCodexSessionPreview(profileId: String, sessionId: String, message: ChatMessage) {
        val sessions = _codexSessions.value[profileId].orEmpty()
        val index = sessions.indexOfFirst { it.sessionId == sessionId }
        if (index < 0) return
        val updated = sessions.toMutableList()
        updated[index] = updated[index].copy(
            lastAssistantPreview = message.content.compactPreview(),
            updatedAt = message.rawTimestamp ?: updated[index].updatedAt,
        )
        _codexSessions.value = _codexSessions.value +
            (profileId to updated.sortedByDescending { it.updatedAt.ifBlank { it.createdAt } })
    }

    private fun backendIdForProfile(profileId: String): String? =
        profileStates[profileId]?.registeredBackendId?.takeIf { it.isNotBlank() }
            ?: _profiles.value.firstOrNull { it.id == profileId }?.backendId?.trim()?.takeIf { it.isNotEmpty() }

    private fun isCodexProfile(profileId: String): Boolean =
        _profiles.value.firstOrNull { it.id == profileId }?.platform == AgentPlatform.CODEX

    private fun clearProfilePairing(profileId: String) {
        updateProfileState(profileId) { state ->
            val nextConnectionState = if (state.connectionState == ConnectionState.DISCONNECTED) {
                ConnectionState.DISCONNECTED
            } else {
                ConnectionState.REGISTERED
            }
            state.copy(
                registeredBackendId = null,
                pairedBackendLabel = null,
                pairingState = PairingState.UNPAIRED,
                connectionState = nextConnectionState,
                loadedHistoryKeys = emptySet(),
            )
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
        profileStates[profileId] = runtimeStateForProfilePersistence(
            existingState = existingState,
            isManagerForProfile = isManagerForProfile,
            currentRegisteredBackendId = wsManager?.currentRegisteredBackendId,
            currentPairedBackendLabel = _pairedBackendLabel.value,
            currentPairingState = _pairingState.value,
            currentConnectionState = _connectionState.value,
            currentMessages = _messages.value,
            currentIsLoadingHistory = _isLoadingHistory.value,
            currentHasMoreHistory = _hasMoreHistory.value,
            currentLoadedHistoryKeys = loadedHistoryKeys,
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

    private fun loadHistoryViewState(profileId: String) {
        val state = profileStates[profileId] ?: ChatProfileRuntimeState()
        _messages.value = state.messages
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

    private fun scheduleStartupHistoryPreload(profiles: List<AgentProfile>) {
        val candidates = startupHistoryPreloadCandidates(
            profiles = profiles,
            requestedProfileIds = startupHistoryRequestedProfileIds,
        )
        if (candidates.isEmpty()) return
        startupHistoryRequestedProfileIds += candidates.map { it.id }
        startupHistoryPendingBackendIds += candidates.map { it.backendId.trim() }
        requestPendingStartupHistory()
    }

    private fun requestPendingStartupHistory() {
        val manager = wsManager ?: return
        val requested = startupHistoryPendingBackendIds
            .filter { backendId -> manager.requestRecentHistory(backendId = backendId) }
            .toSet()
        startupHistoryPendingBackendIds.removeAll(requested)
    }

    private fun applyHistoryResponseToProfile(
        profileId: String,
        backendId: String?,
        messages: List<ChatMessage>,
        hasMore: Boolean,
        error: String?,
    ) {
        val currentState = profileStates[profileId] ?: ChatProfileRuntimeState()
        val nextState = if (!error.isNullOrBlank()) {
            currentState.copy(isLoadingHistory = false, hasMoreHistory = false)
        } else {
            val mergeResult = mergeHistoryMessages(
                existingMessages = currentState.messages,
                loadedHistoryKeys = currentState.loadedHistoryKeys,
                incomingMessages = messages,
            )
            currentState.withReachableBackend(backendId).copy(
                messages = mergeResult.messages,
                loadedHistoryKeys = mergeResult.loadedHistoryKeys,
                isLoadingHistory = false,
                hasMoreHistory = hasMore,
            )
        }
        profileStates[profileId] = nextState
        if (profileId == _selectedProfileId.value) {
            if (profileId == activeConnectionKey?.profileId) {
                loadRuntimeState(profileId)
            } else {
                loadHistoryViewState(profileId)
            }
        }
    }

    private fun selectedProfileBackendId(): String? {
        return _profiles.value
            .firstOrNull { it.id == _selectedProfileId.value }
            ?.backendId
            ?.trim()
            ?.takeIf { it.isNotEmpty() }
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

    private fun logAsrFailure(profileId: String, clientMessageId: String?, error: String?) {
        println(
            "OpenClawChat asr failed " +
                "profileId=${profileId.ifBlank { "-" }} " +
                "clientMessageId=${clientMessageId?.ifBlank { "-" } ?: "-"} " +
                "error=${error?.ifBlank { "unknown" } ?: "unknown"}"
        )
    }
}

internal fun shouldDropAsrFailureMessage(error: String?): Boolean =
    true

internal data class ChatConnectionKey(
    val profileId: String,
    val gatewayUrl: String,
    val deviceLabel: String,
    val accessToken: String,
    val asrMode: String,
    val asrProfileId: String,
)

internal fun GatewayConfig.toChatConnectionKey(): ChatConnectionKey =
    ChatConnectionKey(
        profileId = profileId,
        gatewayUrl = gatewayUrl,
        deviceLabel = deviceLabel,
        accessToken = accessToken,
        asrMode = asrMode,
        asrProfileId = asrProfileId,
    )

internal fun shouldReconnectForConfig(previous: ChatConnectionKey?, next: ChatConnectionKey): Boolean =
    previous != next

internal fun shouldRefreshConnectionForPairRequest(previous: ChatConnectionKey?, next: ChatConnectionKey): Boolean =
    shouldReconnectForConfig(previous, next)

internal fun shouldPersistPairedBackend(config: GatewayConfig, backendId: String?, backendLabel: String?): Boolean =
    config.pairedBackendId != backendId || config.pairedBackendLabel != backendLabel

internal fun shouldMaintainAuthenticatedConnection(accessToken: String, accessExpiresAt: String): Boolean =
    accessToken.trim().isNotEmpty() && !shouldRefreshAccessToken(accessExpiresAt)

data class AuthRecoveryRequest(
    val code: String,
    val message: String,
)

data class PaymentRequiredRequest(
    val message: String,
)

internal fun oldestHistoryTimestamp(messages: List<ChatMessage>): String? =
    messages.firstNotNullOfOrNull { it.rawTimestamp?.takeIf { timestamp -> timestamp.isNotBlank() } }

private fun String.compactPreview(): String =
    trim()
        .split(Regex("\\s+"))
        .filter { it.isNotBlank() }
        .joinToString(" ")
        .take(180)

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
        if (profile.backendId.isBlank() || !profile.isPaired) {
            return copy(
                registeredBackendId = null,
                pairedBackendLabel = null,
                pairingState = PairingState.UNPAIRED,
                connectionState = ConnectionState.DISCONNECTED,
            )
        }
        val normalizedBackendId = profile.backendId.trim()
        val hasSameRuntimeBackend = registeredBackendId == normalizedBackendId
        return copy(
            registeredBackendId = normalizedBackendId,
            pairedBackendLabel = profile.backendLabel ?: profile.resolvedDisplayName,
            pairingState = PairingState.PAIRED,
            connectionState = if (hasSameRuntimeBackend) connectionState else ConnectionState.DISCONNECTED,
        )
    }

    companion object {
        fun fromProfile(profile: AgentProfile): ChatProfileRuntimeState =
            ChatProfileRuntimeState().withProfilePairing(profile)
    }
}

internal fun runtimeStateForProfilePersistence(
    existingState: ChatProfileRuntimeState?,
    isManagerForProfile: Boolean,
    currentRegisteredBackendId: String?,
    currentPairedBackendLabel: String?,
    currentPairingState: PairingState,
    currentConnectionState: ConnectionState,
    currentMessages: List<ChatMessage>,
    currentIsLoadingHistory: Boolean,
    currentHasMoreHistory: Boolean,
    currentLoadedHistoryKeys: Set<String>,
): ChatProfileRuntimeState =
    if (!isManagerForProfile) {
        existingState ?: ChatProfileRuntimeState()
    } else ChatProfileRuntimeState(
        registeredBackendId = currentRegisteredBackendId,
        pairedBackendLabel = currentPairedBackendLabel,
        pairingState = currentPairingState,
        connectionState = currentConnectionState,
        messages = currentMessages,
        isLoadingHistory = currentIsLoadingHistory,
        hasMoreHistory = currentHasMoreHistory,
        loadedHistoryKeys = currentLoadedHistoryKeys,
    )

internal fun ChatProfileRuntimeState.withReachableBackend(backendId: String?): ChatProfileRuntimeState {
    val normalizedBackendId = backendId?.trim().orEmpty()
    if (normalizedBackendId.isBlank()) return this
    return copy(
        registeredBackendId = normalizedBackendId,
        pairingState = PairingState.PAIRED,
        connectionState = ConnectionState.PAIRED,
    )
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

internal fun startupHistoryPreloadCandidates(
    profiles: List<AgentProfile>,
    requestedProfileIds: Set<String>,
): List<AgentProfile> =
    profiles.filter { profile ->
        profile.isPaired &&
            profile.backendId.isNotBlank() &&
            profile.id !in requestedProfileIds
    }

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

private data class ChatPushTokenBinding(
    val token: String,
    val platform: String,
    val environment: String,
    val appVersion: String,
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
    selectedConnectionState: ConnectionState,
    profileConnectionState: ConnectionState?,
    routerConnectionState: ConnectionState,
): ConnectionState =
    if (profileId.isBlank()) {
        ConnectionState.DISCONNECTED
    } else {
        val ownConnectionState = if (profileId == selectedProfileId && activeConnectionProfileId == profileId) {
            selectedConnectionState
        } else {
            profileConnectionState ?: ConnectionState.DISCONNECTED
        }
        if (routerConnectionState == ConnectionState.REGISTERED || routerConnectionState == ConnectionState.PAIRED) {
            ownConnectionState
        } else {
            downgradeProfileConnectionForRouterReconnect(ownConnectionState)
        }
    }

internal fun downgradeProfileConnectionForRouterReconnect(connectionState: ConnectionState): ConnectionState =
    when (connectionState) {
        ConnectionState.PAIRED, ConnectionState.REGISTERED, ConnectionState.CONNECTED, ConnectionState.CONNECTING ->
            ConnectionState.CONNECTING
        ConnectionState.DISCONNECTED -> ConnectionState.DISCONNECTED
    }
