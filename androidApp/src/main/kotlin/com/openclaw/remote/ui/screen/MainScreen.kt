package com.openclaw.remote.ui.screen

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.*
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.automirrored.filled.VolumeOff
import androidx.compose.material.icons.automirrored.filled.VolumeUp
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.DarkMode
import androidx.compose.material.icons.filled.Headphones
import androidx.compose.material.icons.filled.Keyboard
import androidx.compose.material.icons.filled.LightMode
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.StopCircle
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.changedToUpIgnoreConsumed
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInWindow
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.openclaw.remote.audio.AudioRecorder
import com.openclaw.remote.data.AgentAvailabilityStatus
import com.openclaw.remote.data.AgentProfile
import com.openclaw.remote.data.ChatMessage
import com.openclaw.remote.domain.ConnectionState
import com.openclaw.remote.domain.PairingState
import com.openclaw.remote.headset.A9UltraStandbyMode
import com.openclaw.remote.ui.theme.MochiColors
import com.openclaw.remote.ui.theme.MochiTheme
import com.openclaw.remote.viewmodel.ChatViewModel

@Composable
fun MainScreen(
    messages: List<ChatMessage>,
    isRecording: Boolean,
    connectionState: ConnectionState,
    pairingState: PairingState,
    pairedBackendLabel: String?,
    profiles: List<AgentProfile> = emptyList(),
    selectedProfileId: String = "",
    profileStatuses: Map<String, AgentAvailabilityStatus> = emptyMap(),
    unreadCounts: Map<String, Int> = emptyMap(),
    isDark: Boolean,
    isLoadingHistory: Boolean,
    hasMoreHistory: Boolean,
    headsetStatusLabel: String? = null,
    headsetStandbyMode: A9UltraStandbyMode = A9UltraStandbyMode.WAKE_WORD_REQUIRED,
    soundPlaybackEnabled: Boolean = true,
    isPlaybackSpeaking: Boolean = false,
    viewModel: ChatViewModel,
    audioRecorder: AudioRecorder,
    onToggleTheme: () -> Unit,
    onToggleSoundPlayback: () -> Unit = {},
    onInterruptPlayback: () -> Unit = {},
    onToggleHeadsetStandbyMode: () -> Unit = {},
    onNavigateToSettings: () -> Unit = {},
    onSelectProfile: (String) -> Unit = {},
) {
    val colors = MochiTheme.colors
    val clipboardManager = LocalClipboardManager.current
    val listState = rememberLazyListState()
    var isNearBottom by remember { mutableStateOf(true) }
    var isSelectingMessages by remember { mutableStateOf(false) }
    var selectedMessageKeys by remember { mutableStateOf<Set<String>>(emptySet()) }
    var quotedMessageSummary by remember { mutableStateOf<String?>(null) }
    val configuration = LocalConfiguration.current
    val density = LocalDensity.current
    val screenHeightPx = with(density) { configuration.screenHeightDp.dp.toPx() }
    val recordingPanelTopYPx = recordingPanelTopY(screenHeightPx)
    var touchLocationY by remember { mutableFloatStateOf(screenHeightPx) }
    var isMicGestureActive by remember { mutableStateOf(false) }
    val recordingState = voiceRecordingState(
        isRecording = isRecording,
        isGestureActive = isMicGestureActive,
        touchY = touchLocationY,
        panelTopY = recordingPanelTopYPx,
    )
    val lastMessageKey = messages.lastOrNull()?.let { message ->
        message.clientMessageId ?: "${message.senderId}|${message.timestamp}|${message.content}"
    }
    val selectedMessages = messages.filterIndexed { index, message ->
        selectedMessageKeys.contains(messageSelectionKey(index, message))
    }

    LaunchedEffect(Unit) {
        viewModel.connect()
    }

    LaunchedEffect(listState) {
        snapshotFlow {
            val layoutInfo = listState.layoutInfo
            val lastVisibleIndex = layoutInfo.visibleItemsInfo.lastOrNull()?.index ?: 0
            lastVisibleIndex to layoutInfo.totalItemsCount
        }.collect { (lastVisibleIndex, totalItemsCount) ->
            isNearBottom = totalItemsCount == 0 || lastVisibleIndex >= totalItemsCount - 3
        }
    }

    LaunchedEffect(lastMessageKey) {
        val lastMessage = messages.lastOrNull() ?: return@LaunchedEffect
        if (isNearBottom || lastMessage.senderId == "user") {
            val messageOffset = if (hasMoreHistory) 1 else 0
            listState.animateScrollToItem(messages.lastIndex + messageOffset)
        }
    }

    LaunchedEffect(isRecording, screenHeightPx) {
        if (!isRecording) {
            touchLocationY = screenHeightPx
            isMicGestureActive = false
        }
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(colors.background)
            .imePadding()
    ) {
        Column(modifier = Modifier.fillMaxSize()) {
            TopBar(
                connectionState = connectionState,
                pairingState = pairingState,
                pairedBackendLabel = pairedBackendLabel,
                profiles = profiles,
                selectedProfileId = selectedProfileId,
                profileStatuses = profileStatuses,
                unreadCounts = unreadCounts,
                headsetStatusLabel = headsetStatusLabel,
                headsetStandbyMode = headsetStandbyMode,
                soundPlaybackEnabled = soundPlaybackEnabled,
                isPlaybackSpeaking = isPlaybackSpeaking,
                isDark = isDark,
                onToggleTheme = onToggleTheme,
                onToggleSoundPlayback = onToggleSoundPlayback,
                onInterruptPlayback = onInterruptPlayback,
                onToggleHeadsetStandbyMode = onToggleHeadsetStandbyMode,
                onNavigateToSettings = onNavigateToSettings,
                onSelectProfile = onSelectProfile,
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

                    itemsIndexed(messages) { index, msg ->
                        val isUser = msg.senderId == "user"
                        val messageKey = messageSelectionKey(index, msg)
                        MessageBubble(
                            message = msg,
                            isUser = isUser,
                            isSelectionMode = isSelectingMessages,
                            isSelected = selectedMessageKeys.contains(messageKey),
                            onClick = {
                                if (isSelectingMessages) {
                                    selectedMessageKeys = toggleSelectedMessage(selectedMessageKeys, messageKey)
                                    if (selectedMessageKeys.isEmpty()) {
                                        isSelectingMessages = false
                                    }
                                }
                            },
                            onCopy = {
                                clipboardManager.setText(AnnotatedString(msg.content))
                            },
                            onQuote = {
                                quotedMessageSummary = quoteSummary(msg.content)
                            },
                            onSelect = {
                                isSelectingMessages = true
                                selectedMessageKeys = setOf(messageKey)
                            },
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
                                text = "请先扫码配对后端 Agent",
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

            if (isSelectingMessages) {
                MessageSelectionToolbar(
                    selectedCount = selectedMessageKeys.size,
                    colors = colors,
                    onCopy = {
                        clipboardManager.setText(
                            AnnotatedString(selectedMessages.joinToString(separator = "\n\n") { it.content })
                        )
                        selectedMessageKeys = emptySet()
                        isSelectingMessages = false
                    },
                    onCancel = {
                        selectedMessageKeys = emptySet()
                        isSelectingMessages = false
                    },
                )
            }

            InputArea(
                isRecording = isRecording,
                colors = colors,
                viewModel = viewModel,
                audioRecorder = audioRecorder,
                pairingState = pairingState,
                quotedMessageSummary = quotedMessageSummary,
                onCancelQuote = { quotedMessageSummary = null },
                onInterruptCurrentPlayback = onInterruptPlayback,
                recordingState = recordingState,
                onMicTouchLocationChanged = { globalY ->
                    touchLocationY = globalY
                    isMicGestureActive = true
                },
                onMicReleaseLocation = { finalGlobalY, pointerCancelled ->
                    val cancelled = shouldCancelVoiceRelease(
                        finalTouchY = finalGlobalY,
                        panelTopY = recordingPanelTopYPx,
                        pointerCancelled = pointerCancelled,
                    )
                    isMicGestureActive = false
                    touchLocationY = screenHeightPx
                    cancelled
                },
                onSendText = { text ->
                    val outgoingText = quotedMessageSummary?.let { "> $it\n\n$text" } ?: text
                    onInterruptPlayback()
                    viewModel.sendText(outgoingText)
                    quotedMessageSummary = null
                },
            )
        }

        // 录音遮罩层
        AnimatedVisibility(
            modifier = Modifier.align(Alignment.BottomCenter),
            visible = isRecording,
            enter = fadeIn() + slideInVertically { it },
            exit = fadeOut() + slideOutVertically { it },
        ) {
            RecordingOverlay(
                isRecording = isRecording,
                recordingState = recordingState,
                colors = colors,
            )
        }
    }
}

private fun messageSelectionKey(index: Int, message: ChatMessage): String {
    return message.clientMessageId ?: "$index|${message.senderId}|${message.timestamp}|${message.content}"
}

private fun toggleSelectedMessage(selected: Set<String>, key: String): Set<String> {
    return if (selected.contains(key)) selected - key else selected + key
}

private fun quoteSummary(content: String): String {
    val compact = content.split(Regex("\\s+")).filter { it.isNotEmpty() }.joinToString(" ")
    return if (compact.length <= 300) compact else compact.take(300) + "..."
}

@Composable
private fun MessageSelectionToolbar(
    selectedCount: Int,
    colors: MochiColors,
    onCopy: () -> Unit,
    onCancel: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(colors.surface)
            .border(width = 0.5.dp, color = colors.divider)
            .padding(horizontal = 16.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            text = "已选 $selectedCount 条",
            fontSize = 13.sp,
            color = colors.textSecondary,
        )

        Spacer(modifier = Modifier.weight(1f))

        TextButton(onClick = onCopy, enabled = selectedCount > 0) {
            Text("复制")
        }
        TextButton(onClick = onCancel) {
            Text("取消")
        }
    }
}

@Composable
private fun TopBar(
    connectionState: ConnectionState,
    pairingState: PairingState,
    pairedBackendLabel: String?,
    profiles: List<AgentProfile>,
    selectedProfileId: String,
    profileStatuses: Map<String, AgentAvailabilityStatus>,
    unreadCounts: Map<String, Int>,
    headsetStatusLabel: String?,
    headsetStandbyMode: A9UltraStandbyMode,
    soundPlaybackEnabled: Boolean,
    isPlaybackSpeaking: Boolean,
    isDark: Boolean,
    onToggleTheme: () -> Unit,
    onToggleSoundPlayback: () -> Unit,
    onInterruptPlayback: () -> Unit,
    onToggleHeadsetStandbyMode: () -> Unit,
    onNavigateToSettings: () -> Unit,
    onSelectProfile: (String) -> Unit,
    colors: MochiColors,
) {
    val selectedProfile = profiles.firstOrNull { it.id == selectedProfileId } ?: profiles.firstOrNull()
    val selectedStatus = selectedProfile
        ?.let { profileStatuses[it.id] }
        ?: fallbackAvailabilityStatus(connectionState, pairingState)
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(colors.surface)
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 12.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(5.dp),
            ) {
                if (profiles.size >= 2) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(4.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        profiles.take(3).forEach { profile ->
                            val itemStatus = profileStatuses[profile.id] ?: AgentAvailabilityStatus.UNPAIRED
                            AgentChip(
                                profile = profile,
                                status = itemStatus,
                                selected = profile.id == selectedProfileId,
                                hasUnread = (unreadCounts[profile.id] ?: 0) > 0,
                                colors = colors,
                                onClick = { onSelectProfile(profile.id) },
                                modifier = Modifier.weight(1f),
                            )
                        }
                    }
                } else {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        Text(
                            text = "${selectedProfile?.resolvedDisplayName ?: "Agent"}(${selectedStatus.label})",
                            fontSize = 13.sp,
                            fontWeight = FontWeight.Normal,
                            color = availabilityColor(selectedStatus, colors),
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                            modifier = Modifier.weight(1f, fill = false),
                        )
                    }
                }
            }

            Spacer(modifier = Modifier.width(8.dp))

            Row(
                horizontalArrangement = Arrangement.spacedBy(4.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                AnimatedVisibility(visible = isPlaybackSpeaking) {
                    MochiIconButton(
                        imageVector = Icons.Filled.StopCircle,
                        contentDescription = "打断当前播放",
                        tint = colors.recordingRed,
                        background = colors.recordingRed.copy(alpha = 0.12f),
                        onClick = onInterruptPlayback,
                    )
                }

                MochiIconButton(
                    imageVector = Icons.Filled.Mic,
                    contentDescription = if (headsetStandbyMode == A9UltraStandbyMode.CONTINUOUS) {
                        "切换到唤醒词待机"
                    } else {
                        "切换到连续对话"
                    },
                    tint = if (headsetStandbyMode == A9UltraStandbyMode.CONTINUOUS) colors.accent else colors.textSecondary,
                    background = if (headsetStandbyMode == A9UltraStandbyMode.CONTINUOUS) {
                        colors.accent.copy(alpha = 0.12f)
                    } else {
                        colors.inputBg
                    },
                    onClick = onToggleHeadsetStandbyMode,
                )

                MochiIconButton(
                    imageVector = if (soundPlaybackEnabled) Icons.AutoMirrored.Filled.VolumeUp else Icons.AutoMirrored.Filled.VolumeOff,
                    contentDescription = if (soundPlaybackEnabled) "切换到无声" else "切换到播放",
                    tint = if (soundPlaybackEnabled) colors.icon else colors.textSecondary,
                    background = if (soundPlaybackEnabled) colors.inputBg else colors.inputBorder.copy(alpha = 0.65f),
                    onClick = onToggleSoundPlayback,
                )

                MochiIconButton(
                    imageVector = if (isDark) Icons.Filled.LightMode else Icons.Filled.DarkMode,
                    contentDescription = if (isDark) "切换到浅色模式" else "切换到深色模式",
                    tint = if (isDark) colors.accent else colors.primary,
                    background = if (isDark) colors.secondary.copy(alpha = 0.72f) else Color.Transparent,
                    onClick = onToggleTheme,
                )

                MochiIconButton(
                    imageVector = Icons.Filled.Settings,
                    contentDescription = "设置",
                    tint = colors.icon,
                    background = colors.inputBg,
                    onClick = onNavigateToSettings,
                )
            }
        }

        if (!headsetStatusLabel.isNullOrBlank()) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(colors.inputBg)
                    .padding(horizontal = 12.dp, vertical = 7.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Icon(
                    imageVector = Icons.Filled.Headphones,
                    contentDescription = null,
                    tint = colors.primary,
                    modifier = Modifier.size(14.dp),
                )
                Text(
                    text = "耳机 $headsetStatusLabel · ${headsetStandbyMode.label}",
                    fontSize = 12.sp,
                    fontWeight = FontWeight.Medium,
                    color = colors.textSecondary,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f),
                )
                StatusDot(color = colors.primary)
            }
        }
    }
}

@Composable
private fun MochiIconButton(
    imageVector: ImageVector,
    contentDescription: String,
    tint: Color,
    background: Color,
    onClick: () -> Unit,
) {
    Box(
        modifier = Modifier
            .size(32.dp)
            .clip(CircleShape)
            .background(background)
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Icon(
            imageVector = imageVector,
            contentDescription = contentDescription,
            tint = tint,
            modifier = Modifier.size(19.dp),
        )
    }
}

@Composable
private fun StatusDot(color: Color) {
    Box(
        modifier = Modifier
            .size(6.dp)
            .clip(CircleShape)
            .background(color)
    )
}

private fun availabilityColor(
    status: AgentAvailabilityStatus,
    colors: MochiColors,
): Color {
    return when (status) {
        AgentAvailabilityStatus.AVAILABLE -> colors.onlineGreen
        AgentAvailabilityStatus.PAIRING, AgentAvailabilityStatus.CONNECTING, AgentAvailabilityStatus.OFFLINE -> colors.accent
        AgentAvailabilityStatus.UNCONFIGURED, AgentAvailabilityStatus.UNPAIRED -> colors.textSecondary
    }
}

private fun fallbackAvailabilityStatus(
    connectionState: ConnectionState,
    pairingState: PairingState,
): AgentAvailabilityStatus {
    return when {
        pairingState == PairingState.PAIRED &&
            (connectionState == ConnectionState.REGISTERED || connectionState == ConnectionState.PAIRED) ->
            AgentAvailabilityStatus.AVAILABLE
        pairingState == PairingState.PAIRED || pairingState == PairingState.PENDING ->
            AgentAvailabilityStatus.CONNECTING
        connectionState == ConnectionState.CONNECTING || connectionState == ConnectionState.CONNECTED ->
            AgentAvailabilityStatus.CONNECTING
        connectionState == ConnectionState.REGISTERED ->
            AgentAvailabilityStatus.UNPAIRED
        else -> AgentAvailabilityStatus.UNPAIRED
    }
}

@Composable
private fun AgentChip(
    profile: AgentProfile,
    status: AgentAvailabilityStatus,
    selected: Boolean,
    hasUnread: Boolean,
    colors: MochiColors,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val statusColor = availabilityColor(status, colors)
    Row(
        modifier = modifier
            .height(28.dp)
            .clip(RoundedCornerShape(8.dp))
            .background(if (selected) colors.primary else colors.inputBg)
            .border(
                width = 0.5.dp,
                color = if (selected) Color.Transparent else colors.inputBorder,
                shape = RoundedCornerShape(8.dp),
            )
            .clickable(onClick = onClick)
            .padding(horizontal = 6.dp, vertical = 5.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Text(
            text = "${profile.resolvedDisplayName}(${status.label})",
            fontSize = 10.sp,
            fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Normal,
            color = if (selected) colors.onPrimary else statusColor,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.weight(1f),
        )
        if (!selected && hasUnread) {
            Box(
                modifier = Modifier
                    .size(6.dp)
                    .clip(CircleShape)
                    .background(colors.recordingRed)
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
    quotedMessageSummary: String? = null,
    onCancelQuote: () -> Unit = {},
    onInterruptCurrentPlayback: () -> Unit = {},
    onSendText: (String) -> Unit = { viewModel.sendText(it) },
    recordingState: VoiceRecordingState = VoiceRecordingState.IDLE,
    onMicTouchLocationChanged: (Float) -> Unit = {},
    onMicReleaseLocation: (Float, Boolean) -> Boolean = { _, pointerCancelled -> pointerCancelled },
) {
    var inputMode by rememberSaveable { mutableStateOf(InputMode.VOICE) }

    LaunchedEffect(quotedMessageSummary) {
        if (quotedMessageSummary != null) {
            inputMode = InputMode.TEXT
        }
    }

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(colors.surface)
    ) {
        HorizontalDivider(color = colors.divider, thickness = 0.5.dp)

        if (quotedMessageSummary != null) {
            QuotePreviewBar(
                summary = quotedMessageSummary,
                colors = colors,
                onCancel = onCancelQuote,
            )
        }

        if (inputMode == InputMode.TEXT) {
            TextInputRow(
                inputMode = inputMode,
                onSend = onSendText,
                onSwitchToVoice = { inputMode = InputMode.VOICE },
                colors = colors,
            )
        } else {
            VoiceInputRow(
                isRecording = isRecording,
                recordingState = recordingState,
                onMicPress = {
                    onInterruptCurrentPlayback()
                    if (!audioRecorder.isRecording.value) {
                        audioRecorder.startRecording()
                    }
                },
                onMicRelease = { finalGlobalY, pointerCancelled ->
                    val cancelled = onMicReleaseLocation(finalGlobalY, pointerCancelled)
                    if (audioRecorder.isRecording.value) {
                        audioRecorder.stopRecording { audioData ->
                            if (!cancelled) {
                                viewModel.sendAudio(audioData)
                            }
                        }
                    }
                },
                onMicTouchLocationChanged = onMicTouchLocationChanged,
                onSwitchToText = { inputMode = InputMode.TEXT },
                colors = colors,
            )
        }

        Spacer(modifier = Modifier.height(8.dp))
    }
}

@Composable
private fun QuotePreviewBar(
    summary: String,
    colors: MochiColors,
    onCancel: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(start = 16.dp, top = 10.dp, end = 16.dp, bottom = 2.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            modifier = Modifier
                .width(3.dp)
                .height(34.dp)
                .clip(RoundedCornerShape(2.dp))
                .background(colors.primary)
        )

        Spacer(modifier = Modifier.width(10.dp))

        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = "引用",
                fontSize = 12.sp,
                color = colors.textSecondary,
            )
            Text(
                text = summary,
                fontSize = 13.sp,
                color = colors.textSecondary,
                maxLines = 2,
            )
        }

        InputIconButton(
            imageVector = Icons.Filled.Close,
            contentDescription = "取消引用",
            colors = colors,
            size = 28,
            iconSize = 16,
            onClick = onCancel,
        )
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
        InputIconButton(
            imageVector = Icons.Filled.Mic,
            contentDescription = "切换到语音",
            colors = colors,
            onClick = onSwitchToVoice,
        )

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
private fun InputIconButton(
    imageVector: ImageVector,
    contentDescription: String,
    colors: MochiColors,
    size: Int = 44,
    iconSize: Int = 22,
    onClick: () -> Unit,
) {
    Box(
        modifier = Modifier
            .size(size.dp)
            .clip(CircleShape)
            .background(colors.inputBg)
            .border(0.5.dp, colors.inputBorder, CircleShape)
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Icon(
            imageVector = imageVector,
            contentDescription = contentDescription,
            tint = colors.icon,
            modifier = Modifier.size(iconSize.dp),
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
    recordingState: VoiceRecordingState,
    onMicPress: () -> Unit,
    onMicRelease: (finalGlobalY: Float, pointerCancelled: Boolean) -> Unit,
    onMicTouchLocationChanged: (Float) -> Unit,
    onSwitchToText: () -> Unit,
    colors: MochiColors,
) {
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
            InputIconButton(
                imageVector = Icons.Filled.Keyboard,
                contentDescription = "切换到键盘",
                colors = colors,
                onClick = onSwitchToText,
            )

            Spacer(modifier = Modifier.weight(1f))

            VoiceMicButton(
                isRecording = isRecording,
                recordingState = recordingState,
                onPress = onMicPress,
                onRelease = onMicRelease,
                onTouchLocationChanged = onMicTouchLocationChanged,
                colors = colors,
            )

            Spacer(modifier = Modifier.weight(1f))

            Spacer(modifier = Modifier.size(44.dp))
        }
    }
}

@Composable
private fun RecordingOverlay(
    isRecording: Boolean,
    recordingState: VoiceRecordingState,
    colors: MochiColors,
) {
    if (!isRecording) return

    val isCancelled = recordingState.isCancelled
    val infiniteTransition = rememberInfiniteTransition(label = "glowPulse")
    val glowAlpha by infiniteTransition.animateFloat(
        initialValue = 0.3f,
        targetValue = 0.7f,
        animationSpec = infiniteRepeatable(
            animation = tween(1150, easing = EaseInOut),
            repeatMode = RepeatMode.Reverse,
        ),
        label = "glowAlpha",
    )

    Box(
        modifier = Modifier
            .fillMaxWidth()
            .height(180.dp)
            .background(
                brush = Brush.verticalGradient(
                    colors = if (isCancelled) {
                        listOf(
                            Color(0xFF2B0606).copy(alpha = 0.95f),
                            Color(0xFF1A0303).copy(alpha = 0.98f),
                        )
                    } else {
                        listOf(
                            Color(0xFF238CFF).copy(alpha = 0.95f),
                            Color(0xFF1A5FCC).copy(alpha = 0.98f),
                        )
                    },
                ),
            ),
        contentAlignment = Alignment.TopCenter,
    ) {
        // 动态光晕效果
        Box(
            modifier = Modifier
                .offset(y = 42.dp)
                .width(320.dp)
                .height(120.dp)
                .background(
                    brush = Brush.radialGradient(
                        colors = listOf(
                            if (isCancelled) Color(0xFFE53935).copy(alpha = glowAlpha * 0.5f)
                            else Color(0xFF4DA6FF).copy(alpha = glowAlpha * 0.5f),
                            Color.Transparent,
                        ),
                    ),
                ),
        )

        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(top = 24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            // 波形动画
            VoiceWaveform(
                isActive = isRecording && !isCancelled,
                isCancelled = isCancelled,
                modifier = Modifier
                    .fillMaxWidth()
                    .height(60.dp),
            )

            Spacer(modifier = Modifier.height(16.dp))

            // 提示文字
            Text(
                text = when {
                    isCancelled -> "松开取消"
                    else -> "松手发送，上滑取消 ↑"
                },
                fontSize = 14.sp,
                color = if (isCancelled) Color.White else Color.White.copy(alpha = 0.9f),
            )
        }
    }
}

@Composable
private fun VoiceWaveform(
    isActive: Boolean,
    isCancelled: Boolean,
    modifier: Modifier = Modifier,
) {
    val infiniteTransition = rememberInfiniteTransition(label = "waveform")

    val phase by infiniteTransition.animateFloat(
        initialValue = 0f,
        targetValue = 2f * Math.PI.toFloat(),
        animationSpec = infiniteRepeatable(
            animation = tween(850, easing = LinearEasing),
            repeatMode = RepeatMode.Restart,
        ),
        label = "phase",
    )

    val barCount = 54
    val barSpacing = 3.dp

    Row(
        modifier = modifier,
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        repeat(barCount) { index ->
            val distanceFromCenter = kotlin.math.abs(index - barCount / 2f) / (barCount / 2f)
            val centerBias = (1f - distanceFromCenter).coerceIn(0.12f, 1f)

            val barHeight = if (isActive) {
                val primaryWave = (kotlin.math.sin(phase + index * 0.3f) + 1f) / 2f
                val secondaryWave = (kotlin.math.sin(phase * 1.5f + index * 0.5f) + 1f) / 2f
                val liveMotion = (primaryWave * 0.6f + secondaryWave * 0.4f) * centerBias
                val baseHeight = if (isCancelled) 8f else 5f
                (baseHeight + liveMotion * 40f).coerceIn(5f, 50f)
            } else {
                // 静止状态
                val idleWave = (kotlin.math.sin(phase * 0.5f + index * 0.2f) + 1f) / 2f
                (2f + idleWave * 5f).coerceIn(2f, 7f)
            }

            Box(
                modifier = Modifier
                    .width(2.dp)
                    .height(barHeight.dp),
            ) {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .fillMaxHeight()
                        .background(
                            color = if (isCancelled) Color(0xFFE53935) else Color.White.copy(alpha = 0.7f),
                            shape = RoundedCornerShape(1.dp),
                        ),
                )
            }

            if (index < barCount - 1) {
                Spacer(modifier = Modifier.width(barSpacing))
            }
        }
    }
}

@Composable
private fun VoiceMicButton(
    isRecording: Boolean,
    recordingState: VoiceRecordingState,
    onPress: () -> Unit,
    onRelease: (finalGlobalY: Float, pointerCancelled: Boolean) -> Unit,
    onTouchLocationChanged: (Float) -> Unit,
    colors: MochiColors,
) {
    val buttonTopYState = remember { mutableFloatStateOf(0f) }
    val currentOnPress by rememberUpdatedState(onPress)
    val currentOnRelease by rememberUpdatedState(onRelease)
    val currentOnTouchLocationChanged by rememberUpdatedState(onTouchLocationChanged)
    val backgroundColor = when {
        recordingState.isCancelled -> colors.recordingRed.copy(alpha = 0.8f)
        isRecording -> colors.recordingRed
        else -> colors.secondary
    }

    val iconRotation by animateFloatAsState(
        targetValue = if (recordingState.isCancelled) 45f else 0f,
        animationSpec = spring(dampingRatio = Spring.DampingRatioMediumBouncy),
        label = "iconRotate",
    )

    Box(
        modifier = Modifier
            .size(56.dp)
            .clip(CircleShape)
            .background(backgroundColor)
            .onGloballyPositioned { coordinates ->
                buttonTopYState.floatValue = coordinates.positionInWindow().y
            }
            .pointerInput(Unit) {
                fun globalY(localY: Float): Float = buttonTopYState.floatValue + localY

                awaitEachGesture {
                    val down = awaitFirstDown(requireUnconsumed = false)
                    var lastGlobalY = globalY(down.position.y)
                    currentOnTouchLocationChanged(lastGlobalY)
                    currentOnPress()

                    var pointerCancelled = false
                    while (true) {
                        val event = awaitPointerEvent()
                        val change = event.changes.firstOrNull { it.id == down.id }
                        if (change == null) {
                            pointerCancelled = true
                            break
                        }

                        lastGlobalY = globalY(change.position.y)
                        currentOnTouchLocationChanged(lastGlobalY)

                        if (change.changedToUpIgnoreConsumed()) {
                            break
                        }
                        change.consume()
                    }

                    currentOnRelease(lastGlobalY, pointerCancelled)
                }
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
