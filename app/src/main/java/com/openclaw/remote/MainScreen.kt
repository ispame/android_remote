package com.openclaw.remote

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp

@Composable
fun MainScreen(viewModel: MainViewModel, audioRecorder: AudioRecorder) {
    var textInput by remember { mutableStateOf("") }
    var settingsExpanded by remember { mutableStateOf(true) }
    val focusManager = LocalFocusManager.current

    val settings by viewModel.settings.collectAsState()
    val messages by viewModel.messages.collectAsState()
    val statusText by viewModel.statusText.collectAsState()
    val isConnected by viewModel.isConnected.collectAsState()
    val errorText by viewModel.errorText.collectAsState()
    val asrPartialText by viewModel.asrPartialText.collectAsState()
    val streamingAssistantText by viewModel.streamingAssistantText.collectAsState()
    val supportsStreamingAudio by viewModel.supportsStreamingAudio.collectAsState()
    val isStreaming by audioRecorder.isStreaming.collectAsState()

    LaunchedEffect(supportsStreamingAudio, isConnected) {
        if ((!supportsStreamingAudio || !isConnected) && isStreaming) {
            viewModel.stopVoiceStreaming(audioRecorder)
        }
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(16.dp),
    ) {
        Text("OpenClaw Remote", style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Bold)

        Spacer(modifier = Modifier.height(12.dp))

        ConnectionCard(
            settings = settings,
            statusText = statusText,
            isConnected = isConnected,
            errorText = errorText,
            expanded = settingsExpanded,
            onToggleExpanded = { settingsExpanded = !settingsExpanded },
            onSelectBackend = viewModel::selectBackend,
            onHostChange = viewModel::updateHost,
            onPortChange = viewModel::updatePort,
            onUseTlsChange = viewModel::updateUseTls,
            onNanobotPathChange = viewModel::updateNanobotPath,
            onOpenClawSharedTokenChange = viewModel::updateOpenClawSharedToken,
            onOpenClawBootstrapTokenChange = viewModel::updateOpenClawBootstrapToken,
            onOpenClawPasswordChange = viewModel::updateOpenClawPassword,
            onOpenClawSessionKeyChange = viewModel::updateOpenClawSessionKey,
            onConnect = {
                focusManager.clearFocus()
                viewModel.connect()
            },
            onDisconnect = {
                focusManager.clearFocus()
                viewModel.disconnect()
            },
        )

        Spacer(modifier = Modifier.height(12.dp))

        if (asrPartialText.isNotEmpty()) {
            StatusCard(
                label = "识别中",
                content = asrPartialText,
                containerColor = MaterialTheme.colorScheme.tertiaryContainer,
            )
            Spacer(modifier = Modifier.height(8.dp))
        }

        streamingAssistantText?.takeIf { it.isNotBlank() }?.let { streamingText ->
            StatusCard(
                label = "OpenClaw 回复中",
                content = streamingText,
                containerColor = MaterialTheme.colorScheme.secondaryContainer,
            )
            Spacer(modifier = Modifier.height(8.dp))
        }

        LazyColumn(
            modifier = Modifier
                .weight(1f)
                .fillMaxWidth(),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            items(messages) { msg ->
                MessageItem(msg)
            }
        }

        Spacer(modifier = Modifier.height(16.dp))

        Row(modifier = Modifier.fillMaxWidth()) {
            OutlinedTextField(
                value = textInput,
                onValueChange = { textInput = it },
                modifier = Modifier.weight(1f),
                placeholder = { Text("输入消息") },
                singleLine = true,
            )
            Spacer(modifier = Modifier.width(8.dp))
            Button(onClick = {
                if (textInput.isNotEmpty()) {
                    viewModel.sendText(textInput)
                    textInput = ""
                    focusManager.clearFocus()
                }
            }) {
                Text("发送")
            }
        }

        Spacer(modifier = Modifier.height(16.dp))

        if (supportsStreamingAudio) {
            Button(
                onClick = {
                    if (isStreaming) {
                        viewModel.stopVoiceStreaming(audioRecorder)
                    } else {
                        viewModel.startVoiceStreaming(audioRecorder)
                    }
                },
                modifier = Modifier.fillMaxWidth(),
                enabled = isConnected,
                colors = if (isStreaming) {
                    ButtonDefaults.buttonColors(
                        containerColor = MaterialTheme.colorScheme.error,
                    )
                } else {
                    ButtonDefaults.buttonColors()
                },
            ) {
                Text(if (isStreaming) "停止语音发送" else "开始语音发送")
            }
        } else {
            Text(
                "OpenClaw 兼容模式当前先支持文本聊天；语音流仍沿用原来的 Nanobot 协议。",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
private fun ConnectionCard(
    settings: RemoteSettings,
    statusText: String,
    isConnected: Boolean,
    errorText: String?,
    expanded: Boolean,
    onToggleExpanded: () -> Unit,
    onSelectBackend: (BackendKind) -> Unit,
    onHostChange: (String) -> Unit,
    onPortChange: (String) -> Unit,
    onUseTlsChange: (Boolean) -> Unit,
    onNanobotPathChange: (String) -> Unit,
    onOpenClawSharedTokenChange: (String) -> Unit,
    onOpenClawBootstrapTokenChange: (String) -> Unit,
    onOpenClawPasswordChange: (String) -> Unit,
    onOpenClawSessionKeyChange: (String) -> Unit,
    onConnect: () -> Unit,
    onDisconnect: () -> Unit,
) {
    Card(modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(16.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Column(modifier = Modifier.weight(1f)) {
                    Text("连接配置", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                    Text(
                        statusText,
                        style = MaterialTheme.typography.bodySmall,
                        color = if (isConnected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
                TextButton(onClick = onToggleExpanded) {
                    Text(if (expanded) "收起" else "展开")
                }
            }

            if (errorText != null) {
                Spacer(modifier = Modifier.height(8.dp))
                Text(
                    errorText,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.error,
                )
            }

            if (expanded) {
                Spacer(modifier = Modifier.height(12.dp))

                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    BackendChip(
                        selected = settings.backend == BackendKind.NANOBOT,
                        label = "Nanobot",
                        onClick = { onSelectBackend(BackendKind.NANOBOT) },
                    )
                    BackendChip(
                        selected = settings.backend == BackendKind.OPENCLAW,
                        label = "OpenClaw",
                        onClick = { onSelectBackend(BackendKind.OPENCLAW) },
                    )
                }

                Spacer(modifier = Modifier.height(12.dp))

                OutlinedTextField(
                    value = settings.host,
                    onValueChange = onHostChange,
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text("服务器地址") },
                    singleLine = true,
                )

                Spacer(modifier = Modifier.height(8.dp))

                OutlinedTextField(
                    value = settings.portText,
                    onValueChange = onPortChange,
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text("端口") },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                    singleLine = true,
                )

                Spacer(modifier = Modifier.height(8.dp))

                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Column(modifier = Modifier.weight(1f)) {
                        Text("使用 TLS / WSS")
                        Text(
                            if (settings.backend == BackendKind.OPENCLAW) {
                                "公网或 Tailscale 通常应开启"
                            } else {
                                "Nanobot 也可以按需接入 WSS"
                            },
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                    Switch(
                        checked = settings.useTls,
                        onCheckedChange = onUseTlsChange,
                    )
                }

                if (settings.backend == BackendKind.NANOBOT) {
                    Spacer(modifier = Modifier.height(8.dp))
                    OutlinedTextField(
                        value = settings.nanobotPath,
                        onValueChange = onNanobotPathChange,
                        modifier = Modifier.fillMaxWidth(),
                        label = { Text("WebSocket 路径") },
                        singleLine = true,
                    )
                } else {
                    Spacer(modifier = Modifier.height(8.dp))
                    OutlinedTextField(
                        value = settings.openClawSessionKey,
                        onValueChange = onOpenClawSessionKeyChange,
                        modifier = Modifier.fillMaxWidth(),
                        label = { Text("会话 Key") },
                        supportingText = { Text("默认填 main；连接后会自动映射到主会话") },
                        singleLine = true,
                    )

                    Spacer(modifier = Modifier.height(8.dp))
                    SecretField(
                        label = "Shared Token",
                        value = settings.openClawSharedToken,
                        onValueChange = onOpenClawSharedTokenChange,
                    )

                    Spacer(modifier = Modifier.height(8.dp))
                    SecretField(
                        label = "Bootstrap Token",
                        value = settings.openClawBootstrapToken,
                        onValueChange = onOpenClawBootstrapTokenChange,
                    )

                    Spacer(modifier = Modifier.height(8.dp))
                    SecretField(
                        label = "Password",
                        value = settings.openClawPassword,
                        onValueChange = onOpenClawPasswordChange,
                    )
                }

                Spacer(modifier = Modifier.height(12.dp))

                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Button(
                        onClick = onConnect,
                        modifier = Modifier.weight(1f),
                    ) {
                        Text(if (isConnected) "重新连接" else "连接")
                    }
                    OutlinedButton(
                        onClick = onDisconnect,
                        modifier = Modifier.weight(1f),
                    ) {
                        Text("断开")
                    }
                }
            }
        }
    }
}

@Composable
private fun BackendChip(selected: Boolean, label: String, onClick: () -> Unit) {
    val background = if (selected) {
        MaterialTheme.colorScheme.primaryContainer
    } else {
        MaterialTheme.colorScheme.surfaceVariant
    }
    val content = if (selected) {
        MaterialTheme.colorScheme.onPrimaryContainer
    } else {
        MaterialTheme.colorScheme.onSurfaceVariant
    }

    TextButton(
        onClick = onClick,
        modifier = Modifier.background(background, MaterialTheme.shapes.small),
        colors = ButtonDefaults.textButtonColors(contentColor = content),
    ) {
        Text(label)
    }
}

@Composable
private fun SecretField(label: String, value: String, onValueChange: (String) -> Unit) {
    var visible by remember(value) { mutableStateOf(false) }

    OutlinedTextField(
        value = value,
        onValueChange = onValueChange,
        modifier = Modifier.fillMaxWidth(),
        label = { Text(label) },
        visualTransformation = if (visible) VisualTransformation.None else PasswordVisualTransformation(),
        singleLine = true,
        trailingIcon = {
            TextButton(onClick = { visible = !visible }) {
                Text(if (visible) "隐藏" else "显示")
            }
        },
    )
}

@Composable
private fun StatusCard(label: String, content: String, containerColor: Color) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = containerColor),
    ) {
        Column(modifier = Modifier.padding(12.dp)) {
            Text(label, style = MaterialTheme.typography.labelLarge, fontWeight = FontWeight.SemiBold)
            Spacer(modifier = Modifier.height(4.dp))
            Text(content, style = MaterialTheme.typography.bodyMedium)
        }
    }
}

@Composable
fun MessageItem(message: ChatMessage) {
    val containerColor = when (message.role) {
        ChatRole.USER -> MaterialTheme.colorScheme.primaryContainer
        ChatRole.ASSISTANT -> MaterialTheme.colorScheme.secondaryContainer
        ChatRole.SYSTEM -> MaterialTheme.colorScheme.surfaceVariant
    }
    val title = when (message.role) {
        ChatRole.USER -> "我"
        ChatRole.ASSISTANT -> "机器人"
        ChatRole.SYSTEM -> "系统"
    }

    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = containerColor),
    ) {
        Column(modifier = Modifier.padding(12.dp)) {
            Text(title, style = MaterialTheme.typography.labelLarge, fontWeight = FontWeight.SemiBold)
            Spacer(modifier = Modifier.height(4.dp))
            Text(message.content, style = MaterialTheme.typography.bodyMedium)
            Spacer(modifier = Modifier.height(6.dp))
            Text(
                formatChatTimestamp(message.timestampMs),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.End,
                modifier = Modifier.fillMaxWidth(),
            )
        }
    }
}
