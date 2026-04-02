package com.openclaw.remote

import android.Manifest
import android.content.pm.PackageManager
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.ContextCompat
import com.openclaw.remote.ui.screen.MainScreen
import com.openclaw.remote.ui.theme.MochiTheme

class MainActivity : ComponentActivity() {
    private lateinit var wsManager: WebSocketManager
    private lateinit var audioRecorder: AudioRecorder

    private val requestPermission = registerForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { isGranted ->
        if (!isGranted) {
            // 权限被拒绝，录音功能不可用
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        wsManager = WebSocketManager("192.168.1.14", 8765)
        audioRecorder = AudioRecorder(this)

        checkPermissions()

        setContent {
            // MainScreen 自己管理主题状态并应用 MochiTheme
            MainScreen(wsManager, audioRecorder)
        }
    }

    private fun checkPermissions() {
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO)
            != PackageManager.PERMISSION_GRANTED) {
            requestPermission.launch(Manifest.permission.RECORD_AUDIO)
        }
    }
}
