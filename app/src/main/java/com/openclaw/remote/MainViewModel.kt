package com.openclaw.remote

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import kotlinx.coroutines.flow.StateFlow

class MainViewModel(application: Application) : AndroidViewModel(application) {
    private val sessionManager = RemoteSessionManager(application, SettingsStore(application))

    val settings: StateFlow<RemoteSettings> = sessionManager.settings
    val messages: StateFlow<List<ChatMessage>> = sessionManager.messages
    val statusText: StateFlow<String> = sessionManager.statusText
    val isConnected: StateFlow<Boolean> = sessionManager.isConnected
    val errorText: StateFlow<String?> = sessionManager.errorText
    val asrPartialText: StateFlow<String> = sessionManager.asrPartialText
    val streamingAssistantText: StateFlow<String?> = sessionManager.streamingAssistantText
    val supportsStreamingAudio: StateFlow<Boolean> = sessionManager.supportsStreamingAudio

    init {
        sessionManager.connect()
    }

    fun selectBackend(backend: BackendKind) {
        sessionManager.updateSettings { current ->
            val shouldReplacePort =
                current.portText.isBlank() || current.portText == defaultPortFor(current.backend)
            current.copy(
                backend = backend,
                portText = if (shouldReplacePort) defaultPortFor(backend) else current.portText,
            )
        }
    }

    fun updateHost(host: String) {
        sessionManager.updateSettings { it.copy(host = host) }
    }

    fun updatePort(portText: String) {
        sessionManager.updateSettings { it.copy(portText = portText) }
    }

    fun updateUseTls(useTls: Boolean) {
        sessionManager.updateSettings { it.copy(useTls = useTls) }
    }

    fun updateNanobotPath(path: String) {
        sessionManager.updateSettings { it.copy(nanobotPath = path) }
    }

    fun updateOpenClawSharedToken(token: String) {
        sessionManager.updateSettings { it.copy(openClawSharedToken = token) }
    }

    fun updateOpenClawBootstrapToken(token: String) {
        sessionManager.updateSettings { it.copy(openClawBootstrapToken = token) }
    }

    fun updateOpenClawPassword(password: String) {
        sessionManager.updateSettings { it.copy(openClawPassword = password) }
    }

    fun updateOpenClawSessionKey(sessionKey: String) {
        sessionManager.updateSettings { it.copy(openClawSessionKey = sessionKey) }
    }

    fun connect() {
        sessionManager.connect()
    }

    fun disconnect() {
        sessionManager.disconnect()
    }

    fun sendText(text: String) {
        sessionManager.sendText(text)
    }

    fun startVoiceStreaming(audioRecorder: AudioRecorder) {
        if (!sessionManager.startAudioStream()) {
            return
        }
        audioRecorder.startStreaming(object : AudioChunkCallback {
            override fun onChunk(chunk: ByteArray, isLast: Boolean) {
                sessionManager.sendAudioChunk(chunk, isLast)
            }
        })
    }

    fun stopVoiceStreaming(audioRecorder: AudioRecorder) {
        audioRecorder.stopStreaming()
        sessionManager.endAudioStream()
    }

    override fun onCleared() {
        sessionManager.disconnect()
        super.onCleared()
    }
}
