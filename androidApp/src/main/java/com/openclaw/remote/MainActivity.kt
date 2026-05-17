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
import com.openclaw.remote.audio.AudioRecorderAndroid
import com.openclaw.remote.data.GatewayConfig
import com.openclaw.remote.data.SettingsManagerAndroid
import com.openclaw.remote.headset.A9UltraSppManager
import com.openclaw.remote.headset.AssistantSpeechTrigger
import com.openclaw.remote.headset.BaseTtsEngine
import com.openclaw.remote.headset.SoundPlaybackController
import com.openclaw.remote.headset.TtsEngine
import com.openclaw.remote.headset.TtsEngineFactory
import com.openclaw.remote.ui.screen.MainScreen
import com.openclaw.remote.ui.screen.QRParseResult
import com.openclaw.remote.ui.screen.SettingsScreen
import com.openclaw.remote.ui.screen.QRScannerScreen
import com.openclaw.remote.ui.screen.parseQRPack
import com.openclaw.remote.ui.theme.MochiTheme
import com.openclaw.remote.viewmodel.ChatViewModel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

class MainActivity : ComponentActivity() {

    private lateinit var viewModel: ChatViewModel
    private lateinit var settingsManager: SettingsManagerAndroid
    private lateinit var audioRecorder: AudioRecorderAndroid
    private lateinit var headsetManager: A9UltraSppManager
    private lateinit var soundPlaybackController: SoundPlaybackController
    private var ttsEngine: TtsEngine? = null
    private var currentConfig: GatewayConfig = GatewayConfig()
    private val scope = kotlinx.coroutines.CoroutineScope(kotlinx.coroutines.Dispatchers.Main)

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
            val assistantSpeechTrigger = remember { AssistantSpeechTrigger() }

            MochiTheme(darkTheme = isDark) {
                val connectionState by viewModel.connectionState.collectAsState()
                val pairingState by viewModel.pairingState.collectAsState()
                val pairedBackendLabel by viewModel.pairedBackendLabel.collectAsState()
                val isRecording by audioRecorder.isRecording.collectAsState()
                val messages by viewModel.messages.collectAsState()
                val profiles by viewModel.profiles.collectAsState()
                val selectedProfileId by viewModel.selectedProfileId.collectAsState()
                val unreadCounts by viewModel.unreadCounts.collectAsState()
                val isLoadingHistory by viewModel.isLoadingHistory.collectAsState()
                val hasMoreHistory by viewModel.hasMoreHistory.collectAsState()
                val headsetState by headsetManager.state.collectAsState()
                val config by settingsManager.configFlow.collectAsState(initial = currentConfig)
                val soundPlaybackEnabled by settingsManager.soundPlaybackEnabledFlow.collectAsState(initial = true)
                val playbackState by soundPlaybackController.state.collectAsState()

                LaunchedEffect(soundPlaybackEnabled) {
                    soundPlaybackController.syncSoundPlaybackEnabled(soundPlaybackEnabled)
                }

                // 监听配置变化，重新初始化 TTS 引擎
                LaunchedEffect(config.ttsEngine) {
                    ttsEngine?.release()
                    soundPlaybackController.markPlaybackFinished()
                    ttsEngine = TtsEngineFactory.create(config.ttsEngine, this@MainActivity).also { engine ->
                        (engine as? BaseTtsEngine)?.setCallbacks(
                            onStart = { soundPlaybackController.markPlaybackStarted() },
                            onDone = { soundPlaybackController.markPlaybackFinished() },
                        )
                    }
                }

                // 监听当前会话的新 assistant 回复，播放 TTS。历史消息和设置变更不重播。
                LaunchedEffect(messages) {
                    val msg = assistantSpeechTrigger.onMessagesChanged(messages) ?: return@LaunchedEffect
                    val apiKey = if (config.ttsEngine == "minimax") config.minimaxApiKey else null
                    val voiceId = if (config.ttsEngine == "minimax") config.minimaxVoiceId else null
                    soundPlaybackController.speakAssistantReply(msg.content, apiKey, voiceId)
                }

                if (showQRScanner) {
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
                        onNavigateToQRScanner = { showQRScanner = true }
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
                        unreadCounts = unreadCounts,
                        isDark = isDark,
                        isLoadingHistory = isLoadingHistory,
                        hasMoreHistory = hasMoreHistory,
                        headsetStatusLabel = headsetState.label,
                        soundPlaybackEnabled = playbackState.soundPlaybackEnabled,
                        isPlaybackSpeaking = playbackState.isSpeaking,
                        viewModel = viewModel,
                        audioRecorder = audioRecorder,
                        onToggleTheme = { isDark = !isDark },
                        onToggleSoundPlayback = {
                            soundPlaybackController.setSoundPlaybackEnabled(!playbackState.soundPlaybackEnabled)
                        },
                        onInterruptPlayback = {
                            soundPlaybackController.interruptCurrentPlayback()
                        },
                        onNavigateToSettings = { showSettings = true },
                        onSelectProfile = { profileId -> viewModel.selectProfile(profileId) },
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
        ttsEngine?.release()
        super.onDestroy()
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
                    delay(1000)
                    viewModel.requestPair(profile.id, profile.backendId)
                }
            }
            is QRParseResult.Error -> {
                viewModel.addLocalMessage(result.message)
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
