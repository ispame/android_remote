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
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch

class MainActivity : ComponentActivity() {

    private lateinit var viewModel: ChatViewModel
    private lateinit var settingsManager: SettingsManagerAndroid
    private lateinit var audioRecorder: AudioRecorderAndroid
    private lateinit var headsetManager: A9UltraSppManager
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

        // 初始化 TTS 引擎和配置
        scope.launch {
            settingsManager.configFlow.collect { config ->
                currentConfig = config
            }
        }
        headsetManager = A9UltraSppManager(this, onAudioReady = { audioData ->
            Log.i("A9UltraSPP", "headset audio ready wav=${audioData.size}")
            viewModel.sendAudio(audioData)
        })

        checkPermissions()
        handleIntent(intent)

        setContent {
            val systemDark = isSystemInDarkTheme()
            var isDark by rememberSaveable(systemDark) { mutableStateOf(systemDark) }
            var showSettings by remember { mutableStateOf(false) }
            var showQRScanner by remember { mutableStateOf(false) }

            MochiTheme(darkTheme = isDark) {
                val connectionState by viewModel.connectionState.collectAsState()
                val pairingState by viewModel.pairingState.collectAsState()
                val pairedBackendLabel by viewModel.pairedBackendLabel.collectAsState()
                val isRecording by audioRecorder.isRecording.collectAsState()
                val messages by viewModel.messages.collectAsState()
                val isLoadingHistory by viewModel.isLoadingHistory.collectAsState()
                val hasMoreHistory by viewModel.hasMoreHistory.collectAsState()
                val headsetState by headsetManager.state.collectAsState()
                var config by remember { mutableStateOf(currentConfig) }

                // 监听配置变化，重新初始化 TTS 引擎
                LaunchedEffect(config.ttsEngine) {
                    ttsEngine?.release()
                    ttsEngine = TtsEngineFactory.create(config.ttsEngine, this@MainActivity)
                }

                // 监听新消息，播放 TTS
                LaunchedEffect(messages, config) {
                    val lastMsg = messages.lastOrNull()
                    if (lastMsg != null && lastMsg.senderId == "assistant" && lastMsg.content.isNotBlank()) {
                        val apiKey = if (config.ttsEngine == "minimax") config.minimaxApiKey else null
                        ttsEngine?.speak(lastMsg.content, apiKey)
                    }
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
                        connectionState = connectionState,
                        pairingState = pairingState,
                        pairedBackendLabel = pairedBackendLabel,
                        isDark = isDark,
                        onToggleTheme = { isDark = !isDark },
                        onRequestPair = { backendId ->
                            viewModel.requestPair(backendId)
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
                        isDark = isDark,
                        isLoadingHistory = isLoadingHistory,
                        hasMoreHistory = hasMoreHistory,
                        headsetStatusLabel = headsetState.label,
                        viewModel = viewModel,
                        audioRecorder = audioRecorder,
                        onToggleTheme = { isDark = !isDark },
                        onNavigateToSettings = { showSettings = true }
                    )
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleIntent(intent)
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
                    val current = settingsManager.configFlow.first()
                    settingsManager.updateConfig(
                        GatewayConfig(
                            gatewayUrl = result.gatewayUrl,
                            deviceId = current.deviceId,
                            deviceLabel = current.deviceLabel.ifEmpty { "我的手机" },
                            token = result.token,
                            pairedBackendId = result.backendId,
                            pairedBackendLabel = result.backendId,
                            asrMode = current.asrMode,
                            asrProfileId = current.asrProfileId,
                        )
                    )
                    delay(1000)
                    viewModel.requestPair(result.backendId)
                }
            }
            is QRParseResult.Error -> {
                // Handle error
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
