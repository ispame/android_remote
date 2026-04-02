package com.openclaw.remote.ui.screen

import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.DarkMode
import androidx.compose.material.icons.filled.LightMode
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.openclaw.remote.AudioRecorder
import com.openclaw.remote.ChatMessage
import com.openclaw.remote.ConnectionState
import com.openclaw.remote.WebSocketManager
import com.openclaw.remote.ui.theme.MochiColors
import com.openclaw.remote.ui.theme.MochiTheme

@Composable
fun MainScreen(
    wsManager: WebSocketManager,
    audioRecorder: AudioRecorder
) {
    // 主题状态：默认跟随系统，可手动切换
    val systemDark = isSystemInDarkTheme()
    var isDark by rememberSaveable(systemDark) { mutableStateOf(systemDark) }

    MochiTheme(darkTheme = isDark) {
        val colors = MochiTheme.colors

        var textFieldValue by remember { mutableStateOf(TextFieldValue("")) }
        val messages by wsManager.messages.collectAsState()
        val isRecording by audioRecorder.isRecording.collectAsState()
        val connectionState by wsManager.connectionState.collectAsState()
        val listState = rememberLazyListState()

        // 新消息到来时自动滚动到底部
        LaunchedEffect(messages.size) {
            if (messages.isNotEmpty()) {
                listState.animateScrollToItem(messages.size - 1)
            }
        }

        Column(
            modifier = Modifier
                .fillMaxSize()
                .background(colors.background)
        ) {
            // ── 顶栏 ──
            TopBar(
                connectionState = connectionState,
                isDark = isDark,
                onToggleTheme = { isDark = !isDark },
                colors = colors,
            )

            HorizontalDivider(color = colors.divider, thickness = 0.5.dp)

            // ── 消息列表 ──
            LazyColumn(
                state = listState,
                modifier = Modifier
                    .weight(1f)
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp),
                contentPadding = PaddingValues(vertical = 16.dp),
            ) {
                items(messages) { msg ->
                    val isUser = msg.senderId == "user"
                    MessageBubble(
                        message = ChatMessage(msg.content, msg.timestamp, msg.senderId),
                        isUser = isUser,
                    )
                }
            }

            // ── 输入区域 ──
            InputArea(
                textFieldValue = textFieldValue,
                onTextChange = { textFieldValue = it },
                onSend = {
                    val text = textFieldValue.text.trim()
                    if (text.isNotEmpty()) {
                        wsManager.sendText(text)
                        textFieldValue = TextFieldValue("")
                    }
                },
                onMicClick = {
                    if (isRecording) {
                        audioRecorder.stopRecording { audioData ->
                            wsManager.sendAudio(audioData)
                        }
                    } else {
                        audioRecorder.startRecording()
                    }
                },
                isRecording = isRecording,
                colors = colors,
            )
        }
    }
}

// ============================================================
// 顶栏
// ============================================================
@Composable
private fun TopBar(
    connectionState: ConnectionState,
    isDark: Boolean,
    onToggleTheme: () -> Unit,
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

        // 连接状态指示
        val (statusColor, statusText) = when (connectionState) {
            ConnectionState.CONNECTED -> colors.onlineGreen to "已连接"
            ConnectionState.CONNECTING -> colors.accent to "连接中..."
            ConnectionState.DISCONNECTED -> colors.recordingRed to "未连接"
        }
        Text(
            text = "\u2022 $statusText",
            fontSize = 11.sp,
            color = statusColor,
        )

        Spacer(modifier = Modifier.weight(1f))

        // 主题切换按钮
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
    }
}

// ============================================================
// 输入区域
// ============================================================
@Composable
private fun InputArea(
    textFieldValue: TextFieldValue,
    onTextChange: (TextFieldValue) -> Unit,
    onSend: () -> Unit,
    onMicClick: () -> Unit,
    isRecording: Boolean,
    colors: MochiColors,
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(colors.surface)
    ) {
        HorizontalDivider(color = colors.divider, thickness = 0.5.dp)

        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            // 麦克风按钮
            MicButton(
                isRecording = isRecording,
                onClick = onMicClick,
                colors = colors,
            )

            Spacer(modifier = Modifier.width(10.dp))

            // 输入框
            Box(
                modifier = Modifier
                    .weight(1f)
                    .height(44.dp)
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
                    onValueChange = onTextChange,
                    modifier = Modifier.fillMaxWidth(),
                    textStyle = LocalTextStyle.current.copy(
                        fontSize = 15.sp,
                        color = colors.inputText,
                    ),
                    cursorBrush = SolidColor(colors.primary),
                    singleLine = false,
                    maxLines = 3,
                )
            }

            Spacer(modifier = Modifier.width(10.dp))

            // 发送按钮
            SendButton(
                enabled = textFieldValue.text.isNotBlank(),
                onClick = onSend,
                colors = colors,
            )
        }

        // 录音状态提示
        if (isRecording) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 4.dp),
                horizontalArrangement = Arrangement.Center,
            ) {
                PulsingDot(color = colors.recordingRed)
                Spacer(modifier = Modifier.width(6.dp))
                Text(
                    text = "正在录音，点击停止",
                    fontSize = 12.sp,
                    color = colors.recordingRed,
                )
            }
        }

        Spacer(modifier = Modifier.height(8.dp))
    }
}

// ============================================================
// 麦克风按钮
// ============================================================
@Composable
private fun MicButton(
    isRecording: Boolean,
    onClick: () -> Unit,
    colors: MochiColors,
) {
    Box(
        modifier = Modifier
            .size(44.dp)
            .clip(CircleShape)
            .background(if (isRecording) colors.recordingRed else colors.secondary)
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Icon(
            imageVector = if (isRecording) Icons.Filled.Close else Icons.Filled.Mic,
            contentDescription = if (isRecording) "停止录音" else "按住说话",
            tint = if (isRecording) Color.White else colors.onSecondary,
            modifier = Modifier.size(20.dp),
        )
    }
}

// ============================================================
// 发送按钮
// ============================================================
@Composable
private fun SendButton(
    enabled: Boolean,
    onClick: () -> Unit,
    colors: MochiColors,
) {
    Box(
        modifier = Modifier
            .size(44.dp)
            .clip(CircleShape)
            .background(if (enabled) colors.primary else colors.inputBorder)
            .clickable(enabled = enabled, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Icon(
            imageVector = Icons.AutoMirrored.Filled.Send,
            contentDescription = "发送",
            tint = if (enabled) colors.onPrimary else colors.textSecondary,
            modifier = Modifier.size(18.dp),
        )
    }
}

// ============================================================
// 录音脉冲动画圆点
// ============================================================
@Composable
private fun PulsingDot(color: Color) {
    val infiniteTransition = rememberInfiniteTransition(label = "pulse")
    val scale by infiniteTransition.animateFloat(
        initialValue = 1f,
        targetValue = 1.5f,
        animationSpec = infiniteRepeatable(
            animation = tween(600, easing = FastOutSlowInEasing),
            repeatMode = RepeatMode.Reverse,
        ),
        label = "scale",
    )
    Box(
        modifier = Modifier
            .size(8.dp)
            .scale(scale)
            .clip(CircleShape)
            .background(color),
    )
}
