package com.openclaw.remote

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Bundle
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
    private val scope = kotlinx.coroutines.CoroutineScope(kotlinx.coroutines.Dispatchers.Main)

    private val requestPermission = registerForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { _ ->
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        settingsManager = SettingsManagerAndroid(this)
        audioRecorder = AudioRecorderAndroid(this)

        viewModel = ChatViewModel(settingsManager)

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

                if (showQRScanner) {
                    QRScannerScreen(
                        onQRCodeScanned = { scannedText ->
                            showQRScanner = false
                            parseQRPack(scannedText) { result ->
                                when (result) {
                                    is QRParseResult.Success -> {
                                        scope.launch {
                                            settingsManager.updateConfig(
                                                GatewayConfig(
                                                    gatewayUrl = result.gatewayUrl,
                                                    deviceId = "",
                                                    deviceLabel = "我的手机",
                                                    token = result.token,
                                                    pairedBackendId = null,
                                                    pairedBackendLabel = null
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

    private fun handleIntent(intent: Intent?) {
        val uri = intent?.data ?: return
        val uriString = uri.toString()
        if (uriString.startsWith("openclaw://connect")) {
            parseQRPack(uriString) { result ->
                when (result) {
                    is QRParseResult.Success -> {
                        scope.launch {
                            settingsManager.updateConfig(
                                GatewayConfig(
                                    gatewayUrl = result.gatewayUrl,
                                    deviceId = "",
                                    deviceLabel = "我的手机",
                                    token = result.token,
                                    pairedBackendId = null,
                                    pairedBackendLabel = null
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
        }
    }

    private fun checkPermissions() {
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO)
            != PackageManager.PERMISSION_GRANTED) {
            requestPermission.launch(Manifest.permission.RECORD_AUDIO)
        }
    }
}
