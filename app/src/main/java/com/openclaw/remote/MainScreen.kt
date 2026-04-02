package com.openclaw.remote

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp

@Composable
fun MainScreen(wsManager: WebSocketManager, audioRecorder: AudioRecorder) {
    var textInput by remember { mutableStateOf("") }
    val messages by wsManager.messages.collectAsState()
    val isRecording by audioRecorder.isRecording.collectAsState()

    LaunchedEffect(Unit) {
        wsManager.connect()
    }

    Column(modifier = Modifier.fillMaxSize().padding(16.dp)) {
        Text("OpenClaw Remote", style = MaterialTheme.typography.headlineMedium)

        Spacer(modifier = Modifier.height(16.dp))

        LazyColumn(
            modifier = Modifier.weight(1f).fillMaxWidth(),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            items(messages) { msg ->
                MessageItem(msg)
            }
        }

        Spacer(modifier = Modifier.height(16.dp))

        Row(modifier = Modifier.fillMaxWidth()) {
            TextField(
                value = textInput,
                onValueChange = { textInput = it },
                modifier = Modifier.weight(1f),
                placeholder = { Text("输入消息") }
            )
            Spacer(modifier = Modifier.width(8.dp))
            Button(onClick = {
                if (textInput.isNotEmpty()) {
                    wsManager.sendText(textInput)
                    textInput = ""
                }
            }) {
                Text("发送")
            }
        }

        Spacer(modifier = Modifier.height(16.dp))

        Button(
            onClick = {
                if (isRecording) {
                    audioRecorder.stopRecording { audioData ->
                        wsManager.sendAudio(audioData)
                    }
                } else {
                    audioRecorder.startRecording()
                }
            },
            modifier = Modifier.fillMaxWidth()
        ) {
            Text(if (isRecording) "停止录音" else "按住说话")
        }
    }
}

@Composable
fun MessageItem(message: ChatMessage) {
    Card(modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(12.dp)) {
            Text(message.content, style = MaterialTheme.typography.bodyMedium)
            Text(
                message.timestamp,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}

data class ChatMessage(val content: String, val timestamp: String)
