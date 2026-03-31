package com.openclaw.remote

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp

@Composable
fun MainScreen(wsManager: WebSocketManager, audioRecorder: AudioRecorder) {
    var textInput by remember { mutableStateOf("") }
    val messages by wsManager.messages.collectAsState()
    val isRecording by audioRecorder.isRecording.collectAsState()
    val isStreaming by audioRecorder.isStreaming.collectAsState()

    // ASR 实时识别文字
    var asrPartialText by remember { mutableStateOf("") }

    // 监听 ASR 回调
    LaunchedEffect(Unit) {
        wsManager.onAsrPartial = { partial ->
            asrPartialText = partial
        }
        wsManager.onAsrDone = {
            asrPartialText = ""
        }
    }

    LaunchedEffect(Unit) {
        wsManager.connect()
    }

    Column(modifier = Modifier.fillMaxSize().padding(16.dp)) {
        Text("OpenClaw Remote", style = MaterialTheme.typography.headlineMedium)

        Spacer(modifier = Modifier.height(16.dp))

        // ─── ASR 实时识别区域 ───────────────────────────────────────
        if (asrPartialText.isNotEmpty()) {
            Card(
                modifier = Modifier.fillMaxWidth(),
                colors = CardDefaults.cardColors(
                    containerColor = MaterialTheme.colorScheme.tertiaryContainer
                )
            ) {
                Row(
                    modifier = Modifier.padding(12.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(16.dp),
                        strokeWidth = 2.dp
                    )
                    Spacer(modifier = Modifier.width(8.dp))
                    Text(
                        "识别中: $asrPartialText",
                        style = MaterialTheme.typography.bodyMedium
                    )
                }
            }
            Spacer(modifier = Modifier.height(8.dp))
        }

        // ─── 消息列表 ────────────────────────────────────────────────
        LazyColumn(
            modifier = Modifier.weight(1f).fillMaxWidth(),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            items(messages) { msg ->
                MessageItem(msg)
            }
        }

        Spacer(modifier = Modifier.height(16.dp))

        // ─── 文字输入 ────────────────────────────────────────────────
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

        // ─── 录音按钮（流式模式）────────────────────────────────────
        Button(
            onClick = {
                if (isStreaming) {
                    // 停止流式录音
                    audioRecorder.stopStreaming()
                    wsManager.endAudioStream()
                } else {
                    // 开始流式录音
                    wsManager.startAudioStream()
                    audioRecorder.startStreaming(object : AudioChunkCallback {
                        override fun onChunk(chunk: ByteArray, isLast: Boolean) {
                            wsManager.sendAudioChunk(chunk, isLast)
                        }
                    })
                }
            },
            modifier = Modifier.fillMaxWidth(),
            colors = if (isStreaming) {
                ButtonDefaults.buttonColors(
                    containerColor = MaterialTheme.colorScheme.error
                )
            } else {
                ButtonDefaults.buttonColors()
            }
        ) {
            Text(if (isStreaming) "松开停止" else "按住说话")
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
