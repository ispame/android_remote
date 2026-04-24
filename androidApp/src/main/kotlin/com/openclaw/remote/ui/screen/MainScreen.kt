package com.openclaw.remote.ui.screen

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.*
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.filled.DarkMode
import androidx.compose.material.icons.filled.Keyboard
import androidx.compose.material.icons.filled.LightMode
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.openclaw.remote.audio.AudioRecorder
import com.openclaw.remote.data.ChatMessage
import com.openclaw.remote.domain.ConnectionState
import com.openclaw.remote.domain.PairingState
import com.openclaw.remote.ui.theme.MochiTheme
import com.openclaw.remote.viewmodel.ChatViewModel
import kotlin.math.roundToInt

@Composable
fun MainScreen(
    messages: List<ChatMessage>,
    isRecording: Boolean,
    connectionState: ConnectionState,
    pairingState: PairingState,
    pairedBackendLabel: String?,
    isDark: Boolean,
    isLoadingHistory: Boolean,
    hasMoreHistory: Boolean,
    viewModel: ChatViewModel,
    audioRecorder: AudioRecorder,
    onToggleTheme: () -> Unit,
    onNavigateToSettings: () -> Unit = {},
) {
    val colors = MochiTheme.colors
    val listState = rememberLazyListState()

    LaunchedEffect(Unit) {
        viewModel.connect()
    }

    LaunchedEffect(messages.size) {
        if (messages.isNotEmpty()) {
            listState.animateScrollToItem(messages.size - 1)
        }
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(colors.background)
            .imePadding()
    ) {
        TopBar(
            connectionState = connectionState,
            pairingState = pairingState,
            pairedBackendLabel = pairedBackendLabel,
            isDark = isDark,
            onToggleTheme = onToggleTheme,
            onNavigateToSettings = onNavigateToSettings,
            colors = colors,
        )

        HorizontalDivider(color = colors.divider, thickness = 0.5.dp)

        Box(modifier = Modifier.weight(1f)) {
            LazyColumn(
                state = listState,
                modifier = Modifier
                    .fillMaxSize()
                    .padding(horizontal = 16.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp),
                contentPadding = PaddingValues(vertical = 16.dp),
                reverseLayout = false,
            ) {
                if (hasMoreHistory) {
                    item {
                        Box(
                            modifier = Modifier.fillMaxWidth(),
                            contentAlignment = Alignment.Center
                        ) {
                            if (isLoadingHistory) {
                                CircularProgressIndicator(
                                    modifier = Modifier.size(20.dp),
                                    strokeWidth = 2.dp,
                                    color = colors.accent,
                                )
                            } else {
                                TextButton(onClick = { viewModel.loadMoreHistory() }) {
                                    Text(
                                        text = "查看历史消息 ↑",
                                        fontSize = 13.sp,
                                        color = colors.textSecondary,
                                    )
                                }
                            }
                        }
                    }
                }

                items(messages) { msg ->
                    val isUser = msg.senderId == "user"
                    MessageBubble(
                        message = ChatMessage(msg.content, msg.timestamp, msg.senderId),
                        isUser = isUser,
                    )
                }
            }

            if (pairingState != PairingState.PAIRED) {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(horizontal = 16.dp),
                    contentAlignment = Alignment.Center
                ) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Text(
                            text = "请先扫码配对 OpenClaw",
                            fontSize = 16.sp,
                            color = colors.textSecondary,
                        )
                        Spacer(modifier = Modifier.height(8.dp))
                        TextButton(onClick = onNavigateToSettings) {
                            Text("去设置", fontSize = 14.sp)
                        }
                    }
                }
            }
        }

        InputArea(
            isRecording = isRecording,
            colors = colors,
            viewModel = viewModel,
            audioRecorder = audioRecorder,
            pairingState = pairingState,
        )
    }
}

@Composable
private fun TopBar(
    connectionState: ConnectionState,
    pairingState: PairingState,
    pairedBackendLabel: String?,
    isDark: Boolean,
    onToggleTheme: () -> Unit,
    onNavigateToSettings: () -> Unit,
    colors: MochiColors,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(colors.surface)
            .padding(horizontal = 12.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            text = "OpenClaw Remote",
            fontSize = 13.sp,
            color = colors.textSecondary,
        )

        Spacer(modifier = Modifier.width(8.dp))

        val (statusColor, statusText) = when {
            pairingState == PairingState.PAIRED -> colors.onlineGreen to "已配对${pairedBackendLabel?.let { " · $it" } ?: ""}"
            connectionState == ConnectionState.REGISTERED -> colors.accent to "已连接，请扫码"
            connectionState == ConnectionState.CONNECTED -> colors.accent to "连接中..."
            connectionState == ConnectionState.CONNECTING -> colors.accent to "连接中..."
            else -> colors.recordingRed to "未连接"
        }
        Text(
            text = "• $statusText",
            fontSize = 11.sp,
            color = statusColor,
        )

        Spacer(modifier = Modifier.weight(1f))

        Box(
            modifier = Modifier
                .size(32.dp)
                .clip(CircleShape)
                .clickable(onClick = onToggleTheme),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                imageVector = if (isDark) Icons.Filled.LightMode else Icons.Filled.DarkMode,
                contentDescription = if (isDark) "切换到浅色模式" else "切换到深色模式",
                tint = if (isDark) Color(0xFFE8A87C) else Color(0xFFB85C38),
                modifier = Modifier.size(20.dp),
            )
        }

        IconButton(
            onClick = onNavigateToSettings,
            modifier = Modifier.size(32.dp),
        ) {
            Icon(
                imageVector = Icons.Filled.Settings,
                contentDescription = "设置",
                tint = colors.icon,
                modifier = Modifier.size(20.dp),
            )
        }
    }
}

private enum class InputMode { VOICE, TEXT }

@Composable
private fun InputArea(
    isRecording: Boolean,
    colors: MochiColors,
    viewModel: ChatViewModel,
    audioRecorder: AudioRecorder,
    pairingState: PairingState = PairingState.UNPAIRED,
) {
    var inputMode by rememberSaveable { mutableStateOf(InputMode.VOICE) }

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(colors.surface)
    ) {
        HorizontalDivider(color = colors.divider, thickness = 0.5.dp)

        if (inputMode == InputMode.TEXT) {
            TextInputRow(
                inputMode = inputMode,
                onSend = { text ->
                    viewModel.sendText(text)
                },
                onSwitchToVoice = { inputMode = InputMode.VOICE },
                colors = colors,
            )
        } else {
            VoiceInputRow(
                isRecording = isRecording,
                onMicPress = {
                    if (!isRecording) {
                        audioRecorder.startRecording()
                    }
                },
                onMicRelease = { cancelled ->
                    if (isRecording) {
                        audioRecorder.stopRecording { audioData ->
                            if (!cancelled) {
                                viewModel.sendAudio(audioData)
                            }
                        }
                    }
                },
                onSwitchToText = { inputMode = InputMode.TEXT },
                colors = colors,
            )
        }

        Spacer(modifier = Modifier.height(8.dp))
    }
}

@Composable
private fun TextInputRow(
    inputMode: InputMode,
    onSend: (String) -> Unit,
    onSwitchToVoice: () -> Unit,
    colors: MochiColors,
) {
    var textFieldValue by remember { mutableStateOf(TextFieldValue()) }

    LaunchedEffect(inputMode) {
        textFieldValue = TextFieldValue()
    }

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        IconButton(
            onClick = onSwitchToVoice,
            modifier = Modifier.size(44.dp),
        ) {
            Icon(
                imageVector = Icons.Filled.Mic,
                contentDescription = "切换到语音",
                tint = colors.icon,
                modifier = Modifier.size(22.dp),
            )
        }

        Spacer(modifier = Modifier.width(8.dp))

        Box(
            modifier = Modifier
                .weight(1f)
                .height(56.dp)
                .clip(RoundedCornerShape(22.dp))
                .background(colors.inputBg)
                .border(1.dp, colors.inputBorder, RoundedCornerShape(22.dp))
                .padding(horizontal = 16.dp),
            contentAlignment = Alignment.CenterStart,
        ) {
            if (textFieldValue.text.isEmpty()) {
                Text(
                    text = "输入消息...",
                    fontSize = 15.sp,
                    color = colors.inputPlaceholder,
                )
            }
            BasicTextField(
                value = textFieldValue,
                onValueChange = { newValue ->
                    textFieldValue = newValue
                },
                modifier = Modifier.fillMaxWidth(),
                textStyle = TextStyle(fontSize = 15.sp, color = colors.inputText),
                cursorBrush = SolidColor(colors.primary),
                singleLine = false,
                maxLines = 3,
            )
        }

        Spacer(modifier = Modifier.width(8.dp))

        SendButton(
            text = textFieldValue.text,
            onClick = {
                val trimmed = textFieldValue.text.trim()
                if (trimmed.isNotEmpty()) {
                    onSend(trimmed)
                    textFieldValue = TextFieldValue()
                }
            },
            colors = colors,
        )
    }
}

@Composable
private fun SendButton(
    text: String,
    onClick: () -> Unit,
    colors: MochiColors,
) {
    Box(
        modifier = Modifier
            .size(44.dp)
            .clip(CircleShape)
            .background(if (text.isNotBlank()) colors.primary else colors.inputBorder)
            .clickable(enabled = text.isNotBlank(), onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Icon(
            imageVector = Icons.AutoMirrored.Filled.Send,
            contentDescription = "发送",
            tint = if (text.isNotBlank()) colors.onPrimary else colors.textSecondary,
            modifier = Modifier.size(18.dp),
        )
    }
}

@Composable
private fun VoiceInputRow(
    isRecording: Boolean,
    onMicPress: () -> Unit,
    onMicRelease: (cancelled: Boolean) -> Unit,
    onSwitchToText: () -> Unit,
    colors: MochiColors,
) {
    var dragOffsetY by remember { mutableFloatStateOf(0f) }
    var isDragging by remember { mutableStateOf(false) }

    val isCancelled = dragOffsetY < -80f && isDragging

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 12.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            IconButton(
                onClick = onSwitchToText,
                modifier = Modifier.size(44.dp),
            ) {
                Icon(
                    imageVector = Icons.Filled.Keyboard,
                    contentDescription = "切换到键盘",
                    tint = colors.icon,
                    modifier = Modifier.size(22.dp),
                )
            }

            Spacer(modifier = Modifier.weight(1f))

            VoiceMicButton(
                isRecording = isRecording,
                isCancelled = isCancelled,
                isDragging = isDragging,
                dragOffsetY = dragOffsetY,
                onPress = onMicPress,
                onRelease = { realOffsetY, didDrag ->
                    val cancelled = didDrag && realOffsetY < -80f
                    dragOffsetY = 0f
                    isDragging = false
                    onMicRelease(cancelled)
                },
                onDrag = { delta ->
                    dragOffsetY += delta
                    isDragging = dragOffsetY < -30f
                },
                colors = colors,
            )

            Spacer(modifier = Modifier.weight(1f))

            Spacer(modifier = Modifier.size(44.dp))
        }

        AnimatedVisibility(
            visible = isRecording,
            enter = fadeIn() + slideInVertically { it },
            exit = fadeOut() + slideOutVertically { it },
        ) {
            VoiceRecordingHint(
                isCancelled = isCancelled,
                isDragging = isDragging,
                dragOffsetY = dragOffsetY,
                colors = colors,
            )
        }
    }
}

@Composable
private fun VoiceRecordingHint(
    isCancelled: Boolean,
    isDragging: Boolean,
    dragOffsetY: Float,
    colors: MochiColors,
) {
    val cancelProgress = (-dragOffsetY / 80f).coerceIn(0f, 1f)

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(top = 8.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        if (isDragging) {
            Box(
                modifier = Modifier
                    .width(120.dp)
                    .height(3.dp)
                    .clip(RoundedCornerShape(2.dp))
                    .background(colors.inputBorder),
            ) {
                Box(
                    modifier = Modifier
                        .fillMaxHeight()
                        .fillMaxWidth(cancelProgress)
                        .clip(RoundedCornerShape(2.dp))
                        .background(colors.recordingRed),
                )
            }
            Spacer(modifier = Modifier.height(4.dp))
        }

        Text(
            text = when {
                isCancelled -> "松开取消"
                isDragging -> "上划取消 ↓"
                else -> "松手发送，上滑取消 ↑"
            },
            fontSize = 12.sp,
            color = if (isCancelled) colors.recordingRed else colors.textSecondary,
        )
    }
}

@Composable
private fun VoiceMicButton(
    isRecording: Boolean,
    isCancelled: Boolean,
    isDragging: Boolean,
    dragOffsetY: Float,
    onPress: () -> Unit,
    onRelease: (realOffsetY: Float, didDrag: Boolean) -> Unit,
    onDrag: (Float) -> Unit,
    colors: MochiColors,
) {
    val animatedScale by animateFloatAsState(
        targetValue = if (isRecording) 1.15f else 1f,
        animationSpec = spring(dampingRatio = Spring.DampingRatioMediumBouncy),
        label = "micScale",
    )

    val animatedOffsetY by animateFloatAsState(
        targetValue = if (isDragging) dragOffsetY.coerceAtMost(0f) else 0f,
        animationSpec = spring(dampingRatio = Spring.DampingRatioNoBouncy),
        label = "dragOffset",
    )

    val backgroundColor = when {
        isCancelled -> colors.recordingRed.copy(alpha = 0.8f)
        isRecording -> colors.recordingRed
        else -> colors.secondary
    }

    val iconRotation by animateFloatAsState(
        targetValue = if (isCancelled) 45f else 0f,
        animationSpec = spring(dampingRatio = Spring.DampingRatioMediumBouncy),
        label = "iconRotate",
    )

    Box(
        modifier = Modifier
            .size(56.dp)
            .offset { IntOffset(0, animatedOffsetY.roundToInt()) }
            .scale(animatedScale)
            .clip(CircleShape)
            .background(backgroundColor)
            .pointerInput(isRecording) {
                var didDrag = false
                var realOffsetY = 0f
                detectDragGestures(
                    onDragStart = {
                        didDrag = false
                        realOffsetY = 0f
                        onPress()
                    },
                    onDragEnd = {
                        onRelease(realOffsetY, didDrag)
                    },
                    onDragCancel = {
                        onRelease(realOffsetY, didDrag)
                    },
                    onDrag = { change, dragAmount ->
                        change.consume()
                        realOffsetY += dragAmount.y
                        if (dragAmount.y < -5f || dragAmount.y > 5f) {
                            didDrag = true
                        }
                        onDrag(dragAmount.y)
                    },
                )
            },
        contentAlignment = Alignment.Center,
    ) {
        Icon(
            imageVector = Icons.Filled.Mic,
            contentDescription = "按住说话",
            tint = if (isRecording) Color.White else colors.onSecondary,
            modifier = Modifier
                .size(24.dp)
                .rotate(iconRotation),
        )
    }
}
