package com.openclaw.remote

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.util.Log
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.core.content.ContextCompat
import com.openclaw.remote.auth.AccountAgentProfileResult
import com.openclaw.remote.auth.GatewayAuthClient
import com.openclaw.remote.audio.AudioRecorderAndroid
import com.openclaw.remote.data.AgentPlatform
import com.openclaw.remote.data.AgentProfile
import com.openclaw.remote.data.GatewayConfig
import com.openclaw.remote.data.SettingsManagerAndroid
import com.openclaw.remote.headset.A9UltraSppManager
import com.openclaw.remote.headset.AssistantSpeechTrigger
import com.openclaw.remote.headset.BaseTtsEngine
import com.openclaw.remote.headset.SoundPlaybackController
import com.openclaw.remote.headset.TtsEngine
import com.openclaw.remote.headset.TtsEngineFactory
import com.openclaw.remote.headset.supportsLedLightControl
import com.openclaw.remote.headset.supportsStandbyControl
import com.openclaw.remote.network.accessTokenRefreshDelayMillis
import com.openclaw.remote.network.refreshFailureRequiresLogin
import com.openclaw.remote.network.shouldRefreshAccessToken
import com.openclaw.remote.ui.screen.AuthScreen
import com.openclaw.remote.ui.screen.MainScreen
import com.openclaw.remote.ui.screen.QRParseResult
import com.openclaw.remote.ui.screen.SettingsScreen
import com.openclaw.remote.ui.screen.WalletScreen
import com.openclaw.remote.ui.screen.QRScannerScreen
import com.openclaw.remote.ui.screen.parseQRPack
import com.openclaw.remote.ui.theme.MochiTheme
import com.openclaw.remote.viewmodel.ChatViewModel
import kotlinx.coroutines.delay
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.util.UUID

class MainActivity : ComponentActivity() {

    private lateinit var viewModel: ChatViewModel
    private lateinit var settingsManager: SettingsManagerAndroid
    private lateinit var audioRecorder: AudioRecorderAndroid
    private lateinit var headsetManager: A9UltraSppManager
    private lateinit var soundPlaybackController: SoundPlaybackController
    private var ttsEngine: TtsEngine? = null
    private var systemFallbackTtsEngine: TtsEngine? = null
    private var currentConfig: GatewayConfig = GatewayConfig()
    private val scope = kotlinx.coroutines.CoroutineScope(kotlinx.coroutines.Dispatchers.Main)
    private val authRefreshMutex = Mutex()

    private val requestPermissions = registerForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions()
    ) { grants ->
        if (grants.values.all { it }) {
            headsetManager.start()
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        settingsManager = SettingsManagerAndroid(this)
        audioRecorder = AudioRecorderAndroid(this)

        viewModel = ChatViewModel(settingsManager)
        soundPlaybackController = SoundPlaybackController(
            ttsEngineProvider = { ttsEngine },
            fallbackTtsEngineProvider = { systemFallbackTtsEngine },
            shouldUseFallback = { error -> shouldFallbackToSystemTts(error) },
            persistSoundPlaybackEnabled = { enabled ->
                scope.launch {
                    settingsManager.updateSoundPlaybackEnabled(enabled)
                }
            },
        )

        // 初始化 TTS 引擎和配置
        scope.launch {
            settingsManager.configFlow.collect { config ->
                currentConfig = config
            }
        }
        headsetManager = A9UltraSppManager(this, onAudioReady = { audioData ->
            Log.i("A9UltraSPP", "headset audio ready wav=${audioData.size}")
            viewModel.sendAudio(audioData)
        }, onWake = {
            soundPlaybackController.onHeadsetWake()
        })

        checkPermissions()
        handleIntent(intent)

        setContent {
            val systemDark = isSystemInDarkTheme()
            var isDark by rememberSaveable(systemDark) { mutableStateOf(systemDark) }
            var showSettings by remember { mutableStateOf(false) }
            var showQRScanner by remember { mutableStateOf(false) }
            var showWallet by remember { mutableStateOf(false) }
            var walletNotice by remember { mutableStateOf<String?>(null) }
            var authGateNotice by remember { mutableStateOf<String?>(null) }
            var workflowActionInProgress by remember { mutableStateOf(false) }
            var workflowActionError by remember { mutableStateOf<String?>(null) }
            val assistantSpeechTrigger = remember { AssistantSpeechTrigger() }
            val authClient = remember { GatewayAuthClient() }

            MochiTheme(darkTheme = isDark) {
                val connectionState by viewModel.connectionState.collectAsState()
                val pairingState by viewModel.pairingState.collectAsState()
                val pairedBackendLabel by viewModel.pairedBackendLabel.collectAsState()
                val isRecording by audioRecorder.isRecording.collectAsState()
                val messages by viewModel.messages.collectAsState()
                val profiles by viewModel.profiles.collectAsState()
                val selectedProfileId by viewModel.selectedProfileId.collectAsState()
                val isLoadingHistory by viewModel.isLoadingHistory.collectAsState()
                val hasMoreHistory by viewModel.hasMoreHistory.collectAsState()
                val headsetState by headsetManager.state.collectAsState()
                val headsetStandbyMode by headsetManager.standbyMode.collectAsState()
                val headsetLedLightEnabled by headsetManager.ledLightEnabled.collectAsState()
                val config by settingsManager.configFlow.collectAsState(initial = currentConfig)
                val authNotice by viewModel.authNotice.collectAsState()
                val soundPlaybackEnabled by settingsManager.soundPlaybackEnabledFlow.collectAsState(initial = true)
                val playbackState by soundPlaybackController.state.collectAsState()
                val recordingWorkflow by viewModel.latestRecordingWorkflow.collectAsState()
                val showHeadsetStandbyControl = headsetState.supportsStandbyControl()
                val showHeadsetLedLightControl = headsetState.supportsLedLightControl()
                val authenticated = config.accessToken.isNotBlank()

                DisposableEffect(Unit) {
                    onDispose {
                        authClient.close()
                    }
                }

                LaunchedEffect(authenticated) {
                    if (!authenticated) {
                        showQRScanner = false
                        showSettings = false
                        showWallet = false
                    }
                }

                LaunchedEffect(soundPlaybackEnabled) {
                    soundPlaybackController.syncSoundPlaybackEnabled(soundPlaybackEnabled)
                }

                LaunchedEffect(config.gatewayUrl, config.refreshToken, config.accessExpiresAt) {
                    if (config.accessToken.isBlank() || config.refreshToken.isBlank()) return@LaunchedEffect
                    val delayMillis = accessTokenRefreshDelayMillis(config.accessExpiresAt)
                    delay(delayMillis)
                    val outcome = refreshAuthSessionIfNeeded(authClient, force = false)
                    if (outcome.loginRequired) {
                        authGateNotice = outcome.message
                    }
                }

                LaunchedEffect(Unit) {
                    viewModel.authRecoveryRequests.collect {
                        val outcome = refreshAuthSessionIfNeeded(authClient, force = true)
                        when {
                            outcome.canUseSession -> viewModel.connect()
                            outcome.loginRequired -> authGateNotice = outcome.message
                            outcome.message != null -> authGateNotice = outcome.message
                        }
                    }
                }

                LaunchedEffect(Unit) {
                    viewModel.paymentRequiredRequests.collect { request ->
                        walletNotice = request.message.ifBlank { "余额不足，请开通套餐或充值余额" }
                        showWallet = true
                        showSettings = false
                        showQRScanner = false
                    }
                }

                // 监听配置变化，重新初始化 TTS 引擎
                LaunchedEffect(config.ttsEngine) {
                    val fallbackEngine = ensureSystemFallbackTtsEngine()
                    val nextEngine = if (config.ttsEngine == "minimax") {
                        TtsEngineFactory.create(config.ttsEngine, this@MainActivity).also(::configureTtsCallbacks)
                    } else {
                        fallbackEngine
                    }
                    if (ttsEngine !== nextEngine) {
                        soundPlaybackController.interruptCurrentPlayback()
                        ttsEngine
                            ?.takeIf { it !== systemFallbackTtsEngine }
                            ?.release()
                        ttsEngine = nextEngine
                    }
                }

                // 监听当前会话的新 assistant 回复，播放 TTS。历史消息和设置变更不重播。
                LaunchedEffect(messages) {
                    val replies = assistantSpeechTrigger.onMessagesChanged(messages)
                    if (replies.isEmpty()) return@LaunchedEffect
                    val apiKey = if (config.ttsEngine == "minimax") config.minimaxApiKey else null
                    val voiceId = if (config.ttsEngine == "minimax") config.minimaxVoiceId else null
                    soundPlaybackController.enqueueAssistantReplies(
                        texts = replies.map { it.content },
                        apiKey = apiKey,
                        voiceId = voiceId,
                    )
                }

                if (!authenticated) {
                    AuthScreen(
                        config = config,
                        notice = authNotice ?: authGateNotice,
                        onAuthenticated = { session, gatewayUrl ->
                            scope.launch {
                                settingsManager.updateConfig(
                                    config.copy(
                                        gatewayUrl = gatewayUrl,
                                        accountId = session.accountId,
                                        accessToken = session.accessToken,
                                        refreshToken = session.refreshToken,
                                        accessExpiresAt = session.accessExpiresAt,
                                        refreshExpiresAt = session.refreshExpiresAt,
                                        deviceLabel = config.deviceLabel.ifBlank { "我的设备" },
                                    )
                                )
                                syncAccountAgentsFromServer(authClient, gatewayUrl, session.accessToken)
                                authGateNotice = null
                                viewModel.clearAuthNotice()
                                viewModel.connect()
                            }
                        },
                        onNoticeShown = {
                            authGateNotice = null
                            viewModel.clearAuthNotice()
                        },
                    )
                } else if (showWallet) {
                    WalletScreen(
                        config = config,
                        initialNotice = walletNotice,
                        onBack = {
                            walletNotice = null
                            showWallet = false
                        },
                    )
                } else if (showQRScanner) {
                    QRScannerScreen(
                        onQRCodeScanned = { scannedText ->
                            showQRScanner = false
                            parseQRPack(scannedText) { result ->
                                handleQRParseResult(result)
                            }
                        },
                        onClose = { showQRScanner = false }
                    )
                } else if (showSettings) {
                    SettingsScreen(
                        settingsManager = settingsManager,
                        viewModel = viewModel,
                        connectionState = connectionState,
                        pairingState = pairingState,
                        pairedBackendLabel = pairedBackendLabel,
                        isDark = isDark,
                        onToggleTheme = { isDark = !isDark },
                        onRequestPair = { profileId, backendId ->
                            viewModel.requestPair(profileId, backendId)
                            showSettings = false
                        },
                        onUnpair = {
                            viewModel.unpair()
                        },
                        onBack = { showSettings = false },
                        onNavigateToQRScanner = { if (authenticated) showQRScanner = true },
                        onNavigateToWallet = {
                            showSettings = false
                            showWallet = true
                        },
                    )
                } else {
                    MainScreen(
                        messages = messages,
                        isRecording = isRecording,
                        connectionState = connectionState,
                        pairingState = pairingState,
                        pairedBackendLabel = pairedBackendLabel,
                        profiles = profiles,
                        selectedProfileId = selectedProfileId,
                        profileStatuses = profiles.associate { it.id to viewModel.availabilityStatus(it) },
                        isDark = isDark,
                        isLoadingHistory = isLoadingHistory,
                        hasMoreHistory = hasMoreHistory,
                        headsetStatusLabel = headsetState.label,
                        headsetStandbyMode = headsetStandbyMode,
                        showHeadsetStandbyControl = showHeadsetStandbyControl,
                        headsetLedLightEnabled = headsetLedLightEnabled,
                        showHeadsetLedLightControl = showHeadsetLedLightControl,
                        soundPlaybackEnabled = playbackState.soundPlaybackEnabled,
                        isPlaybackSpeaking = playbackState.isSpeaking,
                        recordingWorkflow = recordingWorkflow,
                        workflowActionInProgress = workflowActionInProgress,
                        workflowActionError = workflowActionError,
                        viewModel = viewModel,
                        audioRecorder = audioRecorder,
                        onToggleTheme = { isDark = !isDark },
                        onToggleSoundPlayback = {
                            soundPlaybackController.setSoundPlaybackEnabled(!playbackState.soundPlaybackEnabled)
                        },
                        onInterruptPlayback = {
                            soundPlaybackController.interruptCurrentPlayback()
                        },
                        onToggleHeadsetStandbyMode = {
                            headsetManager.toggleStandbyMode()
                        },
                        onToggleHeadsetLedLight = { enabled ->
                            headsetManager.setLedLightEnabled(enabled)
                        },
                        onSpeakMessage = { text ->
                            val apiKey = if (config.ttsEngine == "minimax") config.minimaxApiKey else null
                            val voiceId = if (config.ttsEngine == "minimax") config.minimaxVoiceId else null
                            soundPlaybackController.speakManualText(text, apiKey, voiceId)
                        },
                        onNavigateToSettings = { showSettings = true },
                        onSelectProfile = { profileId -> viewModel.selectProfile(profileId) },
                        onWorkflowAction = { action ->
                            recordingWorkflow?.let { workflow ->
                                scope.launch {
                                    workflowActionInProgress = true
                                    workflowActionError = null
                                    runCatching {
                                        authClient.recordingWorkflowAction(
                                            gatewayUrl = config.gatewayUrl,
                                            accessToken = config.accessToken,
                                            workflowId = workflow.workflowId,
                                            action = action,
                                            expectedRevision = workflow.revision,
                                            idempotencyKey = UUID.randomUUID().toString(),
                                        )
                                    }.onSuccess(viewModel::applyRecordingWorkflow)
                                        .onFailure { workflowActionError = it.message ?: "工作流操作失败" }
                                    workflowActionInProgress = false
                                }
                            }
                        },
                        onWorkflowTaskAction = { taskId, action ->
                            recordingWorkflow?.let { workflow ->
                                scope.launch {
                                    workflowActionInProgress = true
                                    workflowActionError = null
                                    runCatching {
                                        authClient.recordingWorkflowTaskAction(
                                            gatewayUrl = config.gatewayUrl,
                                            accessToken = config.accessToken,
                                            workflowId = workflow.workflowId,
                                            taskId = taskId,
                                            action = if (action == "retry_blockers") "retry-blockers" else action,
                                            expectedRevision = workflow.revision,
                                            idempotencyKey = UUID.randomUUID().toString(),
                                        )
                                    }.onSuccess(viewModel::applyRecordingWorkflow)
                                        .onFailure { workflowActionError = it.message ?: "任务操作失败" }
                                    workflowActionInProgress = false
                                }
                            }
                        },
                        onWorkflowTaskUpdate = { taskId, prompt, executor, model, sources, maxAttempts ->
                            recordingWorkflow?.let { workflow ->
                                scope.launch {
                                    workflowActionInProgress = true
                                    workflowActionError = null
                                    runCatching {
                                        authClient.updateRecordingWorkflowTask(
                                            gatewayUrl = config.gatewayUrl,
                                            accessToken = config.accessToken,
                                            workflowId = workflow.workflowId,
                                            taskId = taskId,
                                            expectedRevision = workflow.revision,
                                            idempotencyKey = UUID.randomUUID().toString(),
                                            prompt = prompt,
                                            executorHint = executor,
                                            modelHint = model,
                                            sourceConstraints = sources,
                                            maxAttempts = maxAttempts,
                                        )
                                    }.onSuccess(viewModel::applyRecordingWorkflow)
                                        .onFailure { workflowActionError = it.message ?: "任务编辑失败" }
                                    workflowActionInProgress = false
                                }
                            }
                        },
                    )
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleIntent(intent)
    }

    override fun onResume() {
        super.onResume()
        if (::viewModel.isInitialized) {
            viewModel.connect()
        }
    }

    override fun onDestroy() {
        headsetManager.stop()
        if (::viewModel.isInitialized) {
            viewModel.onCleared()
        }
        scope.cancel()
        ttsEngine
            ?.takeIf { it !== systemFallbackTtsEngine }
            ?.release()
        systemFallbackTtsEngine?.release()
        super.onDestroy()
    }

    private fun ensureSystemFallbackTtsEngine(): TtsEngine {
        return systemFallbackTtsEngine ?: TtsEngineFactory.create("system", this).also { engine ->
            configureTtsCallbacks(engine)
            systemFallbackTtsEngine = engine
        }
    }

    private fun configureTtsCallbacks(engine: TtsEngine) {
        (engine as? BaseTtsEngine)?.setCallbacks(
            onStart = { soundPlaybackController.markPlaybackStarted() },
            onDone = { soundPlaybackController.markPlaybackFinished() },
            onError = { error -> soundPlaybackController.markPlaybackFailed(error) },
        )
    }

    private fun shouldFallbackToSystemTts(error: Throwable): Boolean {
        if (currentConfig.ttsEngine != "minimax") return false
        val message = generateSequence(error) { it.cause }
            .joinToString(separator = " ") { it.message.orEmpty() }
            .lowercase()
        val fallbackSignals = listOf(
            "usage limit",
            "provider error",
            "api key",
            "minimax api error",
            "empty response",
            "rejected",
            "failed",
            "audio",
            "playback",
        )
        return message.isBlank() || fallbackSignals.any { signal -> message.contains(signal) }
    }

    private fun handleIntent(intent: Intent?) {
        val uri = intent?.data ?: return
        val uriString = uri.toString()
        if (uriString.startsWith("openclaw://connect")) {
            parseQRPack(uriString) { result ->
                handleQRParseResult(result)
            }
        }
    }

    private fun handleQRParseResult(result: QRParseResult) {
        when (result) {
            is QRParseResult.Success -> {
                scope.launch {
                    val config = settingsManager.configFlow.first()
                    if (config.accessToken.isBlank()) {
                        viewModel.addLocalMessage("请先登录账号，再扫码配对")
                        return@launch
                    }
                    GatewayAuthClient().also { authClient ->
                        try {
                            val outcome = refreshAuthSessionIfNeeded(authClient, force = false)
                            if (!outcome.canUseSession) {
                                viewModel.addLocalMessage(outcome.message ?: "登录状态暂不可用，请稍后重试")
                                return@launch
                            }
                        } finally {
                            authClient.close()
                        }
                    }
                    val error = settingsManager.profileAcceptError(result.gatewayUrl, result.backendId)
                    if (error != null) {
                        viewModel.addLocalMessage(error)
                        return@launch
                    }
                    val profile = settingsManager.upsertScannedProfile(
                        gatewayUrl = result.gatewayUrl,
                        backendId = result.backendId,
                        token = result.token,
                        platform = result.platform,
                        label = result.label,
                    )
                    if (profile == null) {
                        viewModel.addLocalMessage("无法新增 Agent")
                        return@launch
                    }
                    val latestConfig = settingsManager.configFlow.first()
                    GatewayAuthClient().also { authClient ->
                        try {
                            authClient.upsertAccountAgent(
                                gatewayUrl = latestConfig.gatewayUrl.ifBlank { profile.gatewayUrl },
                                accessToken = latestConfig.accessToken,
                                profile = profile.toAccountAgentProfileResult(),
                            )
                        } catch (error: Exception) {
                            viewModel.addLocalMessage("Agent 配置同步失败，请稍后重试")
                            return@launch
                        } finally {
                            authClient.close()
                        }
                    }
                    delay(1000)
                    viewModel.requestPair(profile.id, profile.backendId)
                }
            }
            is QRParseResult.Error -> {
                viewModel.addLocalMessage(result.message)
            }
        }
    }

    private suspend fun refreshAuthSessionIfNeeded(
        authClient: GatewayAuthClient,
        force: Boolean,
    ): AuthRefreshOutcome = authRefreshMutex.withLock {
        val config = settingsManager.configFlow.first()
        if (config.accessToken.isBlank()) {
            return@withLock AuthRefreshOutcome(canUseSession = false, loginRequired = true, message = "请先登录账号")
        }
        if (config.refreshToken.isBlank()) {
            clearStoredAuthSession(config)
            return@withLock AuthRefreshOutcome(canUseSession = false, loginRequired = true, message = "登录状态已过期，请重新登录")
        }
        if (!force && !shouldRefreshAccessToken(config.accessExpiresAt)) {
            return@withLock AuthRefreshOutcome(canUseSession = true)
        }

        val result = runCatching {
            authClient.refresh(
                gatewayUrl = config.gatewayUrl,
                refreshToken = config.refreshToken,
            )
        }
        result.onSuccess { session ->
            settingsManager.updateConfig(
                config.copy(
                    accountId = session.accountId,
                    accessToken = session.accessToken,
                    refreshToken = session.refreshToken,
                    accessExpiresAt = session.accessExpiresAt,
                    refreshExpiresAt = session.refreshExpiresAt,
                )
            )
            return@withLock AuthRefreshOutcome(canUseSession = true)
        }

        val message = result.exceptionOrNull()?.message.orEmpty()
        if (refreshFailureRequiresLogin(message)) {
            clearStoredAuthSession(config)
            return@withLock AuthRefreshOutcome(canUseSession = false, loginRequired = true, message = "登录状态已过期，请重新登录")
        }
        AuthRefreshOutcome(canUseSession = false, message = "网络异常，正在等待登录状态恢复")
    }

    private suspend fun clearStoredAuthSession(config: GatewayConfig) {
        viewModel.disconnect()
        settingsManager.updateConfig(
            config.copy(
                accountId = "",
                accessToken = "",
                refreshToken = "",
                accessExpiresAt = "",
                refreshExpiresAt = "",
            )
        )
    }

    private suspend fun syncAccountAgentsFromServer(
        authClient: GatewayAuthClient,
        gatewayUrl: String,
        accessToken: String,
    ) {
        val remoteAgents = runCatching {
            authClient.listAccountAgents(gatewayUrl, accessToken)
        }.getOrElse { error ->
            viewModel.addLocalMessage("Agent 配置同步失败，已保留本地配置")
            return
        }
        if (remoteAgents.isNotEmpty()) {
            val profiles = remoteAgents
                .filter { it.backendId.isNotBlank() }
                .map { it.toAgentProfile() }
            settingsManager.replaceAccountProfiles(profiles)
            return
        }

        val localProfiles = settingsManager.profilesFlow.first().profiles
            .filter { it.backendId.isNotBlank() }
        for (profile in localProfiles) {
            runCatching {
                authClient.upsertAccountAgent(
                    gatewayUrl = gatewayUrl,
                    accessToken = accessToken,
                    profile = profile.toAccountAgentProfileResult(),
                )
            }
        }
    }

    private fun checkPermissions() {
        val missing = requiredRuntimePermissions().filter { permission ->
            ContextCompat.checkSelfPermission(this, permission) != PackageManager.PERMISSION_GRANTED
        }
        if (missing.isEmpty()) {
            headsetManager.start()
        } else {
            requestPermissions.launch(missing.toTypedArray())
        }
    }

    private fun requiredRuntimePermissions(): List<String> {
        val permissions = mutableListOf(Manifest.permission.RECORD_AUDIO)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            permissions += Manifest.permission.BLUETOOTH_CONNECT
        }
        return permissions
    }
}

private fun AccountAgentProfileResult.toAgentProfile(): AgentProfile =
    AgentProfile(
        id = agentProfileId,
        platform = AgentPlatform.fromWireValue(platform),
        displayName = displayName,
        gatewayUrl = gatewayUrl,
        backendId = backendId,
        backendLabel = backendLabel,
        token = "",
        isPaired = isPaired,
        asrMode = if (asrMode == "backend") "backend" else "router",
        asrProfileId = if (asrMode == "backend") "" else "",
    )

private fun AgentProfile.toAccountAgentProfileResult(): AccountAgentProfileResult =
    AccountAgentProfileResult(
        agentProfileId = id,
        platform = platform.wireValue,
        displayName = resolvedDisplayName,
        gatewayUrl = gatewayUrl,
        backendId = backendId,
        backendLabel = backendLabel ?: resolvedDisplayName,
        isPaired = isPaired,
        asrMode = asrMode,
        sortOrder = 0,
        pinned = false,
    )

private data class AuthRefreshOutcome(
    val canUseSession: Boolean,
    val loginRequired: Boolean = false,
    val message: String? = null,
)
