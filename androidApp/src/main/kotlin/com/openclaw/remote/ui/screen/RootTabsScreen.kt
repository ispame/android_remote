package com.openclaw.remote.ui.screen

import android.content.Context
import android.content.SharedPreferences
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.AccountCircle
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.Bluetooth
import androidx.compose.material.icons.filled.Chat
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.GraphicEq
import androidx.compose.material.icons.filled.Headphones
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.MoreHoriz
import androidx.compose.material.icons.filled.PushPin
import androidx.compose.material.icons.filled.QrCodeScanner
import androidx.compose.material.icons.filled.RadioButtonUnchecked
import androidx.compose.material.icons.filled.Save
import androidx.compose.material.icons.filled.Send
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material.icons.filled.TaskAlt
import androidx.compose.material.icons.outlined.PushPin
import androidx.compose.material3.AssistChip
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Divider
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ElevatedButton
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Slider
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.openclaw.remote.auth.AiChatMessage
import com.openclaw.remote.auth.AnthropicChatClient
import com.openclaw.remote.auth.GatewayAuthClient
import com.openclaw.remote.auth.OpenAICompatibleChatClient
import com.openclaw.remote.auth.resolvedCredentialId
import com.openclaw.remote.audio.AudioRecorder
import com.openclaw.remote.data.AgentAvailabilityStatus
import com.openclaw.remote.data.AgentPlatform
import com.openclaw.remote.data.AgentProfile
import com.openclaw.remote.data.AgentProfilesState
import com.openclaw.remote.data.AiAgentOverride
import com.openclaw.remote.data.AiProviderCatalog
import com.openclaw.remote.data.AiProviderDescriptor
import com.openclaw.remote.data.AiProviderChatSelection
import com.openclaw.remote.data.AiServiceChoice
import com.openclaw.remote.data.AiServiceConfig
import com.openclaw.remote.data.AiServiceDefaults
import com.openclaw.remote.data.AiServiceSettings
import com.openclaw.remote.data.ChatMessage
import com.openclaw.remote.data.CodexSessionGroupingMode
import com.openclaw.remote.data.CodexSessionSummary
import com.openclaw.remote.data.GatewayConfig
import com.openclaw.remote.data.Recording
import com.openclaw.remote.data.RecordingAsrJob
import com.openclaw.remote.data.RecordingAsrJobStatus
import com.openclaw.remote.data.RecordingReminder
import com.openclaw.remote.data.RecordingSettings
import com.openclaw.remote.data.RecordingStore
import com.openclaw.remote.data.RecordingType
import com.openclaw.remote.data.SettingsManager
import com.openclaw.remote.data.decodeRecordings
import com.openclaw.remote.data.defaultSelectionType
import com.openclaw.remote.data.asrConfigForRecording
import com.openclaw.remote.data.isSelectableServiceConfig
import com.openclaw.remote.data.llmConfigForProviderChat
import com.openclaw.remote.data.encodeRecordings
import com.openclaw.remote.data.promptFor
import com.openclaw.remote.data.preferredBySavedCredential
import com.openclaw.remote.data.recordingSelectionTypeOptions
import com.openclaw.remote.data.settingsTypeOptions
import com.openclaw.remote.data.sortedForAgentList
import com.openclaw.remote.data.toAiServiceChoice
import com.openclaw.remote.data.toAiServiceConfig
import com.openclaw.remote.data.ttsConfigForPlayback
import com.openclaw.remote.data.groupCodexSessions
import com.openclaw.remote.headset.A9UltraStandbyMode
import com.openclaw.remote.ui.theme.MochiTheme
import com.openclaw.remote.viewmodel.ChatViewModel
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

enum class AndroidRootTab(val label: String) {
    AGENTS("Agent"),
    RECORDINGS("录音"),
    HEADSET("耳机"),
    SETTINGS("设置"),
}

data class RootNavigationState(
    val selectedTab: AndroidRootTab = AndroidRootTab.AGENTS,
    val openChatProfileId: String? = null,
    val openCodexProfileId: String? = null,
    val openCodexSessionId: String? = null,
    val isProviderChatOpen: Boolean = false,
    val openAgentConfigProfileId: String? = null,
)

enum class ProviderChatRoute {
    ROUTER,
    OPENAI_COMPATIBLE,
    ANTHROPIC,
    AGENT_DISABLED,
    UNSUPPORTED,
}

fun providerChatRouteFor(choice: AiServiceChoice): ProviderChatRoute =
    when {
        choice.mode == "router" -> ProviderChatRoute.ROUTER
        choice.mode == "agent" || choice.mode == "backend" -> ProviderChatRoute.AGENT_DISABLED
        choice.mode == "byok" && choice.providerId == "claude" -> ProviderChatRoute.ANTHROPIC
        choice.mode == "byok" -> ProviderChatRoute.OPENAI_COMPATIBLE
        else -> ProviderChatRoute.UNSUPPORTED
    }

@Composable
fun RootTabsScreen(
    navigationState: RootNavigationState,
    onNavigationStateChange: (RootNavigationState) -> Unit,
    settingsManager: SettingsManager,
    config: GatewayConfig,
    authClient: GatewayAuthClient,
    chatViewModel: ChatViewModel,
    profiles: List<AgentProfile>,
    selectedProfileId: String,
    profileStatuses: Map<String, AgentAvailabilityStatus>,
    isDark: Boolean,
    isRecording: Boolean,
    audioRecorder: AudioRecorder,
    headsetStatusLabel: String?,
    headsetStandbyMode: A9UltraStandbyMode,
    showHeadsetStandbyControl: Boolean,
    headsetLedLightEnabled: Boolean,
    showHeadsetLedLightControl: Boolean,
    soundPlaybackEnabled: Boolean,
    isPlaybackSpeaking: Boolean,
    onToggleTheme: () -> Unit,
    onToggleSoundPlayback: () -> Unit,
    onInterruptPlayback: () -> Unit,
    onToggleHeadsetStandbyMode: () -> Unit,
    onToggleHeadsetLedLight: (Boolean) -> Unit,
    onOpenQrScanner: () -> Unit,
    onOpenWallet: () -> Unit,
    onSelectProfile: (String) -> Unit,
    onOpenProfileChat: (String) -> Unit,
    onDeleteProfile: (String) -> Unit,
    onToggleProfilePin: (String, Boolean) -> Unit,
    chatContent: @Composable () -> Unit,
    settingsContent: @Composable () -> Unit,
) {
    val colors = MochiTheme.colors
    val context = LocalContext.current
    val aiSettings by settingsManager.aiSettingsFlow.collectAsState(initial = AiServiceSettings())
    val codexAgentPreviews by chatViewModel.codexAgentPreviews.collectAsState()
    val recordingPrefs = remember(context) {
        context.getSharedPreferences("openclaw_recordings", Context.MODE_PRIVATE)
    }
    val recordingStore = remember(recordingPrefs) {
        RecordingStore(decodeRecordings(recordingPrefs.getString("recordings_v1", null)))
    }
    var recordings by remember { mutableStateOf(recordingStore.recordings) }
    var selectedRecordingId by remember { mutableStateOf<String?>(null) }
    var recordingSettings by remember(recordingPrefs) {
        mutableStateOf(recordingPrefs.readRecordingSettings())
    }
    val effectiveRecordingSettings = recordingSettings.withAiAsrConfig(aiSettings.asrConfigForRecording())

    fun refreshRecordings() {
        recordings = recordingStore.recordings
        recordingPrefs.edit()
            .putString("recordings_v1", encodeRecordings(recordings))
            .apply()
    }

    fun updateRecordingSettings(settings: RecordingSettings) {
        recordingSettings = settings
        recordingPrefs.writeRecordingSettings(settings)
    }

    when {
        navigationState.openAgentConfigProfileId != null -> {
            val profile = profiles.firstOrNull { it.id == navigationState.openAgentConfigProfileId }
            if (profile != null) {
                AgentConfigScreen(
                    profile = profile,
                    settingsManager = settingsManager,
                    onBack = {
                        onNavigationStateChange(
                            navigationState.copy(openAgentConfigProfileId = null)
                        )
                    },
                    onOpenAiService = {
                        onNavigationStateChange(
                            RootNavigationState(selectedTab = AndroidRootTab.SETTINGS)
                        )
                    },
                )
                return
            }
        }
        navigationState.isProviderChatOpen -> {
            ProviderChatScreen(
                settingsManager = settingsManager,
                config = config,
                authClient = authClient,
                onBack = { onNavigationStateChange(navigationState.copy(isProviderChatOpen = false)) },
            )
            return
        }
        navigationState.openCodexProfileId != null && navigationState.openCodexSessionId != null -> {
            val profile = profiles.firstOrNull { it.id == navigationState.openCodexProfileId }
            if (profile != null) {
                CodexSessionChatScreen(
                    profile = profile,
                    sessionId = navigationState.openCodexSessionId,
                    viewModel = chatViewModel,
                    onBack = {
                        onNavigationStateChange(navigationState.copy(openCodexSessionId = null))
                    },
                )
                return
            }
        }
        navigationState.openCodexProfileId != null -> {
            val profile = profiles.firstOrNull { it.id == navigationState.openCodexProfileId }
            if (profile != null) {
                CodexSessionListScreen(
                    profile = profile,
                    status = profileStatuses[profile.id] ?: AgentAvailabilityStatus.UNCONFIGURED,
                    viewModel = chatViewModel,
                    onBack = {
                        onNavigationStateChange(
                            navigationState.copy(openCodexProfileId = null, openCodexSessionId = null)
                        )
                    },
                    onOpenSettings = {
                        onNavigationStateChange(
                            navigationState.copy(openAgentConfigProfileId = profile.id)
                        )
                    },
                    onOpenSession = { sessionId ->
                        onNavigationStateChange(navigationState.copy(openCodexSessionId = sessionId))
                    },
                )
                return
            }
        }
        navigationState.openChatProfileId != null -> {
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .background(colors.background)
            ) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(48.dp)
                        .padding(horizontal = 8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    IconButton(
                        onClick = {
                            onNavigationStateChange(navigationState.copy(openChatProfileId = null))
                        }
                    ) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                    Text(
                        text = profiles.firstOrNull { it.id == navigationState.openChatProfileId }
                            ?.resolvedDisplayName ?: "Agent",
                        fontWeight = FontWeight.SemiBold,
                        modifier = Modifier.weight(1f),
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                    TextButton(
                        onClick = {
                            onNavigationStateChange(
                                navigationState.copy(
                                    openAgentConfigProfileId = navigationState.openChatProfileId
                                )
                            )
                        }
                    ) {
                        Text("配置")
                    }
                }
                Box(modifier = Modifier.weight(1f)) {
                    chatContent()
                }
            }
            return
        }
    }

    Scaffold(
        bottomBar = {
            NavigationBar(containerColor = colors.surface) {
                AndroidRootTab.entries.forEach { tab ->
                    NavigationBarItem(
                        selected = navigationState.selectedTab == tab,
                        onClick = {
                            onNavigationStateChange(
                                RootNavigationState(selectedTab = tab)
                            )
                        },
                        icon = { Icon(rootTabIcon(tab), contentDescription = tab.label) },
                        label = { Text(tab.label) },
                    )
                }
            }
        },
        containerColor = colors.background,
    ) { padding ->
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
        ) {
            when (navigationState.selectedTab) {
                AndroidRootTab.AGENTS -> AgentsTabScreen(
                    profiles = profiles,
                    selectedProfileId = selectedProfileId,
                    profileStatuses = profileStatuses,
                    codexAgentPreviews = codexAgentPreviews,
                    onOpenProviderChat = {
                        onNavigationStateChange(navigationState.copy(isProviderChatOpen = true))
                    },
                    onOpenProfileChat = { profileId ->
                        onSelectProfile(profileId)
                        onOpenProfileChat(profileId)
                        val profile = profiles.firstOrNull { it.id == profileId }
                        if (profile?.platform == AgentPlatform.CODEX) {
                            onNavigationStateChange(
                                navigationState.copy(
                                    openCodexProfileId = profileId,
                                    openCodexSessionId = null,
                                )
                            )
                        } else {
                            onNavigationStateChange(navigationState.copy(openChatProfileId = profileId))
                        }
                    },
                    onOpenQrScanner = onOpenQrScanner,
                    onDeleteProfile = onDeleteProfile,
                    onToggleProfilePin = onToggleProfilePin,
                )
                AndroidRootTab.RECORDINGS -> RecordingsTabScreen(
                    recordings = recordings,
                    selectedRecordingId = selectedRecordingId,
                    onSelectRecording = { selectedRecordingId = it },
                    recordingStore = recordingStore,
                    recordingSettings = effectiveRecordingSettings,
                    config = config,
                    authClient = authClient,
                    isRecording = isRecording,
                    audioRecorder = audioRecorder,
                    onStoreChanged = ::refreshRecordings,
                )
                AndroidRootTab.HEADSET -> HeadsetTabScreen(
                    settingsManager = settingsManager,
                    headsetStatusLabel = headsetStatusLabel,
                    headsetStandbyMode = headsetStandbyMode,
                    showHeadsetStandbyControl = showHeadsetStandbyControl,
                    headsetLedLightEnabled = headsetLedLightEnabled,
                    showHeadsetLedLightControl = showHeadsetLedLightControl,
                    soundPlaybackEnabled = soundPlaybackEnabled,
                    isPlaybackSpeaking = isPlaybackSpeaking,
                    onToggleSoundPlayback = onToggleSoundPlayback,
                    onInterruptPlayback = onInterruptPlayback,
                    onToggleHeadsetStandbyMode = onToggleHeadsetStandbyMode,
                    onToggleHeadsetLedLight = onToggleHeadsetLedLight,
                )
                AndroidRootTab.SETTINGS -> SettingsTabShell(
                    settingsManager = settingsManager,
                    recordingSettings = recordingSettings,
                    isDark = isDark,
                    onToggleTheme = onToggleTheme,
                    onOpenWallet = onOpenWallet,
                    onRecordingSettingsChange = ::updateRecordingSettings,
                    aiServiceContent = {
                        AiServiceSettingsScreen(settingsManager = settingsManager)
                    },
                    connectionSettingsContent = settingsContent,
                )
            }
        }
    }
}

@Composable
private fun AgentsTabScreen(
    profiles: List<AgentProfile>,
    selectedProfileId: String,
    profileStatuses: Map<String, AgentAvailabilityStatus>,
    codexAgentPreviews: Map<String, String>,
    onOpenProviderChat: () -> Unit,
    onOpenProfileChat: (String) -> Unit,
    onOpenQrScanner: () -> Unit,
    onDeleteProfile: (String) -> Unit,
    onToggleProfilePin: (String, Boolean) -> Unit,
) {
    val colors = MochiTheme.colors
    val spec = iosParitySpecFor(AndroidRootTab.AGENTS)
    val sortedProfiles = remember(profiles) { profiles.sortedForAgentList() }
    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .background(colors.background),
        contentPadding = PaddingValues(horizontal = 16.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        item {
            TabHeader(title = spec.title, actionLabel = spec.primaryAction, onAction = onOpenQrScanner)
        }
        item {
            IosSection(title = spec.sections[0].title, footer = spec.sections[0].footer) {
                IosNavigationRow(
                    title = "AI Provider",
                    subtitle = "和当前 LLM Provider 对话",
                    value = "文本",
                    leading = {
                        Icon(
                            Icons.Filled.AutoAwesome,
                            contentDescription = null,
                            modifier = Modifier.size(24.dp),
                            tint = MaterialTheme.colorScheme.primary,
                        )
                    },
                    onClick = onOpenProviderChat,
                )
            }
        }
        item {
            IosSection(title = spec.sections[1].title) {
                if (sortedProfiles.isEmpty()) {
                    IosPlainRow {
                        Text(
                            "还没有连接的 Agent。点击右上角扫码添加。",
                            color = MochiTheme.colors.textSecondary,
                            fontSize = 14.sp,
                        )
                    }
                } else {
                    sortedProfiles.forEachIndexed { index, profile ->
                        AgentRow(
                            profile = profile,
                            selected = profile.id == selectedProfileId,
                            status = profileStatuses[profile.id] ?: AgentAvailabilityStatus.UNCONFIGURED,
                            codexPreview = codexAgentPreviews[profile.id],
                            onOpen = { onOpenProfileChat(profile.id) },
                            onDelete = { onDeleteProfile(profile.id) },
                            onTogglePin = { onToggleProfilePin(profile.id, !profile.isPinned) },
                        )
                        if (index != sortedProfiles.lastIndex) {
                            IosRowDivider()
                        }
                    }
                }
            }
        }
        item {
            IosSection {
                IosActionRow(
                    title = "扫码添加 Agent",
                    onClick = onOpenQrScanner,
                    leading = {
                        Icon(Icons.Filled.QrCodeScanner, contentDescription = null)
                    },
                )
            }
        }
    }
}

@Composable
private fun ProviderAgentRow(onClick: () -> Unit) {
    SurfaceRow(onClick = onClick) {
        Icon(
            Icons.Filled.AutoAwesome,
            contentDescription = null,
            modifier = Modifier.size(28.dp),
            tint = MaterialTheme.colorScheme.primary,
        )
        Spacer(Modifier.width(12.dp))
        Column(modifier = Modifier.weight(1f)) {
            Text("AI Provider", fontWeight = FontWeight.SemiBold)
            Text("Router / BYOK 文本对话", fontSize = 13.sp, color = MochiTheme.colors.textSecondary)
        }
        Icon(Icons.Filled.Chat, contentDescription = null)
    }
}

@Composable
private fun AgentRow(
    profile: AgentProfile,
    selected: Boolean,
    status: AgentAvailabilityStatus,
    codexPreview: String?,
    onOpen: () -> Unit,
    onDelete: () -> Unit,
    onTogglePin: () -> Unit,
) {
    IosPlainRow(onClick = onOpen) {
        Box(
            modifier = Modifier
                .size(36.dp)
                .clip(CircleShape)
                .background(if (selected) MaterialTheme.colorScheme.primary else MochiTheme.colors.secondary),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                Icons.Filled.AccountCircle,
                contentDescription = null,
                tint = if (selected) MaterialTheme.colorScheme.onPrimary else MochiTheme.colors.textSecondary,
            )
        }
        Spacer(Modifier.width(12.dp))
        Column(modifier = Modifier.weight(1f)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    profile.resolvedDisplayName,
                    fontWeight = FontWeight.SemiBold,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f, fill = false),
                )
                if (profile.isPinned) {
                    Spacer(Modifier.width(6.dp))
                    Icon(Icons.Filled.PushPin, contentDescription = null, modifier = Modifier.size(14.dp))
                }
            }
            Text(
                listOf(profile.platform.label, status.label).joinToString(" · "),
                fontSize = 13.sp,
                color = MochiTheme.colors.textSecondary,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            Text(
                codexPreview?.takeIf { profile.platform == AgentPlatform.CODEX && it.isNotBlank() }
                    ?: profile.backendLabel?.takeIf { it.isNotBlank() }
                    ?: profile.backendId.ifBlank { "暂无最近消息" },
                fontSize = 12.sp,
                color = MochiTheme.colors.textSecondary,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
        if (profile.isPinned) {
            Box(
                modifier = Modifier
                    .size(8.dp)
                    .clip(CircleShape)
                    .background(MaterialTheme.colorScheme.primary)
            )
            Spacer(Modifier.width(6.dp))
        }
        TextButton(onClick = onTogglePin) {
            Text(if (profile.isPinned) "取消置顶" else "置顶")
        }
        TextButton(onClick = onDelete) {
            Text("删除", color = MaterialTheme.colorScheme.error)
        }
    }
}

@Composable
private fun CodexSessionListScreen(
    profile: AgentProfile,
    status: AgentAvailabilityStatus,
    viewModel: ChatViewModel,
    onBack: () -> Unit,
    onOpenSettings: () -> Unit,
    onOpenSession: (String) -> Unit,
) {
    val colors = MochiTheme.colors
    val sessionsByProfile by viewModel.codexSessions.collectAsState()
    val archivedByProfile by viewModel.codexArchivedSessions.collectAsState()
    val createdSessionIds by viewModel.codexCreatedSessionIds.collectAsState()
    var mode by remember { mutableStateOf(CodexSessionGroupingMode.TIME) }
    var showingArchived by remember { mutableStateOf(false) }
    var query by remember { mutableStateOf("") }
    var menuExpanded by remember { mutableStateOf(false) }
    var handledCreatedSessionId by remember(profile.id) { mutableStateOf<String?>(null) }
    val loadedSessions = if (showingArchived) {
        archivedByProfile[profile.id].orEmpty()
    } else {
        sessionsByProfile[profile.id].orEmpty()
    }
    val filteredSessions = loadedSessions.filter { session ->
        val q = query.trim().lowercase()
        q.isEmpty() || listOf(
            session.displayTitle,
            session.displayPreview,
            session.displayProjectName,
            session.projectPath,
            session.model.orEmpty(),
        ).joinToString(" ").lowercase().contains(q)
    }
    val groups = groupCodexSessions(filteredSessions, mode)

    LaunchedEffect(profile.id, showingArchived) {
        viewModel.requestCodexSessions(profile.id, archived = showingArchived)
    }
    LaunchedEffect(createdSessionIds[profile.id]) {
        val sessionId = createdSessionIds[profile.id] ?: return@LaunchedEffect
        if (sessionId != handledCreatedSessionId) {
            handledCreatedSessionId = sessionId
            onOpenSession(sessionId)
        }
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(colors.background)
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .height(56.dp)
                .padding(horizontal = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            IconButton(onClick = onBack) {
                Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
            }
            Column(modifier = Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally) {
                Text("Codex", fontWeight = FontWeight.SemiBold, maxLines = 1)
                Text(
                    "${profile.backendLabel?.takeIf { it.isNotBlank() } ?: profile.backendId} · ${status.label}",
                    fontSize = 12.sp,
                    color = colors.textSecondary,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
            Box {
                IconButton(onClick = { menuExpanded = true }) {
                    Icon(Icons.Filled.MoreHoriz, contentDescription = "Codex menu")
                }
                DropdownMenu(expanded = menuExpanded, onDismissRequest = { menuExpanded = false }) {
                    DropdownMenuItem(
                        text = { Text("按项目") },
                        onClick = {
                            mode = CodexSessionGroupingMode.PROJECT
                            menuExpanded = false
                        },
                    )
                    DropdownMenuItem(
                        text = { Text("按时间顺序排列的列表") },
                        onClick = {
                            mode = CodexSessionGroupingMode.TIME
                            menuExpanded = false
                        },
                    )
                    DropdownMenuItem(
                        text = { Text(if (showingArchived) "当前会话" else "已归档会话") },
                        onClick = {
                            showingArchived = !showingArchived
                            menuExpanded = false
                        },
                    )
                    DropdownMenuItem(
                        text = { Text("设置") },
                        onClick = {
                            menuExpanded = false
                            onOpenSettings()
                        },
                    )
                }
            }
        }

        LazyColumn(
            modifier = Modifier
                .weight(1f)
                .fillMaxWidth(),
            contentPadding = PaddingValues(horizontal = 16.dp, vertical = 10.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            if (groups.isEmpty()) {
                item {
                    EmptyState(
                        title = if (showingArchived) "没有已归档会话" else "还没有 Codex 会话",
                        subtitle = "点击聊天创建新的 Codex session",
                    )
                }
            } else {
                groups.forEach { group ->
                    item {
                        Text(group.title, fontWeight = FontWeight.SemiBold, color = colors.textPrimary)
                    }
                    items(group.sessions) { session ->
                        CodexSessionRow(
                            session = session,
                            onOpen = { onOpenSession(session.sessionId) },
                            onArchiveToggle = {
                                if (showingArchived) {
                                    viewModel.unarchiveCodexSession(profile.id, session.sessionId)
                                } else {
                                    viewModel.archiveCodexSession(profile.id, session.sessionId)
                                }
                            },
                            archived = showingArchived,
                        )
                    }
                }
            }
        }

        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 12.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            OutlinedTextField(
                value = query,
                onValueChange = { query = it },
                modifier = Modifier.weight(1f),
                placeholder = { Text("搜索聊天记录") },
                singleLine = true,
            )
            Spacer(Modifier.width(8.dp))
            Button(onClick = { viewModel.createCodexSession(profile.id) }) {
                Icon(Icons.Filled.Chat, contentDescription = null)
                Spacer(Modifier.width(6.dp))
                Text("聊天")
            }
        }
    }
}

@Composable
private fun CodexSessionRow(
    session: CodexSessionSummary,
    archived: Boolean,
    onOpen: () -> Unit,
    onArchiveToggle: () -> Unit,
) {
    IosPlainRow(onClick = onOpen) {
        Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(
                session.displayTitle,
                fontWeight = FontWeight.Medium,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            Text(
                session.displayPreview,
                fontSize = 13.sp,
                color = MochiTheme.colors.textSecondary,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            Text(
                session.displayProjectName,
                fontSize = 12.sp,
                color = MochiTheme.colors.textSecondary,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
        TextButton(onClick = onArchiveToggle) {
            Text(if (archived) "恢复" else "归档")
        }
    }
}

@Composable
private fun CodexSessionChatScreen(
    profile: AgentProfile,
    sessionId: String,
    viewModel: ChatViewModel,
    onBack: () -> Unit,
) {
    val colors = MochiTheme.colors
    val sessionsByProfile by viewModel.codexSessions.collectAsState()
    val messagesByProfileSession by viewModel.codexMessagesByProfileSession.collectAsState()
    val session = sessionsByProfile[profile.id].orEmpty().firstOrNull { it.sessionId == sessionId }
    val messages = messagesByProfileSession[profile.id]?.get(sessionId).orEmpty()
    var input by remember { mutableStateOf("") }

    LaunchedEffect(profile.id, sessionId) {
        viewModel.requestCodexHistory(profile.id, sessionId)
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(colors.background)
    ) {
        ScreenTopBar(
            title = session?.displayTitle ?: "Codex",
            onBack = onBack,
        )
        LazyColumn(
            modifier = Modifier
                .weight(1f)
                .fillMaxWidth(),
            contentPadding = PaddingValues(horizontal = 16.dp, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            if (messages.isEmpty()) {
                item {
                    EmptyState(title = "开始 Codex 会话", subtitle = "发送文本后将写入当前 session")
                }
            } else {
                items(messages) { message ->
                    MessageBubble(
                        message = message,
                        isUser = message.senderId == "user",
                    )
                }
            }
        }
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            OutlinedTextField(
                value = input,
                onValueChange = { input = it },
                modifier = Modifier.weight(1f),
                minLines = 1,
                maxLines = 4,
                placeholder = { Text("输入消息") },
            )
            Spacer(Modifier.width(8.dp))
            Button(
                enabled = input.isNotBlank(),
                onClick = {
                    val text = input.trim()
                    input = ""
                    viewModel.sendCodexText(profile.id, sessionId, text)
                },
            ) {
                Icon(Icons.Filled.Send, contentDescription = "Send")
            }
        }
    }
}

@Composable
private fun ProviderChatScreen(
    settingsManager: SettingsManager,
    config: GatewayConfig,
    authClient: GatewayAuthClient,
    onBack: () -> Unit,
) {
    val colors = MochiTheme.colors
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val aiSettings by settingsManager.aiSettingsFlow.collectAsState(initial = AiServiceSettings())
    val providerPrefs = remember(context) {
        context.getSharedPreferences("openclaw_provider_chat", Context.MODE_PRIVATE)
    }
    val messages = remember {
        mutableStateListOf<AiChatMessage>().apply {
            addAll(loadProviderChatHistory(providerPrefs.getString("messages_v1", null)))
        }
    }
    var input by remember { mutableStateOf("") }
    var isSending by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    val selectableLlmConfigs = aiSettings.serviceConfigs.llm.filter { it.isSelectableServiceConfig() }
    val llmConfig = aiSettings.llmConfigForProviderChat()
    val llmChoice = llmConfig?.toAiServiceChoice() ?: aiSettings.defaults.llm
    val route = providerChatRouteFor(llmChoice)

    LaunchedEffect(messages.size, messages.lastOrNull()?.content) {
        providerPrefs.edit()
            .putString("messages_v1", encodeProviderChatHistory(messages))
            .apply()
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(colors.background)
    ) {
        ScreenTopBar(
            title = "AI Provider",
            onBack = onBack,
            trailing = {
                TextButton(onClick = { messages.clear() }) {
                    Text("清空")
                }
            },
        )
        LazyColumn(
            modifier = Modifier
                .weight(1f)
                .fillMaxWidth(),
            contentPadding = PaddingValues(horizontal = 16.dp, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            item {
                IosSection(title = "AI Provider") {
                    IosValueRow("当前使用", providerRouteLabel(route, llmChoice))
                    if (selectableLlmConfigs.isNotEmpty()) {
                        IosRowDivider()
                        ChipChoiceRow(
                            label = "LLM 场景",
                            selected = llmConfig?.id ?: aiSettings.sceneSelections.providerChat.llmConfigId,
                            choices = selectableLlmConfigs.map { it.id },
                            onSelect = { configId ->
                                scope.launch {
                                    settingsManager.updateAiSceneSelection(providerChatLlmConfigId = configId)
                                }
                            },
                        )
                    }
                    IosRowDivider()
                    IosValueRow(
                        "状态",
                        if (route == ProviderChatRoute.AGENT_DISABLED) "Agent 模式不可用" else "文本对话",
                    )
                    IosRowDivider()
                    IosPlainRow {
                        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                            Text("和当前 LLM Provider 对话", fontWeight = FontWeight.Medium)
                            Text(
                                "这里不连接 Agent，也不会改动 Agent 对话历史。",
                                fontSize = 13.sp,
                                color = MochiTheme.colors.textSecondary,
                            )
                        }
                    }
                }
            }
            if (messages.isEmpty()) {
                item {
                    EmptyState(title = "暂无消息", subtitle = "输入消息后会保存在本机 AI Provider 历史中")
                }
            } else {
                items(messages) { message ->
                    ProviderChatBubble(message)
                }
            }
            error?.let { text ->
                item {
                    Text(text, color = MaterialTheme.colorScheme.error, fontSize = 13.sp)
                }
            }
        }
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            OutlinedTextField(
                value = input,
                onValueChange = { input = it },
                modifier = Modifier.weight(1f),
                minLines = 1,
                maxLines = 4,
                placeholder = { Text("输入消息") },
            )
            Spacer(Modifier.width(8.dp))
            Button(
                enabled = input.isNotBlank() && !isSending,
                onClick = {
                    val userText = input.trim()
                    input = ""
                    messages += AiChatMessage("user", userText)
                    scope.launch {
                        isSending = true
                        error = null
                        val result = runCatching {
                            sendProviderChat(
                                settingsManager = settingsManager,
                                config = config,
                                authClient = authClient,
                                choice = llmChoice,
                                history = messages.toList(),
                            )
                        }
                        result.onSuccess { reply ->
                            messages += AiChatMessage("assistant", reply.ifBlank { "无内容返回" })
                        }.onFailure { failure ->
                            error = failure.message ?: "Provider Chat 发送失败"
                        }
                        isSending = false
                    }
                },
            ) {
                if (isSending) {
                    CircularProgressIndicator(modifier = Modifier.size(16.dp), strokeWidth = 2.dp)
                } else {
                    Icon(Icons.Filled.Send, contentDescription = "Send")
                }
            }
        }
    }
}

private suspend fun sendProviderChat(
    settingsManager: SettingsManager,
    config: GatewayConfig,
    authClient: GatewayAuthClient,
    choice: AiServiceChoice,
    history: List<AiChatMessage>,
): String {
    return when (providerChatRouteFor(choice)) {
        ProviderChatRoute.ROUTER -> authClient.aiChat(
            gatewayUrl = config.gatewayUrl,
            accessToken = config.accessToken,
            choice = choice,
            messages = history,
        )
        ProviderChatRoute.OPENAI_COMPATIBLE -> {
            val credentialId = choice.resolvedCredentialId()
            val apiKey = settingsManager.localCredential(credentialId)
                ?: error("请先在 AI 服务设置中保存 $credentialId")
            OpenAICompatibleChatClient().chat(
                baseUrl = choice.baseUrl.ifBlank { "https://api.openai.com/v1" },
                apiKey = apiKey,
                model = choice.model.ifBlank { "gpt-4o-mini" },
                messages = history,
            )
        }
        ProviderChatRoute.ANTHROPIC -> {
            val credentialId = choice.resolvedCredentialId()
            val apiKey = settingsManager.localCredential(credentialId)
                ?: error("请先在 AI 服务设置中保存 $credentialId")
            AnthropicChatClient().chat(
                baseUrl = choice.baseUrl.ifBlank { "https://api.anthropic.com/v1" },
                apiKey = apiKey,
                model = choice.model.ifBlank { "claude-sonnet-4-20250514" },
                messages = history,
            )
        }
        ProviderChatRoute.AGENT_DISABLED -> error("AI Provider Chat 不通过 Agent WebSocket 发送")
        ProviderChatRoute.UNSUPPORTED -> error("暂不支持的 Provider 模式")
    }
}

@Composable
private fun RecordingsTabScreen(
    recordings: List<Recording>,
    selectedRecordingId: String?,
    onSelectRecording: (String?) -> Unit,
    recordingStore: RecordingStore,
    recordingSettings: RecordingSettings,
    config: GatewayConfig,
    authClient: GatewayAuthClient,
    isRecording: Boolean,
    audioRecorder: AudioRecorder,
    onStoreChanged: () -> Unit,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val colors = MochiTheme.colors
    val spec = iosParitySpecFor(AndroidRootTab.RECORDINGS)
    var selectedType by remember(recordingSettings) { mutableStateOf(recordingSettings.defaultSelectionType()) }
    var showTypeSelection by remember { mutableStateOf(false) }
    var editingAsrRecordingId by remember { mutableStateOf<String?>(null) }
    var editedAsrText by remember { mutableStateOf("") }
    var reminderTitle by remember { mutableStateOf("") }
    val selected = recordings.firstOrNull { it.id == selectedRecordingId }

    fun stopAndSaveRecording(type: RecordingType) {
        audioRecorder.stopRecording { bytes ->
            val dir = File(context.filesDir, "recordings").apply { mkdirs() }
            val file = File(dir, "recording_${System.currentTimeMillis()}.wav")
            file.writeBytes(bytes)
            recordingStore.createRecording(
                title = "${type.label} ${SimpleDateFormat("MM-dd HH:mm", Locale.getDefault()).format(Date())}",
                type = type,
                audioPath = file.absolutePath,
                durationMillis = 0L,
            )
            onStoreChanged()
        }
    }

    if (showTypeSelection) {
        RecordingTypeSelectionDialog(
            selectedType = selectedType,
            recordingSettings = recordingSettings,
            targetAgentName = "当前 Agent",
            onSelect = { selectedType = it },
            onDismiss = { showTypeSelection = false },
            onConfirm = {
                showTypeSelection = false
                audioRecorder.startRecording()
            },
        )
    }

    if (selected != null) {
        RecordingDetailScreen(
            recording = selected,
            editingAsrRecordingId = editingAsrRecordingId,
            editedAsrText = editedAsrText,
            reminderTitle = reminderTitle,
            onEditedAsrTextChange = { editedAsrText = it },
            onReminderTitleChange = { reminderTitle = it },
            onBack = { onSelectRecording(null) },
            onDelete = {
                recordingStore.deleteRecording(selected.id)
                onStoreChanged()
                onSelectRecording(null)
            },
            onEditAsr = {
                editingAsrRecordingId = selected.id
                editedAsrText = selected.asrText
            },
            onSaveAsr = {
                recordingStore.updateAsrText(selected.id, editedAsrText)
                editingAsrRecordingId = null
                onStoreChanged()
            },
            onAddReminder = {
                if (reminderTitle.isNotBlank()) {
                    recordingStore.addReminder(
                        selected.id,
                        RecordingReminder(
                            id = "reminder_${System.currentTimeMillis()}",
                            title = reminderTitle.trim(),
                        ),
                    )
                    reminderTitle = ""
                    onStoreChanged()
                }
            },
            onStartAsr = {
                scope.launch {
                    runCatching {
                        val file = File(selected.audioPath)
                        val bytes = file.readBytes()
                        val created = authClient.createLongRecordingAsrJob(
                            gatewayUrl = config.gatewayUrl,
                            accessToken = config.accessToken,
                            recordingId = selected.id,
                            filename = file.name,
                            mimeType = "audio/wav",
                            sizeBytes = bytes.size.toLong(),
                            recordingType = selected.type.wireValue,
                            asrProfileId = config.asrProfileId.takeIf { config.asrMode != "backend" },
                            agentPrompt = recordingSettings.promptFor(selected.type)
                                .takeIf { selected.type != RecordingType.AUDIO_ONLY && it.isNotBlank() },
                        )
                        recordingStore.updateAsrJob(selected.id, created.toRecordingAsrJob())
                        onStoreChanged()

                        val chunkSize = 512 * 1024
                        val chunks = bytes.toList().chunked(chunkSize)
                        var latest = created
                        chunks.forEachIndexed { index, chunk ->
                            latest = authClient.uploadLongRecordingAsrChunk(
                                gatewayUrl = config.gatewayUrl,
                                accessToken = config.accessToken,
                                jobId = created.jobId,
                                chunkIndex = index,
                                totalChunks = chunks.size,
                                bytes = chunk.toByteArray(),
                            )
                            recordingStore.updateAsrJob(selected.id, latest.toRecordingAsrJob())
                            onStoreChanged()
                        }
                        val completed = authClient.completeLongRecordingAsrJob(
                            gatewayUrl = config.gatewayUrl,
                            accessToken = config.accessToken,
                            jobId = latest.jobId.ifBlank { created.jobId },
                        )
                        recordingStore.updateAsrJob(selected.id, completed.toRecordingAsrJob())
                        completed.text?.takeIf { it.isNotBlank() }?.let { text ->
                            recordingStore.updateAsrText(selected.id, text)
                        }
                        onStoreChanged()
                    }.onFailure { failure ->
                        recordingStore.updateAsrJob(
                            selected.id,
                            RecordingAsrJob(
                                jobId = selected.asrJob?.jobId ?: "failed_${System.currentTimeMillis()}",
                                status = RecordingAsrJobStatus.FAILED,
                                progress = 1.0,
                                error = failure.message ?: "ASR 上传失败",
                            ),
                        )
                        onStoreChanged()
                    }
                }
            },
        )
        return
    }

    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .background(colors.background),
        contentPadding = PaddingValues(horizontal = 16.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        item {
            TabHeader(
                title = spec.title,
                actionLabel = if (isRecording) "结束录音" else "开始录音",
                onAction = {
                    if (isRecording) {
                        stopAndSaveRecording(selectedType)
                    } else {
                        selectedType = recordingSettings.defaultSelectionType()
                        showTypeSelection = true
                    }
                },
            )
        }
        item {
            IosSection(title = spec.sections[0].title) {
                if (recordings.isEmpty()) {
                    IosPlainRow {
                        Text(
                            "点击右上角 + 新增录音",
                            color = MochiTheme.colors.textSecondary,
                            fontSize = 14.sp,
                        )
                    }
                } else {
                    recordings.forEachIndexed { index, recording ->
                        RecordingRow(recording = recording, onClick = { onSelectRecording(recording.id) })
                        if (index != recordings.lastIndex) {
                            IosRowDivider()
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun RecordingDetailScreen(
    recording: Recording,
    editingAsrRecordingId: String?,
    editedAsrText: String,
    reminderTitle: String,
    onEditedAsrTextChange: (String) -> Unit,
    onReminderTitleChange: (String) -> Unit,
    onBack: () -> Unit,
    onDelete: () -> Unit,
    onEditAsr: () -> Unit,
    onSaveAsr: () -> Unit,
    onAddReminder: () -> Unit,
    onStartAsr: () -> Unit,
) {
    val detailSections = recordingDetailParitySections()
    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .background(MochiTheme.colors.background),
        contentPadding = PaddingValues(horizontal = 16.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        item {
            ScreenTopBar(title = recording.title, onBack = onBack, trailing = {
                TextButton(onClick = onDelete) {
                    Text("删除", color = MaterialTheme.colorScheme.error)
                }
            })
        }
        item {
            IosSection(title = detailSections[0].title) {
                IosValueRow("时间", recording.createdAt.recordingTimeText())
                IosRowDivider()
                IosValueRow("状态", recording.asrJob?.status?.label ?: "未生成 ASR 文本")
                IosRowDivider()
                IosValueRow("录音类型", recording.type.label)
                IosRowDivider()
                IosValueRow("来源", "手机录音")
                IosRowDivider()
                IosValueRow("音频", File(recording.audioPath).name.ifBlank { "本地音频" })
                IosRowDivider()
                IosActionRow(
                    title = "上传转写",
                    value = recording.asrJob?.let { "${it.status.label} ${(it.progress * 100).toInt()}%" },
                    onClick = onStartAsr,
                    leading = { Icon(Icons.Filled.TaskAlt, contentDescription = null) },
                )
                IosRowDivider()
                IosPlainRow {
                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text("ASR 文本", fontWeight = FontWeight.Medium, modifier = Modifier.weight(1f))
                            TextButton(onClick = onEditAsr) { Text("编辑") }
                        }
                        if (editingAsrRecordingId == recording.id) {
                            OutlinedTextField(
                                value = editedAsrText,
                                onValueChange = onEditedAsrTextChange,
                                modifier = Modifier.fillMaxWidth(),
                                minLines = 4,
                            )
                            Button(onClick = onSaveAsr) {
                                Icon(Icons.Filled.Save, contentDescription = null)
                                Spacer(Modifier.width(8.dp))
                                Text("保存")
                            }
                        } else {
                            Text(
                                recording.asrText.ifBlank { "未生成 ASR 文本" },
                                color = MochiTheme.colors.textSecondary,
                                fontSize = 14.sp,
                            )
                        }
                    }
                }
                recording.asrJob?.error?.let { error ->
                    IosRowDivider()
                    IosValueRow("错误", error, isError = true)
                }
            }
        }
        item {
            IosSection(title = detailSections[1].title) {
                IosValueRow("状态", if (recording.events.isEmpty()) "未发送" else "已收到事件")
                IosRowDivider()
                IosValueRow("尝试次数", if (recording.events.isEmpty()) "0" else "1")
                IosRowDivider()
                IosPlainRow {
                    Text(
                        recording.events.lastOrNull()?.body ?: "Agent 回复会在这里展示",
                        color = MochiTheme.colors.textSecondary,
                        fontSize = 14.sp,
                    )
                }
            }
        }
        item {
            IosSection(title = detailSections[2].title) {
                IosValueRow("进度", "${recording.events.size} 个事件")
                IosRowDivider()
                if (recording.events.isEmpty()) {
                    IosPlainRow {
                        Text(
                            "Agent 执行任务会在这里展示",
                            color = MochiTheme.colors.textSecondary,
                            fontSize = 14.sp,
                        )
                    }
                } else {
                    recording.events.forEachIndexed { index, event ->
                        IosPlainRow {
                            Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
                                Text(event.title, fontWeight = FontWeight.Medium)
                                event.body?.let {
                                    Text(it, fontSize = 13.sp, color = MochiTheme.colors.textSecondary)
                                }
                                event.artifact?.let {
                                    Text("产物：${it.filename}", fontSize = 13.sp, color = MochiTheme.colors.textSecondary)
                                }
                            }
                        }
                        if (index != recording.events.lastIndex) {
                            IosRowDivider()
                        }
                    }
                }
            }
        }
        item {
            IosSection(title = detailSections[3].title) {
                IosPlainRow {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        OutlinedTextField(
                            value = reminderTitle,
                            onValueChange = onReminderTitleChange,
                            modifier = Modifier.weight(1f),
                            placeholder = { Text("添加待办") },
                        )
                        Spacer(Modifier.width(8.dp))
                        Button(onClick = onAddReminder) { Text("添加") }
                    }
                }
                if (recording.reminders.isEmpty()) {
                    IosRowDivider()
                    IosPlainRow {
                        Text(
                            "需要用户或其他人完成的待办会在这里展示",
                            color = MochiTheme.colors.textSecondary,
                            fontSize = 14.sp,
                        )
                    }
                } else {
                    recording.reminders.forEach { reminder ->
                        IosRowDivider()
                        IosValueRow(reminder.title, if (reminder.isDone) "已完成" else reminder.dueAt ?: "未安排")
                    }
                }
            }
        }
        item {
            IosSection(title = detailSections[4].title) {
                IosPlainRow {
                    Text("导出的定时任务会在这里展示", color = MochiTheme.colors.textSecondary, fontSize = 14.sp)
                }
            }
        }
        item {
            IosSection(title = detailSections[5].title) {
                IosValueRow("Prompt", recording.type.label)
                IosRowDivider()
                IosValueRow("事件", recording.events.size.toString())
                IosRowDivider()
                IosValueRow("提醒", recording.reminders.size.toString())
                IosRowDivider()
                IosValueRow("文件名", File(recording.audioPath).name)
                IosRowDivider()
                IosValueRow("路径", recording.audioPath)
            }
        }
    }
}

@Composable
private fun HeadsetTabScreen(
    settingsManager: SettingsManager,
    headsetStatusLabel: String?,
    headsetStandbyMode: A9UltraStandbyMode,
    showHeadsetStandbyControl: Boolean,
    headsetLedLightEnabled: Boolean,
    showHeadsetLedLightControl: Boolean,
    soundPlaybackEnabled: Boolean,
    isPlaybackSpeaking: Boolean,
    onToggleSoundPlayback: () -> Unit,
    onInterruptPlayback: () -> Unit,
    onToggleHeadsetStandbyMode: () -> Unit,
    onToggleHeadsetLedLight: (Boolean) -> Unit,
) {
    val spec = iosParitySpecFor(AndroidRootTab.HEADSET)
    val scope = rememberCoroutineScope()
    val aiSettings by settingsManager.aiSettingsFlow.collectAsState(initial = AiServiceSettings())
    val selectableTtsConfigs = aiSettings.serviceConfigs.tts.filter { it.isSelectableServiceConfig() }
    var page by remember { mutableStateOf("home") }
    var eqPreset by remember { mutableStateOf("均衡") }
    var leftShortcut by remember { mutableStateOf("长按唤醒") }
    var rightShortcut by remember { mutableStateOf("双击录音") }
    var band80 by remember { mutableStateOf(0f) }
    var band250 by remember { mutableStateOf(0f) }
    var band1000 by remember { mutableStateOf(0f) }
    var band4000 by remember { mutableStateOf(0f) }

    when (page) {
        "eq" -> {
            HeadsetAudioSettingsPage(
                eqPreset = eqPreset,
                onEqPresetChange = { eqPreset = it },
                band80 = band80,
                band250 = band250,
                band1000 = band1000,
                band4000 = band4000,
                onBand80Change = { band80 = it },
                onBand250Change = { band250 = it },
                onBand1000Change = { band1000 = it },
                onBand4000Change = { band4000 = it },
                onBack = { page = "home" },
            )
            return
        }
        "shortcuts" -> {
            HeadsetShortcutSettingsPage(
                leftShortcut = leftShortcut,
                rightShortcut = rightShortcut,
                onLeftShortcutChange = { leftShortcut = it },
                onRightShortcutChange = { rightShortcut = it },
                onBack = { page = "home" },
            )
            return
        }
        "find" -> {
            LocalPlaceholderPage(
                title = "耳机定位",
                rows = listOf("左耳" to "本地演示", "右耳" to "本地演示"),
                onBack = { page = "home" },
            )
            return
        }
        "ota" -> {
            LocalPlaceholderPage(
                title = "固件更新",
                rows = listOf("当前版本" to "A9-local-demo", "更新状态" to "已是最新"),
                onBack = { page = "home" },
            )
            return
        }
    }

    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .background(MochiTheme.colors.background),
        contentPadding = PaddingValues(horizontal = 16.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        item {
            TabHeader(title = spec.title, actionLabel = spec.primaryAction, onAction = {})
        }
        item {
            IosSection(title = spec.sections[0].title, footer = "Android 保留现有 A9 SPP 控制能力。") {
                IosPlainRow {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Filled.Headphones, contentDescription = null, modifier = Modifier.size(32.dp))
                        Spacer(Modifier.width(12.dp))
                        Column(modifier = Modifier.weight(1f)) {
                            Text("A9 Ultra", fontWeight = FontWeight.SemiBold)
                            Text(headsetStatusLabel ?: "未连接耳机", color = MochiTheme.colors.textSecondary, fontSize = 13.sp)
                        }
                        BatteryPill("L", if (headsetStatusLabel == null) "--" else "80%")
                        Spacer(Modifier.width(6.dp))
                        BatteryPill("R", if (headsetStatusLabel == null) "--" else "78%")
                    }
                }
            }
        }
        item {
            IosSection(title = spec.sections[1].title) {
                IosNavigationRow("音频与 EQ", "预设：$eqPreset", onClick = { page = "eq" })
                IosRowDivider()
                IosNavigationRow("手势快捷方式", "左：$leftShortcut · 右：$rightShortcut", onClick = { page = "shortcuts" })
                IosRowDivider()
                IosNavigationRow("耳机定位", "本地演示", onClick = { page = "find" })
                IosRowDivider()
                IosNavigationRow("固件更新", "本地演示", onClick = { page = "ota" })
            }
        }
        item {
            IosSection(title = spec.sections[2].title) {
                SettingSwitchRow("朗读 Agent 回复", soundPlaybackEnabled, onToggleSoundPlayback)
                IosRowDivider()
                ServiceConfigChoiceRow(
                    label = "播放 TTS",
                    selectedId = aiSettings.sceneSelections.playback.ttsConfigId,
                    configs = selectableTtsConfigs,
                    emptyText = "请先到 AI 服务添加 TTS 配置",
                    onSelect = { configId ->
                        scope.launch { settingsManager.updateAiSceneSelection(playbackTtsConfigId = configId) }
                    },
                )
                if (isPlaybackSpeaking) {
                    IosRowDivider()
                    OutlinedButton(onClick = onInterruptPlayback) { Text("停止朗读") }
                }
                if (showHeadsetStandbyControl) {
                    IosRowDivider()
                    SettingActionRow("待机模式", headsetStandbyMode.label, onToggleHeadsetStandbyMode)
                }
                if (showHeadsetLedLightControl) {
                    IosRowDivider()
                    SettingSwitchRow("LED 灯", headsetLedLightEnabled) {
                        onToggleHeadsetLedLight(!headsetLedLightEnabled)
                    }
                }
            }
        }
    }
}

@Composable
private fun SettingsTabShell(
    settingsManager: SettingsManager,
    recordingSettings: RecordingSettings,
    isDark: Boolean,
    onToggleTheme: () -> Unit,
    onOpenWallet: () -> Unit,
    onRecordingSettingsChange: (RecordingSettings) -> Unit,
    aiServiceContent: @Composable () -> Unit,
    connectionSettingsContent: @Composable () -> Unit,
) {
    val spec = iosParitySpecFor(AndroidRootTab.SETTINGS)
    val config by settingsManager.configFlow.collectAsState(initial = GatewayConfig())
    val profilesState by settingsManager.profilesFlow.collectAsState(initial = AgentProfilesState.default())
    var page by remember { mutableStateOf("home") }
    var logoutNotice by remember { mutableStateOf<String?>(null) }
    val currentAgentName = profilesState.profiles.firstOrNull { it.id == profilesState.selectedProfileId }
        ?.resolvedDisplayName
        ?: profilesState.profiles.firstOrNull()?.resolvedDisplayName
        ?: "未选择"
    when (page) {
        "ai" -> Column(Modifier.fillMaxSize()) {
            ScreenTopBar(title = "AI 服务", onBack = { page = "home" })
            Box(Modifier.weight(1f)) { aiServiceContent() }
        }
        "recording" -> RecordingSettingsPage(
            settingsManager = settingsManager,
            settings = recordingSettings,
            onSettingsChange = onRecordingSettingsChange,
            onBack = { page = "home" },
        )
        "headset" -> HeadsetSettingsMenuPage(onBack = { page = "home" })
        "account" -> AccountSecuritySummaryPage(
            accountId = config.accountId,
            deviceLabel = config.deviceLabel.ifBlank { "我的设备" },
            onBack = { page = "home" },
        )
        "connection" -> connectionSettingsContent()
        else -> LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .background(MochiTheme.colors.background),
            contentPadding = PaddingValues(horizontal = 16.dp, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            item {
                TabHeader(title = spec.title)
            }
            item {
                IosSection(title = spec.sections[0].title) {
                    IosValueRow("账号", config.accountId.ifBlank { "未登录" })
                    IosRowDivider()
                    IosValueRow("当前 Agent", currentAgentName)
                }
            }
            item {
                IosSection(title = spec.sections[1].title) {
                    SettingSwitchRow("深色模式", isDark, onToggleTheme)
                    IosRowDivider()
                    IosNavigationRow("AI 服务", "LLM / ASR / TTS", onClick = { page = "ai" })
                    IosRowDivider()
                    IosNavigationRow("录音设置", "主 Agent、录音类型、ASR", onClick = { page = "recording" })
                    IosRowDivider()
                    IosNavigationRow("耳机设置", "EQ、快捷方式、本地能力", onClick = { page = "headset" })
                }
            }
            item {
                IosSection(title = spec.sections[2].title, footer = "切换账号会清空本机 Agent 配置；退出登录会保留本机 Agent 配置。") {
                    IosNavigationRow("钱包与套餐", "余额、套餐、订单", onClick = onOpenWallet)
                    IosRowDivider()
                    IosNavigationRow("账号与安全", "手机号、设备、连接状态", onClick = { page = "account" })
                    IosRowDivider()
                    IosActionRow("切换账号", onClick = { logoutNotice = "请在账号与安全中重新登录" })
                    IosRowDivider()
                    IosActionRow(
                        title = "退出登录",
                        destructive = true,
                        onClick = { logoutNotice = "已保留本机 Agent 配置" },
                    )
                    logoutNotice?.let {
                        IosRowDivider()
                        IosPlainRow {
                            Text(it, color = MochiTheme.colors.textSecondary, fontSize = 13.sp)
                        }
                    }
                }
            }
            item {
                IosSection(title = spec.sections[3].title) {
                    IosValueRow("APP 版本", "1.0")
                }
            }
        }
    }
}

@Composable
private fun AiServiceSettingsScreen(settingsManager: SettingsManager) {
    val scope = rememberCoroutineScope()
    val aiSettings by settingsManager.aiSettingsFlow.collectAsState(initial = AiServiceSettings())
    val profilesState by settingsManager.profilesFlow.collectAsState(initial = AgentProfilesState.default())
    val editingLlm = aiSettings.llmConfigForProviderChat()?.toAiServiceChoice() ?: aiSettings.defaults.llm
    val editingAsr = aiSettings.asrConfigForRecording()?.toAiServiceChoice() ?: aiSettings.defaults.asr
    val editingTts = aiSettings.ttsConfigForPlayback()?.toAiServiceChoice() ?: aiSettings.defaults.tts
    var llm by remember(aiSettings.serviceConfigs.llm) { mutableStateOf(editingLlm) }
    var asr by remember(aiSettings.serviceConfigs.asr) { mutableStateOf(editingAsr) }
    var tts by remember(aiSettings.serviceConfigs.tts) { mutableStateOf(editingTts) }
    var apiKey by remember { mutableStateOf("") }
    var asrApiKey by remember { mutableStateOf("") }
    var ttsApiKey by remember { mutableStateOf("") }
    var notice by remember { mutableStateOf<String?>(null) }
    var editingOverrideProfileId by remember { mutableStateOf<String?>(null) }
    val selectableLlmConfigs = aiSettings.serviceConfigs.llm.filter { it.isSelectableServiceConfig() }
    val selectableAsrConfigs = aiSettings.serviceConfigs.asr.filter { it.isSelectableServiceConfig() }
    val selectableTtsConfigs = aiSettings.serviceConfigs.tts.filter { it.isSelectableServiceConfig() }

    LaunchedEffect(editingLlm) {
        val credentials = AiProviderCatalog.llmProviders.credentialPresence(settingsManager)
        val preferred = if (editingLlm.mode == "byok") {
            AiProviderCatalog.llmProviders.preferredBySavedCredential(editingLlm.providerId) { credentials[it] == true }
        } else {
            null
        }
        val next = preferred?.toChoice(includeVoice = false, currentVoiceId = editingLlm.voiceId) ?: editingLlm
        llm = next
        apiKey = next.credentialId.takeIf { it.isNotBlank() }?.let { settingsManager.localCredential(it).orEmpty() }.orEmpty()
    }

    LaunchedEffect(editingAsr) {
        val credentials = AiProviderCatalog.asrProviders.credentialPresence(settingsManager)
        val preferred = if (editingAsr.mode == "byok") {
            AiProviderCatalog.asrProviders.preferredBySavedCredential(editingAsr.providerId) { credentials[it] == true }
        } else {
            null
        }
        val next = preferred?.toChoice(includeVoice = false, currentVoiceId = editingAsr.voiceId) ?: editingAsr
        asr = next
        asrApiKey = next.credentialId.takeIf { it.isNotBlank() }?.let { settingsManager.localCredential(it).orEmpty() }.orEmpty()
    }

    LaunchedEffect(editingTts) {
        val credentials = AiProviderCatalog.ttsProviders.credentialPresence(settingsManager)
        val preferred = if (editingTts.mode == "byok") {
            AiProviderCatalog.ttsProviders.preferredBySavedCredential(editingTts.providerId) { credentials[it] == true }
        } else {
            null
        }
        val next = preferred?.toChoice(includeVoice = true, currentVoiceId = editingTts.voiceId) ?: editingTts
        tts = next
        ttsApiKey = next.credentialId.takeIf { it.isNotBlank() }?.let { settingsManager.localCredential(it).orEmpty() }.orEmpty()
    }

    val editingProfile = profilesState.profiles.firstOrNull { it.id == editingOverrideProfileId }
    if (editingProfile != null) {
        AgentAiOverrideEditorPage(
            profile = editingProfile,
            settings = aiSettings,
            onBack = { editingOverrideProfileId = null },
            onSave = { nextSettings ->
                scope.launch {
                    settingsManager.updateAiSettings(nextSettings)
                    editingOverrideProfileId = null
                }
            },
        )
        return
    }

    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .background(MochiTheme.colors.background),
        contentPadding = PaddingValues(horizontal = 16.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        item {
            IosSection(title = "服务配置库") {
                IosValueRow("LLM 配置", "${aiSettings.serviceConfigs.llm.size} 个")
                IosRowDivider()
                IosValueRow("ASR 配置", "${aiSettings.serviceConfigs.asr.size} 个")
                IosRowDivider()
                IosValueRow("TTS 配置", "${aiSettings.serviceConfigs.tts.size} 个")
            }
        }
        item {
            IosSection(title = "业务场景") {
                ServiceConfigChoiceRow(
                    label = "Provider Chat",
                    selectedId = aiSettings.sceneSelections.providerChat.llmConfigId,
                    configs = selectableLlmConfigs,
                    emptyText = "无可用 LLM 配置",
                    onSelect = { configId ->
                        scope.launch { settingsManager.updateAiSceneSelection(providerChatLlmConfigId = configId) }
                    },
                )
                IosRowDivider()
                ServiceConfigChoiceRow(
                    label = "录音 ASR",
                    selectedId = aiSettings.sceneSelections.recording.asrConfigId,
                    configs = selectableAsrConfigs,
                    emptyText = "无可用 ASR 配置",
                    onSelect = { configId ->
                        scope.launch { settingsManager.updateAiSceneSelection(recordingAsrConfigId = configId) }
                    },
                )
                IosRowDivider()
                ServiceConfigChoiceRow(
                    label = "播放 TTS",
                    selectedId = aiSettings.sceneSelections.playback.ttsConfigId,
                    configs = selectableTtsConfigs,
                    emptyText = "无可用 TTS 配置",
                    onSelect = { configId ->
                        scope.launch { settingsManager.updateAiSceneSelection(playbackTtsConfigId = configId) }
                    },
                )
            }
        }
        item {
            IosSection(title = "LLM 配置") {
                AiChoiceEditor(
                    label = "服务类型",
                    choice = llm,
                    providers = AiProviderCatalog.llmProviders,
                    apiKey = apiKey,
                    onChoiceChange = { llm = it },
                    onApiKeyChange = { apiKey = it },
                )
                IosRowDivider()
                OutlinedButton(
                    modifier = Modifier.fillMaxWidth(),
                    onClick = {
                        scope.launch {
                            if (llm.credentialId.isNotBlank() && apiKey.isNotBlank()) {
                                settingsManager.updateLocalCredential(llm.credentialId, apiKey)
                            }
                            settingsManager.upsertAiServiceConfig(llm.toAiServiceConfig("llm"))
                            notice = "LLM 配置已保存"
                        }
                    },
                ) {
                    Text("保存 LLM 配置")
                }
            }
        }
        item {
            IosSection(title = "ASR 配置") {
                AiChoiceEditor(
                    label = "服务类型",
                    choice = asr,
                    providers = AiProviderCatalog.asrProviders,
                    apiKey = asrApiKey,
                    onChoiceChange = { asr = it },
                    onApiKeyChange = { asrApiKey = it },
                )
                IosRowDivider()
                OutlinedButton(
                    modifier = Modifier.fillMaxWidth(),
                    onClick = {
                        scope.launch {
                            if (asr.credentialId.isNotBlank() && asrApiKey.isNotBlank()) {
                                settingsManager.updateLocalCredential(asr.credentialId, asrApiKey)
                            }
                            settingsManager.upsertAiServiceConfig(asr.toAiServiceConfig("asr"))
                            notice = "ASR 配置已保存"
                        }
                    },
                ) {
                    Text("保存 ASR 配置")
                }
            }
        }
        item {
            IosSection(title = "TTS 配置") {
                AiChoiceEditor(
                    label = "服务类型",
                    choice = tts,
                    providers = AiProviderCatalog.ttsProviders,
                    apiKey = ttsApiKey,
                    onChoiceChange = { tts = it },
                    onApiKeyChange = { ttsApiKey = it },
                    includeVoice = true,
                )
                IosRowDivider()
                OutlinedButton(
                    modifier = Modifier.fillMaxWidth(),
                    onClick = {
                        scope.launch {
                            if (tts.credentialId.isNotBlank() && ttsApiKey.isNotBlank()) {
                                settingsManager.updateLocalCredential(tts.credentialId, ttsApiKey)
                            }
                            settingsManager.upsertAiServiceConfig(tts.toAiServiceConfig("tts"))
                            notice = "TTS 配置已保存"
                        }
                    },
                ) {
                    Text("保存 TTS 配置")
                }
            }
        }
        item {
            IosSection(title = "Agent 覆盖") {
                profilesState.profiles.forEachIndexed { index, profile ->
                    val override = aiSettings.agentOverrides[profile.id]
                    IosNavigationRow(
                        title = profile.resolvedDisplayName,
                        subtitle = if (override == null || override.inherit) "继承全局默认" else "已覆盖",
                        onClick = { editingOverrideProfileId = profile.id },
                    )
                    if (index != profilesState.profiles.lastIndex) {
                        IosRowDivider()
                    }
                }
            }
        }
        item {
            notice?.let {
                IosSection {
                    Text(it, fontSize = 13.sp, color = MochiTheme.colors.textSecondary)
                }
            }
        }
    }
}

@Composable
private fun RecordingTypeSelector(selectedType: RecordingType, onSelect: (RecordingType) -> Unit) {
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        RecordingType.entries.forEach { type ->
            FilterChip(
                selected = selectedType == type,
                onClick = { onSelect(type) },
                label = { Text(type.label) },
            )
        }
    }
}

@Composable
private fun RecordingRow(recording: Recording, onClick: () -> Unit) {
    IosPlainRow(onClick = onClick) {
        Icon(Icons.Filled.Mic, contentDescription = null)
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
            Text(recording.createdAt.recordingTimeText(), fontWeight = FontWeight.SemiBold, maxLines = 1)
            Text(
                "手机录音 · ${recording.type.label} · ${recording.asrJob?.status?.label ?: "未生成 ASR 文本"}",
                fontSize = 13.sp,
                color = MochiTheme.colors.textSecondary,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            Text(
                recording.asrText.ifBlank { "未生成 ASR 文本" },
                fontSize = 12.sp,
                color = MochiTheme.colors.textSecondary,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
        Column(horizontalAlignment = Alignment.End) {
            Text("${recording.events.size} 事件", fontSize = 12.sp, color = MochiTheme.colors.textSecondary)
            Text("${recording.reminders.size} 提醒", fontSize = 12.sp, color = MochiTheme.colors.textSecondary)
            val artifactCount = recording.events.count { it.artifact != null }
            Text("$artifactCount 产物", fontSize = 12.sp, color = MochiTheme.colors.textSecondary)
        }
    }
}

@Composable
private fun ProviderChatBubble(message: AiChatMessage) {
    val isUser = message.role == "user"
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = if (isUser) Arrangement.End else Arrangement.Start,
    ) {
        Box(
            modifier = Modifier
                .fillMaxWidth(0.84f)
                .clip(RoundedCornerShape(8.dp))
                .background(if (isUser) MaterialTheme.colorScheme.primary else MochiTheme.colors.surface)
                .padding(12.dp),
        ) {
            Text(
                message.content,
                color = if (isUser) MaterialTheme.colorScheme.onPrimary else MochiTheme.colors.textPrimary,
            )
        }
    }
}

@Composable
private fun TabHeader(
    title: String,
    actionLabel: String? = null,
    onAction: (() -> Unit)? = null,
    action: (@Composable () -> Unit)? = null,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .height(44.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(title, fontSize = 22.sp, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f))
        if (actionLabel != null && onAction != null) {
            TextButton(onClick = onAction) {
                Text(actionLabel)
            }
        }
        action?.invoke()
    }
}

@Composable
private fun ScreenTopBar(
    title: String,
    onBack: () -> Unit,
    trailing: (@Composable () -> Unit)? = null,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .height(48.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        IconButton(onClick = onBack) {
            Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
        }
        Text(title, fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f), maxLines = 1, overflow = TextOverflow.Ellipsis)
        trailing?.invoke()
    }
}

@Composable
private fun SurfaceRow(
    onClick: () -> Unit,
    content: @Composable RowScope.() -> Unit,
) {
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick),
        shape = RoundedCornerShape(8.dp),
        colors = CardDefaults.cardColors(containerColor = MochiTheme.colors.surface),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(14.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            content()
        }
    }
}

@Composable
private fun SurfaceBlock(content: @Composable ColumnScope.() -> Unit) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(8.dp),
        colors = CardDefaults.cardColors(containerColor = MochiTheme.colors.surface),
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(14.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            content()
        }
    }
}

@Composable
private fun EmptyState(title: String, subtitle: String) {
    SurfaceBlock {
        Text(title, fontWeight = FontWeight.SemiBold)
        Text(subtitle, color = MochiTheme.colors.textSecondary, fontSize = 13.sp)
    }
}

@Composable
private fun SettingSwitchRow(label: String, checked: Boolean, onToggle: () -> Unit) {
    Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Text(label, modifier = Modifier.weight(1f))
        Switch(checked = checked, onCheckedChange = { onToggle() })
    }
}

@Composable
private fun SettingActionRow(label: String, value: String, onClick: () -> Unit) {
    Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Column(modifier = Modifier.weight(1f)) {
            Text(label)
            Text(value, fontSize = 13.sp, color = MochiTheme.colors.textSecondary)
        }
        OutlinedButton(onClick = onClick) { Text("切换") }
    }
}

@Composable
private fun ChipChoiceRow(
    label: String,
    selected: String,
    choices: List<String>,
    onSelect: (String) -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(label, fontSize = 13.sp, color = MochiTheme.colors.textSecondary)
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            choices.forEach { choice ->
                FilterChip(
                    selected = selected == choice,
                    onClick = { onSelect(choice) },
                    label = { Text(choice) },
                )
            }
        }
    }
}

@Composable
private fun IosSection(
    title: String? = null,
    footer: String? = null,
    content: @Composable ColumnScope.() -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        title?.let {
            Text(
                it.uppercase(),
                color = MochiTheme.colors.textSecondary,
                fontSize = 12.sp,
                fontWeight = FontWeight.Medium,
                modifier = Modifier.padding(horizontal = 8.dp),
            )
        }
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(8.dp))
                .background(MochiTheme.colors.surface),
        ) {
            content()
        }
        footer?.let {
            Text(
                it,
                color = MochiTheme.colors.textSecondary,
                fontSize = 12.sp,
                modifier = Modifier.padding(horizontal = 8.dp),
            )
        }
    }
}

@Composable
private fun IosPlainRow(
    onClick: (() -> Unit)? = null,
    content: @Composable RowScope.() -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier)
            .padding(horizontal = 14.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        content()
    }
}

@Composable
private fun IosValueRow(
    title: String,
    value: String,
    isError: Boolean = false,
) {
    IosPlainRow {
        Text(title, modifier = Modifier.weight(1f), maxLines = 1, overflow = TextOverflow.Ellipsis)
        Text(
            value,
            color = if (isError) MaterialTheme.colorScheme.error else MochiTheme.colors.textSecondary,
            fontSize = 14.sp,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
        )
    }
}

@Composable
private fun IosNavigationRow(
    title: String,
    subtitle: String? = null,
    value: String? = null,
    leading: (@Composable () -> Unit)? = null,
    onClick: () -> Unit,
) {
    IosPlainRow(onClick = onClick) {
        leading?.invoke()
        if (leading != null) Spacer(Modifier.width(12.dp))
        Column(modifier = Modifier.weight(1f)) {
            Text(title, fontWeight = FontWeight.Medium, maxLines = 1, overflow = TextOverflow.Ellipsis)
            subtitle?.let {
                Text(
                    it,
                    color = MochiTheme.colors.textSecondary,
                    fontSize = 13.sp,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
        value?.let {
            Text(it, color = MochiTheme.colors.textSecondary, fontSize = 13.sp)
            Spacer(Modifier.width(6.dp))
        }
        Text(">", color = MochiTheme.colors.textSecondary, fontSize = 16.sp)
    }
}

@Composable
private fun IosActionRow(
    title: String,
    value: String? = null,
    destructive: Boolean = false,
    leading: (@Composable () -> Unit)? = null,
    onClick: () -> Unit,
) {
    IosPlainRow(onClick = onClick) {
        leading?.invoke()
        if (leading != null) Spacer(Modifier.width(12.dp))
        Text(
            title,
            color = if (destructive) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.primary,
            fontWeight = FontWeight.Medium,
            modifier = Modifier.weight(1f),
        )
        value?.let { Text(it, color = MochiTheme.colors.textSecondary, fontSize = 13.sp) }
    }
}

@Composable
private fun IosRowDivider() {
    HorizontalDivider(
        modifier = Modifier.padding(start = 14.dp),
        color = MochiTheme.colors.secondary.copy(alpha = 0.55f),
    )
}

@Composable
private fun BatteryPill(label: String, value: String) {
    Row(
        modifier = Modifier
            .clip(RoundedCornerShape(999.dp))
            .background(MochiTheme.colors.secondary)
            .padding(horizontal = 8.dp, vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(label, fontSize = 11.sp, color = MochiTheme.colors.textSecondary)
        Spacer(Modifier.width(4.dp))
        Text(value, fontSize = 11.sp, fontWeight = FontWeight.Medium)
    }
}

@Composable
private fun RecordingTypeSelectionDialog(
    selectedType: RecordingType,
    recordingSettings: RecordingSettings,
    targetAgentName: String,
    onSelect: (RecordingType) -> Unit,
    onDismiss: () -> Unit,
    onConfirm: () -> Unit,
) {
    val typeOptions = recordingSettings.recordingSelectionTypeOptions()
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("录音类型") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                IosSection(title = "录音类型") {
                    typeOptions.forEachIndexed { index, type ->
                        IosPlainRow(onClick = { onSelect(type) }) {
                            Text(type.label, modifier = Modifier.weight(1f))
                            if (selectedType == type) {
                                Text("已选", color = MaterialTheme.colorScheme.primary, fontSize = 13.sp)
                            }
                        }
                        if (index != typeOptions.lastIndex) IosRowDivider()
                    }
                }
                if (selectedType != RecordingType.AUDIO_ONLY) {
                    IosSection(title = "发送到") {
                        IosValueRow("Agent", targetAgentName)
                    }
                }
            }
        },
        confirmButton = {
            TextButton(onClick = onConfirm) {
                Text(if (selectedType == RecordingType.AUDIO_ONLY) "保存" else "发送给 $targetAgentName")
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("取消") }
        },
    )
}

@Composable
private fun HeadsetAudioSettingsPage(
    eqPreset: String,
    onEqPresetChange: (String) -> Unit,
    band80: Float,
    band250: Float,
    band1000: Float,
    band4000: Float,
    onBand80Change: (Float) -> Unit,
    onBand250Change: (Float) -> Unit,
    onBand1000Change: (Float) -> Unit,
    onBand4000Change: (Float) -> Unit,
    onBack: () -> Unit,
) {
    LazyColumn(
        modifier = Modifier.fillMaxSize().background(MochiTheme.colors.background),
        contentPadding = PaddingValues(horizontal = 16.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        item { ScreenTopBar(title = "音频与 EQ", onBack = onBack) }
        item {
            IosSection(title = "EQ 预设") {
                ChipChoiceRow(
                    label = "预设",
                    selected = eqPreset,
                    choices = listOf("均衡", "人声", "低频"),
                    onSelect = onEqPresetChange,
                )
            }
        }
        item {
            IosSection(title = eqPreset) {
                EqBandRow("80 Hz", band80, onBand80Change)
                IosRowDivider()
                EqBandRow("250 Hz", band250, onBand250Change)
                IosRowDivider()
                EqBandRow("1 kHz", band1000, onBand1000Change)
                IosRowDivider()
                EqBandRow("4 kHz", band4000, onBand4000Change)
            }
        }
    }
}

@Composable
private fun EqBandRow(label: String, value: Float, onValueChange: (Float) -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 14.dp, vertical = 10.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(label, modifier = Modifier.weight(1f))
            Text("${value.toInt()} dB", color = MochiTheme.colors.textSecondary, fontSize = 13.sp)
        }
        Slider(value = value, onValueChange = onValueChange, valueRange = -6f..6f)
        Row {
            Text("-6", color = MochiTheme.colors.textSecondary, fontSize = 12.sp)
            Spacer(Modifier.weight(1f))
            Text("+6", color = MochiTheme.colors.textSecondary, fontSize = 12.sp)
        }
    }
}

@Composable
private fun HeadsetShortcutSettingsPage(
    leftShortcut: String,
    rightShortcut: String,
    onLeftShortcutChange: (String) -> Unit,
    onRightShortcutChange: (String) -> Unit,
    onBack: () -> Unit,
) {
    LazyColumn(
        modifier = Modifier.fillMaxSize().background(MochiTheme.colors.background),
        contentPadding = PaddingValues(horizontal = 16.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        item { ScreenTopBar(title = "手势快捷方式", onBack = onBack) }
        item {
            IosSection(title = "左耳") {
                ChipChoiceRow("手势", leftShortcut, listOf("长按唤醒", "双击录音", "三击静音"), onLeftShortcutChange)
            }
        }
        item {
            IosSection(title = "右耳") {
                ChipChoiceRow("手势", rightShortcut, listOf("长按唤醒", "双击录音", "三击静音"), onRightShortcutChange)
            }
        }
    }
}

@Composable
private fun LocalPlaceholderPage(title: String, rows: List<Pair<String, String>>, onBack: () -> Unit) {
    LazyColumn(
        modifier = Modifier.fillMaxSize().background(MochiTheme.colors.background),
        contentPadding = PaddingValues(horizontal = 16.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        item { ScreenTopBar(title = title, onBack = onBack) }
        item {
            IosSection(title = title) {
                rows.forEachIndexed { index, row ->
                    IosValueRow(row.first, row.second)
                    if (index != rows.lastIndex) IosRowDivider()
                }
            }
        }
    }
}

@Composable
private fun RecordingSettingsPage(
    settingsManager: SettingsManager,
    settings: RecordingSettings,
    onSettingsChange: (RecordingSettings) -> Unit,
    onBack: () -> Unit,
) {
    val scope = rememberCoroutineScope()
    val aiSettings by settingsManager.aiSettingsFlow.collectAsState(initial = AiServiceSettings())
    val selectableAsrConfigs = aiSettings.serviceConfigs.asr.filter { it.isSelectableServiceConfig() }
    var draft by remember(settings) { mutableStateOf(settings) }
    var localDefault by remember { mutableStateOf(true) }
    fun updateDraft(next: RecordingSettings) {
        draft = next
        onSettingsChange(next)
    }
    LazyColumn(
        modifier = Modifier.fillMaxSize().background(MochiTheme.colors.background),
        contentPadding = PaddingValues(horizontal = 16.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        item { ScreenTopBar(title = "录音设置", onBack = onBack) }
        item {
            IosSection(title = "主 Agent") {
                IosValueRow("主 Agent", "当前 Agent")
                IosRowDivider()
                SettingSwitchRow("本机录音默认执行", localDefault) { localDefault = !localDefault }
                IosRowDivider()
                ChipChoiceRow("录音类型", draft.defaultType.label, draft.settingsTypeOptions().map { it.label }) { label ->
                    updateDraft(draft.copy(defaultType = draft.settingsTypeOptions().first { it.label == label }))
                }
            }
        }
        item {
            IosSection(title = "自定义提示词") {
                IosPlainRow {
                    OutlinedTextField(
                        value = draft.customPrompt,
                        onValueChange = { updateDraft(draft.copy(customPrompt = it)) },
                        modifier = Modifier.fillMaxWidth(),
                        minLines = 3,
                        placeholder = { Text("自定义录音 Prompt") },
                    )
                }
            }
        }
        item {
            IosSection(title = "ASR") {
                ServiceConfigChoiceRow(
                    label = "当前使用",
                    selectedId = aiSettings.sceneSelections.recording.asrConfigId,
                    configs = selectableAsrConfigs,
                    emptyText = "请先到 AI 服务添加 ASR 配置",
                    onSelect = { configId ->
                        selectableAsrConfigs.firstOrNull { it.id == configId }?.let { config ->
                            scope.launch {
                                settingsManager.updateAiSceneSelection(recordingAsrConfigId = configId)
                            }
                            updateDraft(
                                draft.copy(
                                    asrMode = if (config.mode == "backend" || config.mode == "agent") "backend" else "router",
                                    asrProfileId = if (config.mode == "router") config.profileId else null,
                                )
                            )
                        }
                    },
                )
                IosRowDivider()
                IosValueRow(
                    "链路",
                    when (aiSettings.asrConfigForRecording()?.mode) {
                        "backend", "agent" -> "Agent"
                        "byok" -> "BYOK"
                        else -> "Router"
                    }
                )
                IosRowDivider()
                IosPlainRow {
                    Text(
                        "ASR 配置在 AI 服务中维护，本页只选择录音场景使用哪一个配置。",
                        fontSize = 13.sp,
                        color = MochiTheme.colors.textSecondary,
                    )
                }
            }
        }
    }
}

@Composable
private fun HeadsetSettingsMenuPage(onBack: () -> Unit) {
    LazyColumn(
        modifier = Modifier.fillMaxSize().background(MochiTheme.colors.background),
        contentPadding = PaddingValues(horizontal = 16.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        item { ScreenTopBar(title = "耳机设置", onBack = onBack) }
        item {
            IosSection(title = "耳机") {
                IosValueRow("默认设备", "A9 Ultra")
                IosRowDivider()
                IosValueRow("音频与 EQ", "在耳机 tab 编辑")
                IosRowDivider()
                IosValueRow("手势快捷方式", "在耳机 tab 编辑")
            }
        }
    }
}

@Composable
private fun AccountSecuritySummaryPage(
    accountId: String,
    deviceLabel: String,
    onBack: () -> Unit,
) {
    LazyColumn(
        modifier = Modifier.fillMaxSize().background(MochiTheme.colors.background),
        contentPadding = PaddingValues(horizontal = 16.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        item { ScreenTopBar(title = "账号与安全", onBack = onBack) }
        item {
            IosSection(title = "账号") {
                IosValueRow("账号", accountId.ifBlank { "未登录" })
                IosRowDivider()
                IosValueRow("设备名", deviceLabel)
                IosRowDivider()
                IosValueRow("登录状态", if (accountId.isBlank()) "未登录" else "已登录")
            }
        }
    }
}

@Composable
private fun ServiceConfigChoiceRow(
    label: String,
    selectedId: String,
    configs: List<AiServiceConfig>,
    emptyText: String,
    onSelect: (String) -> Unit,
) {
    if (configs.isEmpty()) {
        IosValueRow(label, emptyText)
        return
    }
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        IosValueRow(label, configs.firstOrNull { it.id == selectedId }?.serviceConfigLabel() ?: "未选择")
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            configs.forEach { config ->
                FilterChip(
                    selected = selectedId == config.id,
                    onClick = { onSelect(config.id) },
                    label = { Text(config.serviceConfigLabel()) },
                )
            }
        }
    }
}

private fun AiServiceConfig.serviceConfigLabel(): String =
    when (mode) {
        "router" -> "Router ${profileId.ifBlank { "default" }}"
        "byok" -> "BYOK ${providerId.ifBlank { displayName.ifBlank { "Custom" } }}"
        "backend", "agent" -> "Agent"
        "system" -> "System"
        else -> displayName.ifBlank { id }
    }

@Composable
private fun AiChoiceEditor(
    label: String,
    choice: AiServiceChoice,
    providers: List<AiProviderDescriptor>,
    apiKey: String,
    onChoiceChange: (AiServiceChoice) -> Unit,
    onApiKeyChange: (String) -> Unit,
    includeVoice: Boolean = false,
) {
    val selectedProvider = choice.providerId.ifBlank { providers.firstOrNull()?.id.orEmpty() }
    ChipChoiceRow(
        label = label,
        selected = selectedProvider,
        choices = providers.map { it.id },
        onSelect = { providerId ->
            val provider = providers.first { it.id == providerId }
            onChoiceChange(provider.toChoice(includeVoice = includeVoice, currentVoiceId = choice.voiceId))
        },
    )
    if (choice.mode == "router") {
        IosRowDivider()
        IosPlainRow {
            OutlinedTextField(
                value = choice.profileId,
                onValueChange = { onChoiceChange(choice.copy(profileId = it)) },
                modifier = Modifier.fillMaxWidth(),
                label = { Text("Profile ID") },
            )
        }
    }
    if (choice.mode == "byok") {
        IosRowDivider()
        IosPlainRow {
            OutlinedTextField(
                value = choice.baseUrl,
                onValueChange = { onChoiceChange(choice.copy(baseUrl = it)) },
                modifier = Modifier.fillMaxWidth(),
                label = { Text("Base URL") },
            )
        }
        IosRowDivider()
        IosPlainRow {
            OutlinedTextField(
                value = choice.model,
                onValueChange = { onChoiceChange(choice.copy(model = it)) },
                modifier = Modifier.fillMaxWidth(),
                label = { Text("Model") },
            )
        }
        if (choice.credentialId.isNotBlank()) {
            IosRowDivider()
            IosPlainRow {
                OutlinedTextField(
                    value = apiKey,
                    onValueChange = onApiKeyChange,
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text("API Key (${choice.credentialId})") },
                    visualTransformation = PasswordVisualTransformation(),
                )
            }
        }
    }
    if (includeVoice) {
        IosRowDivider()
        IosPlainRow {
            OutlinedTextField(
                value = choice.voiceId,
                onValueChange = { onChoiceChange(choice.copy(voiceId = it)) },
                modifier = Modifier.fillMaxWidth(),
                label = { Text("Voice ID") },
            )
        }
    }
}

private suspend fun List<AiProviderDescriptor>.credentialPresence(settingsManager: SettingsManager): Map<String, Boolean> =
    filter { it.credentialId.isNotBlank() }
        .associate { provider ->
            provider.credentialId to !settingsManager.localCredential(provider.credentialId).isNullOrBlank()
        }

private fun AiProviderDescriptor.toChoice(includeVoice: Boolean, currentVoiceId: String): AiServiceChoice =
    AiServiceChoice(
        mode = mode,
        providerId = id,
        profileId = if (mode == "router") "default" else "",
        baseUrl = baseUrl,
        model = defaultModel,
        credentialId = credentialId,
        displayName = displayName,
        voiceId = if (includeVoice && id == "minimax") currentVoiceId.ifBlank { "male-qn-qingse" } else currentVoiceId,
    )

@Composable
private fun AgentAiOverrideEditorPage(
    profile: AgentProfile,
    settings: AiServiceSettings,
    onBack: () -> Unit,
    onSave: (AiServiceSettings) -> Unit,
) {
    val existing = settings.agentOverrides[profile.id] ?: AiAgentOverride()
    var inherit by remember(profile.id, settings) { mutableStateOf(existing.inherit) }
    var llm by remember(profile.id, settings) { mutableStateOf(existing.llm ?: settings.defaults.llm) }
    var asr by remember(profile.id, settings) { mutableStateOf(existing.asr ?: settings.defaults.asr) }
    var tts by remember(profile.id, settings) { mutableStateOf(existing.tts ?: settings.defaults.tts) }
    LazyColumn(
        modifier = Modifier.fillMaxSize().background(MochiTheme.colors.background),
        contentPadding = PaddingValues(horizontal = 16.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        item {
            ScreenTopBar(title = profile.resolvedDisplayName, onBack = onBack, trailing = {
                TextButton(
                    onClick = {
                        onSave(
                            settings.copy(
                                agentOverrides = settings.agentOverrides + (
                                    profile.id to AiAgentOverride(
                                        inherit = inherit,
                                        llm = if (inherit) null else llm,
                                        asr = if (inherit) null else asr,
                                        tts = if (inherit) null else tts,
                                    )
                                )
                            )
                        )
                    }
                ) {
                    Text("保存")
                }
            })
        }
        item {
            IosSection {
                SettingSwitchRow("继承全局默认", inherit) { inherit = !inherit }
            }
        }
        if (!inherit) {
            item {
                IosSection(title = "LLM") {
                    AiChoiceEditor("模型服务", llm, AiProviderCatalog.llmProviders, "", { llm = it }, {})
                }
            }
            item {
                IosSection(title = "ASR") {
                    AiChoiceEditor("ASR 服务", asr, AiProviderCatalog.asrProviders, "", { asr = it }, {})
                }
            }
            item {
                IosSection(title = "TTS") {
                    AiChoiceEditor("TTS 引擎", tts, AiProviderCatalog.ttsProviders, "", { tts = it }, {}, includeVoice = true)
                }
            }
        }
    }
}

@Composable
private fun AgentConfigScreen(
    profile: AgentProfile,
    settingsManager: SettingsManager,
    onBack: () -> Unit,
    onOpenAiService: () -> Unit,
) {
    val scope = rememberCoroutineScope()
    var name by remember(profile.id) { mutableStateOf(profile.resolvedDisplayName) }
    var token by remember(profile.id) { mutableStateOf(profile.token) }
    var notice by remember { mutableStateOf<String?>(null) }
    LazyColumn(
        modifier = Modifier.fillMaxSize().background(MochiTheme.colors.background),
        contentPadding = PaddingValues(horizontal = 16.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        item {
            ScreenTopBar(title = "Agent 配置", onBack = onBack, trailing = {
                TextButton(
                    onClick = {
                        scope.launch {
                            settingsManager.saveProfile(
                                profile.copy(displayName = name, token = token),
                                select = false,
                            )
                            notice = "已保存"
                        }
                    }
                ) {
                    Text("保存")
                }
            })
        }
        item {
            IosSection(title = "Agent") {
                IosPlainRow {
                    OutlinedTextField(
                        value = name,
                        onValueChange = { name = it },
                        modifier = Modifier.fillMaxWidth(),
                        label = { Text("Agent 名称") },
                    )
                }
                notice?.let {
                    IosRowDivider()
                    IosPlainRow { Text(it, color = MochiTheme.colors.textSecondary, fontSize = 13.sp) }
                }
            }
        }
        item {
            IosSection(title = "Agent 连接 Token") {
                IosPlainRow {
                    OutlinedTextField(
                        value = token,
                        onValueChange = { token = it },
                        modifier = Modifier.fillMaxWidth(),
                        label = { Text("Token") },
                        visualTransformation = PasswordVisualTransformation(),
                    )
                }
                IosRowDivider()
                IosValueRow("Backend", profile.backendId.ifBlank { "未配置" })
            }
        }
        item {
            IosSection(title = "AI 服务") {
                IosNavigationRow("AI 服务", "继承全局或单独覆盖", onClick = onOpenAiService)
            }
        }
    }
}

private fun loadProviderChatHistory(raw: String?): List<AiChatMessage> =
    runCatching {
        if (raw.isNullOrBlank()) {
            emptyList()
        } else {
            val array = JSONArray(raw)
            List(array.length()) { index ->
                val obj = array.getJSONObject(index)
                AiChatMessage(
                    role = obj.optString("role").ifBlank { "assistant" },
                    content = obj.optString("content"),
                )
            }.filter { it.content.isNotBlank() }
        }
    }.getOrDefault(emptyList())

private fun encodeProviderChatHistory(messages: List<AiChatMessage>): String {
    val array = JSONArray()
    messages.takeLast(200).forEach { message ->
        array.put(
            JSONObject()
                .put("role", message.role)
                .put("content", message.content)
        )
    }
    return array.toString()
}

private fun SharedPreferences.readRecordingSettings(): RecordingSettings =
    RecordingSettings(
        defaultType = RecordingType.fromWireValue(getString("recording_default_type", null)),
        asrMode = getString("recording_asr_mode", null)?.ifBlank { "router" } ?: "router",
        asrProfileId = getString("recording_asr_profile_id", null)?.takeIf { it.isNotBlank() },
        customPrompt = getString("recording_custom_prompt", null).orEmpty(),
    )

private fun SharedPreferences.writeRecordingSettings(settings: RecordingSettings) {
    edit()
        .putString("recording_default_type", settings.defaultType.wireValue)
        .putString("recording_asr_mode", settings.asrMode.ifBlank { "router" })
        .putString("recording_asr_profile_id", settings.asrProfileId.orEmpty())
        .putString("recording_custom_prompt", settings.customPrompt)
        .apply()
}

private fun Long.recordingTimeText(): String =
    SimpleDateFormat("MM-dd HH:mm", Locale.getDefault()).format(Date(this))

private val RecordingAsrJobStatus.label: String
    get() = when (this) {
        RecordingAsrJobStatus.QUEUED -> "排队中"
        RecordingAsrJobStatus.UPLOADING -> "上传中"
        RecordingAsrJobStatus.PROCESSING -> "处理中"
        RecordingAsrJobStatus.COMPLETED -> "已完成"
        RecordingAsrJobStatus.FAILED -> "失败"
    }

private fun rootTabIcon(tab: AndroidRootTab): ImageVector =
    when (tab) {
        AndroidRootTab.AGENTS -> Icons.Filled.AccountCircle
        AndroidRootTab.RECORDINGS -> Icons.Filled.Mic
        AndroidRootTab.HEADSET -> Icons.Filled.Headphones
        AndroidRootTab.SETTINGS -> Icons.Filled.Settings
    }

private fun providerRouteLabel(route: ProviderChatRoute, choice: AiServiceChoice): String =
    when (route) {
        ProviderChatRoute.ROUTER -> "Router · ${choice.profileId.ifBlank { "default" }}"
        ProviderChatRoute.OPENAI_COMPATIBLE -> "${choice.providerId.ifBlank { "OpenAI Compatible" }} · ${choice.model.ifBlank { "model" }}"
        ProviderChatRoute.ANTHROPIC -> "Claude · ${choice.model.ifBlank { "model" }}"
        ProviderChatRoute.AGENT_DISABLED -> "Agent 模式不可用于 Provider Chat"
        ProviderChatRoute.UNSUPPORTED -> "未支持模式"
    }

private fun RecordingSettings.withAiAsrConfig(config: AiServiceConfig?): RecordingSettings =
    when (config?.mode) {
        "backend", "agent" -> copy(asrMode = "backend", asrProfileId = null)
        "router" -> copy(asrMode = "router", asrProfileId = config.profileId.takeIf { it.isNotBlank() })
        else -> this
    }

private fun com.openclaw.remote.auth.LongRecordingAsrJobResult.toRecordingAsrJob(): RecordingAsrJob =
    RecordingAsrJob(
        jobId = jobId,
        status = RecordingAsrJobStatus.fromWireValue(status),
        progress = progress,
        error = error,
    )
