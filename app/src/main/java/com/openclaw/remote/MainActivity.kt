package com.openclaw.remote

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.*
import androidx.core.content.ContextCompat
import androidx.lifecycle.ViewModelProvider
import com.openclaw.remote.ui.screen.MainScreen
import com.openclaw.remote.ui.screen.SettingsScreen
import com.openclaw.remote.ui.theme.MochiTheme
import com.openclaw.remote.ui.screen.parseQRPack
import kotlinx.coroutines.launch

class MainActivity : ComponentActivity() {

    private lateinit var viewModel: ChatViewModel
    private lateinit var settingsManager: SettingsManager
    private val scope = kotlinx.coroutines.CoroutineScope(kotlinx.coroutines.Dispatchers.Main)

    private val requestPermission = registerForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { _ ->
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        settingsManager = SettingsManager(this)

        // 从配置变更中恢复 ViewModel，或创建新的
        @Suppress("DEPRECATION")
        val retained = lastCustomNonConfigurationInstance as? ChatViewModel
        viewModel = retained ?: ViewModelProvider(
            this,
            ChatViewModel.Factory(this)
        )[ChatViewModel::class.java]

        checkPermissions()

        // 处理 deep link
        handleIntent(intent)

        setContent {
            MochiTheme {
                var showSettings by remember { mutableStateOf(false) }
                val connectionState by viewModel.connectionState.collectAsState()
                val pairingState by viewModel.pairingState.collectAsState()
                val pairedBackendLabel by viewModel.pairedBackendLabel.collectAsState()

                if (showSettings) {
                    SettingsScreen(
                        settingsManager = settingsManager,
                        connectionState = connectionState,
                        pairingState = pairingState,
                        pairedBackendLabel = pairedBackendLabel,
                        onRequestPair = { backendId ->
                            viewModel.requestPair(backendId)
                            showSettings = false
                        },
                        onUnpair = {
                            viewModel.unpair()
                        },
                        onBack = { showSettings = false }
                    )
                } else {
                    MainScreen(
                        viewModel = viewModel,
                        audioRecorder = AudioRecorder(this),
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
            // Deep link: 自动解析二维码并配对
            parseQRPack(uriString) { result ->
                when (result) {
                    is com.openclaw.remote.ui.screen.QRParseResult.Success -> {
                        scope.launch {
                            settingsManager.updateConfig(
                                GatewayConfig(
                                    gatewayUrl = result.gatewayUrl,
                                    deviceId = "",
                                    deviceLabel = "我的手机",
                                    pairedBackendId = null,
                                    pairedBackendLabel = null
                                )
                            )
                            kotlinx.coroutines.delay(1000)
                            viewModel.requestPair(result.backendId)
                        }
                    }
                    is com.openclaw.remote.ui.screen.QRParseResult.Error -> {
                        // Log error
                    }
                }
            }
        }
    }

    // 配置变更时保留 ViewModel
    override fun onRetainCustomNonConfigurationInstance(): Any = viewModel

    private fun checkPermissions() {
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO)
            != PackageManager.PERMISSION_GRANTED) {
            requestPermission.launch(Manifest.permission.RECORD_AUDIO)
        }
    }
}
