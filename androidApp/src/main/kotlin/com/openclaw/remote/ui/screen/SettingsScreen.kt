package com.openclaw.remote.ui.screen

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.AddCircle
import androidx.compose.material.icons.filled.AccountCircle
import androidx.compose.material.icons.filled.ChatBubble
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.CreditCard
import androidx.compose.material.icons.filled.DarkMode
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.LightMode
import androidx.compose.material.icons.filled.Link
import androidx.compose.material.icons.filled.LinkOff
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.QrCodeScanner
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.RemoveCircle
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.openclaw.remote.auth.AuthSessionResult
import com.openclaw.remote.auth.AuthMeResult
import com.openclaw.remote.auth.GatewayAuthClient
import com.openclaw.remote.data.AgentAvailabilityStatus
import com.openclaw.remote.data.AgentPlatform
import com.openclaw.remote.data.AgentProfile
import com.openclaw.remote.data.AgentProfilesState
import com.openclaw.remote.data.GatewayConfig
import com.openclaw.remote.data.SettingsManager
import com.openclaw.remote.domain.ConnectionState
import com.openclaw.remote.domain.PairingState
import com.openclaw.remote.headset.MiniMaxVoiceCatalog
import com.openclaw.remote.headset.MiniMaxVoiceOption
import com.openclaw.remote.ui.theme.MochiColors
import com.openclaw.remote.ui.theme.MochiTheme
import com.openclaw.remote.viewmodel.ChatViewModel
import java.net.URL
import java.util.UUID
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONObject

private data class AgentFormState(
    val id: String,
    val isDraft: Boolean,
    val platform: AgentPlatform,
    val displayName: String,
    val gatewayUrl: String,
    val backendId: String,
    val token: String,
    val backendLabel: String?,
    val isPaired: Boolean,
) {
    companion object {
        fun fromProfile(profile: AgentProfile): AgentFormState =
            AgentFormState(
                id = profile.id,
                isDraft = false,
                platform = profile.platform,
                displayName = profile.resolvedDisplayName,
                gatewayUrl = profile.gatewayUrl,
                backendId = profile.backendId,
                token = profile.token,
                backendLabel = profile.backendLabel,
                isPaired = profile.isPaired,
            )

        fun draft(gatewayUrl: String): AgentFormState =
            AgentFormState(
                id = "profile_${UUID.randomUUID().toString().take(8)}",
                isDraft = true,
                platform = AgentPlatform.CUSTOM,
                displayName = "",
                gatewayUrl = gatewayUrl,
                backendId = "",
                token = "",
                backendLabel = null,
                isPaired = false,
            )
    }
}

private enum class AccountSecurityPanel {
    Home,
    EditDisplayName,
    ChangePassword,
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(
    settingsManager: SettingsManager,
    viewModel: ChatViewModel,
    connectionState: ConnectionState,
    pairingState: PairingState,
    pairedBackendLabel: String?,
    isDark: Boolean,
    onToggleTheme: () -> Unit,
    onRequestPair: (String, String) -> Unit,
    onUnpair: () -> Unit,
    onBack: () -> Unit,
    onNavigateToQRScanner: () -> Unit,
    onNavigateToWallet: () -> Unit,
) {
    val scope = rememberCoroutineScope()
    val colors = MochiTheme.colors
    val config by settingsManager.configFlow.collectAsState(initial = GatewayConfig())
    val profilesState by settingsManager.profilesFlow.collectAsState(
        initial = AgentProfilesState.default(),
    )
    val authClient = remember { GatewayAuthClient() }
    var agentForms by remember { mutableStateOf<List<AgentFormState>>(emptyList()) }
    var phoneNumber by remember { mutableStateOf("") }
    var smsCode by remember { mutableStateOf("") }
    var isAuthBusy by remember { mutableStateOf(false) }
    var accountPanel by remember { mutableStateOf<AccountSecurityPanel?>(null) }
    var accountProfile by remember { mutableStateOf<AuthMeResult?>(null) }
    var isAccountProfileLoading by remember { mutableStateOf(false) }
    var deviceLabel by remember(config) { mutableStateOf(config.deviceLabel) }
    var asrMode by remember(config) { mutableStateOf(config.asrMode.ifEmpty { "router" }) }
    var asrProfileId by remember(config) { mutableStateOf(config.asrProfileId) }
    var asrProfiles by remember { mutableStateOf<List<AsrProviderProfile>>(emptyList()) }
    var asrProfileMenuExpanded by remember { mutableStateOf(false) }
    var ttsEngine by remember(config) { mutableStateOf(config.ttsEngine.ifEmpty { "system" }) }
    var minimaxApiKey by remember(config) { mutableStateOf(config.minimaxApiKey) }
    var minimaxVoiceId by remember(config) {
        mutableStateOf(config.minimaxVoiceId.ifEmpty { MiniMaxVoiceCatalog.DEFAULT_VOICE_ID })
    }
    var ttsEngineMenuExpanded by remember { mutableStateOf(false) }
    var minimaxVoiceMenuExpanded by remember { mutableStateOf(false) }
    var fetchedMiniMaxVoices by remember { mutableStateOf<List<MiniMaxVoiceOption>>(emptyList()) }
    var isRefreshingMiniMaxVoices by remember { mutableStateOf(false) }
    val snackbarHostState = remember { SnackbarHostState() }
    val ttsEngines = listOf("system" to "系统 TTS", "minimax" to "MiniMax")
    val minimaxVoices = remember(fetchedMiniMaxVoices, minimaxVoiceId) {
        MiniMaxVoiceCatalog.buildSelectableVoices(minimaxVoiceId, fetchedMiniMaxVoices)
    }

    suspend fun showMessage(message: String) {
        snackbarHostState.showSnackbar(message)
    }

    fun normalizedGateway(value: String): String =
        value.trim().ifEmpty { AgentProfile.DEFAULT_GATEWAY_URL }

    fun authGatewayUrl(): String =
        normalizedGateway(
            profilesState.selectedProfile.gatewayUrl.ifBlank { config.gatewayUrl }
        )

    suspend fun applyAuthSession(session: AuthSessionResult) {
        val nextConfig = config.copy(
            accountId = session.accountId,
            accessToken = session.accessToken,
            refreshToken = session.refreshToken,
            accessExpiresAt = session.accessExpiresAt,
            refreshExpiresAt = session.refreshExpiresAt,
            deviceLabel = deviceLabel.ifEmpty { "我的设备" },
        )
        settingsManager.updateConfig(nextConfig)
    }

    suspend fun saveForm(form: AgentFormState, select: Boolean): AgentProfile? {
        val backendId = form.backendId.trim()
        val gatewayUrl = normalizedGateway(form.gatewayUrl)
        val token = form.token.trim()
        val existing = profilesState.profiles.firstOrNull { it.id == form.id }
        val backendChanged = existing != null && existing.backendId.trim() != backendId
        val gatewayChanged = existing != null &&
            AgentProfile.normalizedGatewayKey(existing.gatewayUrl) != AgentProfile.normalizedGatewayKey(gatewayUrl)
        val tokenChanged = existing != null && existing.token.trim() != token
        val connectionChanged = backendChanged || gatewayChanged || tokenChanged
        val displayName = form.displayName.trim().ifEmpty { form.platform.defaultDisplayName }
        val backendLabel = if (backendChanged) {
            backendId.ifBlank { null }
        } else {
            existing?.backendLabel ?: form.backendLabel ?: backendId.ifBlank { null }
        }
        val profile = AgentProfile(
            id = form.id,
            platform = form.platform,
            displayName = displayName,
            gatewayUrl = gatewayUrl,
            backendId = backendId,
            backendLabel = backendLabel,
            token = token,
            isPaired = existing != null && backendId.isNotEmpty() && !connectionChanged && existing.isPaired,
            asrMode = asrMode,
            asrProfileId = if (asrMode == "backend") "" else asrProfileId,
        )
        val saved = settingsManager.saveProfile(profile, select)
        if (!saved) {
            showMessage(settingsManager.profileAcceptError(gatewayUrl, backendId) ?: "无法保存 Agent")
            return null
        }
        return profile
    }

    LaunchedEffect(profilesState.profiles) {
        agentForms = profilesState.profiles.map(AgentFormState::fromProfile)
    }

    LaunchedEffect(config.gatewayUrl, config.accessToken) {
        if (config.accessToken.isBlank()) {
            accountProfile = null
            isAccountProfileLoading = false
            return@LaunchedEffect
        }
        isAccountProfileLoading = true
        runCatching {
            authClient.me(config.gatewayUrl, config.accessToken)
        }.onSuccess {
            accountProfile = it
        }
        isAccountProfileLoading = false
    }

    DisposableEffect(Unit) {
        onDispose {
            authClient.close()
        }
    }

    LaunchedEffect(agentForms.firstOrNull()?.gatewayUrl, profilesState.selectedProfileId) {
        val gateway = agentForms.firstOrNull { it.gatewayUrl.isNotBlank() }?.gatewayUrl
            ?: profilesState.selectedProfile.gatewayUrl
        val (defaultProfileId, profiles) = fetchAsrProfiles(gateway)
        asrProfiles = profiles
        if (asrProfileId.isBlank()) {
            asrProfileId = defaultProfileId ?: profiles.firstOrNull()?.id ?: ""
        }
    }

    Scaffold(
        containerColor = colors.background,
        snackbarHost = { SnackbarHost(snackbarHostState) },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .background(colors.background),
        ) {
            SettingsTopBar(
                isDark = isDark,
                colors = colors,
                onToggleTheme = onToggleTheme,
                onBack = onBack,
            )

            HorizontalDivider(color = colors.divider, thickness = 0.5.dp)

            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .verticalScroll(rememberScrollState())
                    .padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp),
            ) {
                if (accountPanel != null) {
                    AccountSecurityContent(
                        panel = accountPanel ?: AccountSecurityPanel.Home,
                        accountProfile = accountProfile,
                        fallbackAccountLabel = accountDisplayLabel(config.accountId, accountProfile),
                        isProfileLoading = isAccountProfileLoading,
                        isBusy = isAuthBusy,
                        colors = colors,
                        onBack = {
                            accountPanel = when (accountPanel) {
                                AccountSecurityPanel.EditDisplayName,
                                AccountSecurityPanel.ChangePassword -> AccountSecurityPanel.Home
                                else -> null
                            }
                        },
                        onEditDisplayName = { accountPanel = AccountSecurityPanel.EditDisplayName },
                        onChangePassword = { accountPanel = AccountSecurityPanel.ChangePassword },
                        onSaveDisplayName = { displayName ->
                            scope.launch {
                                if (config.accessToken.isBlank()) {
                                    showMessage("请先登录")
                                    return@launch
                                }
                                isAuthBusy = true
                                runCatching {
                                    authClient.updateAccountDisplayName(
                                        gatewayUrl = authGatewayUrl(),
                                        accessToken = config.accessToken,
                                        displayName = displayName,
                                    )
                                }.onSuccess {
                                    accountProfile = it
                                    accountPanel = AccountSecurityPanel.Home
                                    showMessage("用户名已更新")
                                }.onFailure {
                                    showMessage("用户名更新失败：${it.message ?: "unknown"}")
                                }
                                isAuthBusy = false
                            }
                        },
                        onSubmitPassword = { currentPassword, newPassword ->
                            scope.launch {
                                if (config.accessToken.isBlank()) {
                                    showMessage("请先登录")
                                    return@launch
                                }
                                isAuthBusy = true
                                runCatching {
                                    authClient.changePassword(
                                        gatewayUrl = authGatewayUrl(),
                                        accessToken = config.accessToken,
                                        currentPassword = currentPassword,
                                        newPassword = newPassword,
                                    )
                                }.onSuccess {
                                    applyAuthSession(it)
                                    accountPanel = AccountSecurityPanel.Home
                                    showMessage("密码已修改")
                                }.onFailure {
                                    showMessage("修改密码失败：${it.message ?: "unknown"}")
                                }
                                isAuthBusy = false
                            }
                        },
                    )
                } else {
                ConnectionStatusCard(connectionState, pairingState, pairedBackendLabel, colors, onUnpair)

                Button(
                    onClick = onNavigateToQRScanner,
                    modifier = Modifier.fillMaxWidth(),
                    shape = RoundedCornerShape(8.dp),
                    colors = ButtonDefaults.buttonColors(
                        containerColor = colors.primary,
                        contentColor = colors.onPrimary,
                    ),
                    contentPadding = PaddingValues(vertical = 12.dp),
                ) {
                    Icon(Icons.Default.QrCodeScanner, contentDescription = null, modifier = Modifier.size(20.dp))
                    Spacer(modifier = Modifier.width(8.dp))
                    Text("扫码或新增 Agent", fontSize = 15.sp, fontWeight = FontWeight.Medium)
                }

                agentForms.forEachIndexed { index, form ->
                    val profile = profilesState.profiles.firstOrNull { it.id == form.id }
                    AgentFormCard(
                        form = form,
                        index = index,
                        selected = form.id == profilesState.selectedProfileId,
                        status = profile?.let(viewModel::availabilityStatus) ?: AgentAvailabilityStatus.UNPAIRED,
                        onlyPersistedProfile = profilesState.profiles.size == 1 && !form.isDraft,
                        colors = colors,
                        onChange = { changed ->
                            agentForms = agentForms.map { if (it.id == changed.id) changed else it }
                        },
                        onSelect = {
                            if (!form.isDraft) viewModel.selectProfile(form.id)
                        },
                        onRemove = {
                            scope.launch {
                                if (form.isDraft) {
                                    agentForms = agentForms.filterNot { it.id == form.id }
                                } else if (profilesState.profiles.size <= 1) {
                                    if (form.id == profilesState.selectedProfileId && form.isPaired) onUnpair()
                                    settingsManager.clearProfile(form.id)
                                } else {
                                    if (form.id == profilesState.selectedProfileId && form.isPaired) onUnpair()
                                    settingsManager.deleteProfile(form.id)
                                }
                            }
                        },
                        onPair = {
                            scope.launch {
                                if (form.backendId.isBlank()) {
                                    showMessage("请填写 Backend ID")
                                    return@launch
                                }
                                val saved = saveForm(form, select = true) ?: return@launch
                                onRequestPair(saved.id, saved.backendId)
                            }
                        },
                    )
                }

                AddAgentButton(
                    enabled = agentForms.size < SettingsManager.MAX_AGENT_PROFILES,
                    colors = colors,
                    onClick = {
                        if (agentForms.size >= SettingsManager.MAX_AGENT_PROFILES) {
                            scope.launch { showMessage("最多支持 ${SettingsManager.MAX_AGENT_PROFILES} 个 Agent") }
                        } else {
                            val gateway = agentForms.firstOrNull { it.backendId.isNotBlank() }?.gatewayUrl
                                ?: profilesState.selectedProfile.gatewayUrl
                            agentForms = agentForms + AgentFormState.draft(gateway)
                        }
                    },
                )

                HorizontalDivider(color = colors.divider, thickness = 0.5.dp)

                SectionTitle("AI 服务", colors)
                AiServiceSummaryCard(
                    config = config,
                    asrMode = asrMode,
                    asrProfileId = asrProfileId,
                    ttsEngine = ttsEngine,
                    minimaxApiKey = minimaxApiKey,
                    minimaxVoiceId = minimaxVoiceId,
                    colors = colors,
                    onOpenWallet = onNavigateToWallet,
                )
                Text("语音识别", color = colors.textPrimary, fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
                SegmentedControl(
                    leftText = "Router 识别",
                    rightText = "Agent 识别",
                    leftSelected = asrMode != "backend",
                    colors = colors,
                    onSelectLeft = { asrMode = "router" },
                    onSelectRight = { asrMode = "backend" },
                )
                if (asrMode != "backend") {
                    if (asrProfiles.isEmpty()) {
                        OutlinedTextField(
                            value = asrProfileId,
                            onValueChange = { asrProfileId = it },
                            label = { Text("Provider / Model Profile") },
                            placeholder = { Text("默认 profile 或 volcengine-bigmodel") },
                            modifier = Modifier.fillMaxWidth(),
                            singleLine = true,
                            shape = RoundedCornerShape(8.dp),
                            colors = mochiTextFieldColors(colors),
                        )
                    } else {
                        Box(modifier = Modifier.fillMaxWidth()) {
                            OutlinedButton(
                                onClick = { asrProfileMenuExpanded = true },
                                modifier = Modifier.fillMaxWidth(),
                                shape = RoundedCornerShape(8.dp),
                            ) {
                                val selected = asrProfiles.firstOrNull { it.id == asrProfileId }
                                Text(
                                    text = selected?.let { "${it.providerLabel} · ${it.modelLabel}" } ?: "选择 Provider / Model",
                                    color = colors.textPrimary,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis,
                                )
                            }
                            DropdownMenu(
                                expanded = asrProfileMenuExpanded,
                                onDismissRequest = { asrProfileMenuExpanded = false },
                            ) {
                                asrProfiles.forEach { profile ->
                                    DropdownMenuItem(
                                        text = { Text("${profile.providerLabel} · ${profile.modelLabel}") },
                                        onClick = {
                                            asrProfileId = profile.id
                                            asrProfileMenuExpanded = false
                                        },
                                    )
                                }
                            }
                        }
                    }
                }

                Text("本机语音合成", color = colors.textPrimary, fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
                Box(modifier = Modifier.fillMaxWidth()) {
                    OutlinedButton(
                        onClick = { ttsEngineMenuExpanded = true },
                        modifier = Modifier.fillMaxWidth(),
                        shape = RoundedCornerShape(8.dp),
                    ) {
                        Text(
                            text = ttsEngines.firstOrNull { it.first == ttsEngine }?.second ?: "选择 TTS 引擎",
                            color = colors.textPrimary,
                        )
                    }
                    DropdownMenu(expanded = ttsEngineMenuExpanded, onDismissRequest = { ttsEngineMenuExpanded = false }) {
                        ttsEngines.forEach { (id, label) ->
                            DropdownMenuItem(
                                text = { Text(label) },
                                onClick = {
                                    ttsEngine = id
                                    ttsEngineMenuExpanded = false
                                },
                            )
                        }
                    }
                }
                if (ttsEngine == "minimax") {
                    OutlinedTextField(
                        value = minimaxApiKey,
                        onValueChange = { minimaxApiKey = it },
                        label = { Text("MiniMax API Key") },
                        placeholder = { Text("输入你的 MiniMax API Key") },
                        modifier = Modifier.fillMaxWidth(),
                        singleLine = true,
                        visualTransformation = PasswordVisualTransformation(),
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
                        shape = RoundedCornerShape(8.dp),
                        colors = mochiTextFieldColors(colors),
                    )
                    Box(modifier = Modifier.fillMaxWidth()) {
                        OutlinedButton(
                            onClick = { minimaxVoiceMenuExpanded = true },
                            modifier = Modifier.fillMaxWidth(),
                            shape = RoundedCornerShape(8.dp),
                        ) {
                            Text(
                                text = minimaxVoices.firstOrNull { it.id == minimaxVoiceId }?.let(::voiceLabel) ?: "选择 MiniMax 音色",
                                color = colors.textPrimary,
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis,
                            )
                        }
                        DropdownMenu(
                            expanded = minimaxVoiceMenuExpanded,
                            onDismissRequest = { minimaxVoiceMenuExpanded = false },
                        ) {
                            minimaxVoices.forEach { voice ->
                                DropdownMenuItem(
                                    text = { Text(voiceLabel(voice)) },
                                    onClick = {
                                        minimaxVoiceId = voice.id
                                        minimaxVoiceMenuExpanded = false
                                    },
                                )
                            }
                        }
                    }
                    OutlinedButton(
                        onClick = {
                            scope.launch {
                                if (minimaxApiKey.isBlank()) {
                                    showMessage("请先填写 MiniMax API Key")
                                    return@launch
                                }
                                isRefreshingMiniMaxVoices = true
                                runCatching { MiniMaxVoiceCatalog.fetchAvailableVoices(minimaxApiKey) }
                                    .onSuccess {
                                        fetchedMiniMaxVoices = it
                                        showMessage("已刷新 ${it.size} 个 MiniMax 音色")
                                    }
                                    .onFailure { showMessage("刷新音色失败：${it.message ?: "unknown"}") }
                                isRefreshingMiniMaxVoices = false
                            }
                        },
                        enabled = !isRefreshingMiniMaxVoices,
                        modifier = Modifier.fillMaxWidth(),
                        shape = RoundedCornerShape(8.dp),
                    ) {
                        Icon(Icons.Default.Refresh, contentDescription = null, modifier = Modifier.size(20.dp))
                        Spacer(modifier = Modifier.width(8.dp))
                        Text(if (isRefreshingMiniMaxVoices) "正在刷新音色..." else "从 MiniMax 刷新可用音色")
                    }
                }

                HorizontalDivider(color = colors.divider, thickness = 0.5.dp)

                SectionTitle("短信登录", colors)
                OutlinedTextField(
                    value = phoneNumber,
                    onValueChange = { phoneNumber = it },
                    label = { Text("手机号") },
                    placeholder = { Text("+8613800138000") },
                    modifier = Modifier.fillMaxWidth(),
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Phone),
                    shape = RoundedCornerShape(8.dp),
                    colors = mochiTextFieldColors(colors),
                )
                OutlinedTextField(
                    value = smsCode,
                    onValueChange = { smsCode = it },
                    label = { Text("验证码") },
                    placeholder = { Text("123456") },
                    modifier = Modifier.fillMaxWidth(),
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                    shape = RoundedCornerShape(8.dp),
                    colors = mochiTextFieldColors(colors),
                )
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    OutlinedButton(
                        onClick = {
                            scope.launch {
                                if (phoneNumber.isBlank()) {
                                    showMessage("请先填写手机号")
                                    return@launch
                                }
                                isAuthBusy = true
                                runCatching {
                                    authClient.requestSms(
                                        gatewayUrl = authGatewayUrl(),
                                        phoneNumber = phoneNumber,
                                    )
                                }.onSuccess {
                                    showMessage("验证码已发送，${it.retryAfterSeconds} 秒后可重试")
                                }.onFailure {
                                    showMessage("发送验证码失败：${it.message ?: "unknown"}")
                                }
                                isAuthBusy = false
                            }
                        },
                        enabled = !isAuthBusy,
                        modifier = Modifier.weight(1f),
                        shape = RoundedCornerShape(8.dp),
                    ) {
                        Text("发送验证码")
                    }
                    Button(
                        onClick = {
                            scope.launch {
                                if (phoneNumber.isBlank() || smsCode.isBlank()) {
                                    showMessage("请填写手机号和验证码")
                                    return@launch
                                }
                                isAuthBusy = true
                                runCatching {
                                    authClient.verifySms(
                                        gatewayUrl = authGatewayUrl(),
                                        phoneNumber = phoneNumber,
                                        code = smsCode,
                                        terminalLabel = deviceLabel.ifEmpty { "我的设备" },
                                    )
                                }.onSuccess {
                                    applyAuthSession(it)
                                    showMessage("登录成功")
                                }.onFailure {
                                    showMessage("登录失败：${it.message ?: "unknown"}")
                                }
                                isAuthBusy = false
                            }
                        },
                        enabled = !isAuthBusy,
                        modifier = Modifier.weight(1f),
                        shape = RoundedCornerShape(8.dp),
                        colors = ButtonDefaults.buttonColors(
                            containerColor = colors.primary,
                            contentColor = colors.onPrimary,
                        ),
                    ) {
                        Text("登录")
                    }
                }
                OutlinedButton(
                    onClick = {
                        scope.launch {
                            isAuthBusy = true
                            runCatching {
                                if (config.refreshToken.isNotBlank()) {
                                    authClient.logout(
                                        gatewayUrl = authGatewayUrl(),
                                        refreshToken = config.refreshToken,
                                    )
                                }
                            }
                            viewModel.disconnect()
                            settingsManager.updateConfig(
                                config.copy(
                                    accountId = "",
                                    accessToken = "",
                                    refreshToken = "",
                                    accessExpiresAt = "",
                                    refreshExpiresAt = "",
                                )
                            )
                            showMessage("已退出登录")
                            isAuthBusy = false
                        }
                    },
                    enabled = !isAuthBusy,
                    modifier = Modifier.fillMaxWidth(),
                    shape = RoundedCornerShape(8.dp),
                ) {
                    Text("退出登录")
                }

                HorizontalDivider(color = colors.divider, thickness = 0.5.dp)

                SectionTitle("账号会话", colors)
                OutlinedButton(
                    onClick = { accountPanel = AccountSecurityPanel.Home },
                    modifier = Modifier.fillMaxWidth(),
                    shape = RoundedCornerShape(8.dp),
                ) {
                    Icon(Icons.Default.AccountCircle, contentDescription = null, modifier = Modifier.size(20.dp))
                    Spacer(modifier = Modifier.width(8.dp))
                    Text("账号与安全")
                }
                OutlinedButton(
                    onClick = onNavigateToWallet,
                    modifier = Modifier.fillMaxWidth(),
                    shape = RoundedCornerShape(8.dp),
                ) {
                    Icon(Icons.Default.CreditCard, contentDescription = null, modifier = Modifier.size(20.dp))
                    Spacer(modifier = Modifier.width(8.dp))
                    Text("钱包与套餐")
                }
                Text(
                    text = if (config.accountId.isNotBlank()) {
                        "已登录 · ${accountDisplayLabel(config.accountId, accountProfile)}"
                    } else {
                        "未登录"
                    },
                    color = colors.textSecondary,
                    fontSize = 13.sp,
                    modifier = Modifier.fillMaxWidth(),
                )

                HorizontalDivider(color = colors.divider, thickness = 0.5.dp)

                SectionTitle("设备信息", colors)
                OutlinedTextField(
                    value = deviceLabel,
                    onValueChange = { deviceLabel = it },
                    label = { Text("设备名称") },
                    placeholder = { Text("例如：我的手机") },
                    modifier = Modifier.fillMaxWidth(),
                    singleLine = true,
                    shape = RoundedCornerShape(8.dp),
                    colors = mochiTextFieldColors(colors),
                )

                Button(
                    onClick = {
                        scope.launch {
                            var ok = true
                            agentForms.forEach { form ->
                                val emptyDraft = form.isDraft &&
                                    form.displayName.isBlank() &&
                                    form.backendId.isBlank()
                                if (!emptyDraft && saveForm(form, select = form.id == profilesState.selectedProfileId) == null) {
                                    ok = false
                                }
                            }
                            settingsManager.updateDeviceLabel(deviceLabel)
                            settingsManager.updateGlobalAsr(asrMode, asrProfileId)
                            settingsManager.updateConfig(
                                config.copy(
                                    accountId = config.accountId,
                                    accessToken = config.accessToken,
                                    refreshToken = config.refreshToken,
                                    accessExpiresAt = config.accessExpiresAt,
                                    refreshExpiresAt = config.refreshExpiresAt,
                                    deviceLabel = deviceLabel.ifEmpty { "我的设备" },
                                    asrMode = asrMode,
                                    asrProfileId = if (asrMode == "backend") "" else asrProfileId,
                                    ttsEngine = ttsEngine,
                                    minimaxApiKey = minimaxApiKey,
                                    minimaxVoiceId = minimaxVoiceId,
                                )
                            )
                            if (ok) showMessage("设置已保存")
                        }
                    },
                    modifier = Modifier.fillMaxWidth(),
                    shape = RoundedCornerShape(8.dp),
                    colors = ButtonDefaults.buttonColors(
                        containerColor = colors.primary,
                        contentColor = colors.onPrimary,
                    ),
                    contentPadding = PaddingValues(vertical = 12.dp),
                ) {
                    Text("保存", fontSize = 15.sp, fontWeight = FontWeight.Medium)
                }

                HelpCard(colors)
                }
            }
        }
    }
}

@Composable
private fun AccountSecurityContent(
    panel: AccountSecurityPanel,
    accountProfile: AuthMeResult?,
    fallbackAccountLabel: String,
    isProfileLoading: Boolean,
    isBusy: Boolean,
    colors: MochiColors,
    onBack: () -> Unit,
    onEditDisplayName: () -> Unit,
    onChangePassword: () -> Unit,
    onSaveDisplayName: (String) -> Unit,
    onSubmitPassword: (String, String) -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            SettingsIconButton(
                imageVector = Icons.Default.ArrowBack,
                contentDescription = "返回",
                tint = colors.icon,
                background = colors.inputBg,
                onClick = onBack,
            )
            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(
                    text = when (panel) {
                        AccountSecurityPanel.Home -> "账号与安全"
                        AccountSecurityPanel.EditDisplayName -> "修改用户名"
                        AccountSecurityPanel.ChangePassword -> "修改密码"
                    },
                    fontSize = 18.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = colors.textPrimary,
                )
                Text(
                    text = if (isProfileLoading) "正在同步账号资料" else fallbackAccountLabel,
                    fontSize = 12.sp,
                    color = colors.textSecondary,
                )
            }
        }

        when (panel) {
            AccountSecurityPanel.Home -> AccountSecurityHome(
                accountProfile = accountProfile,
                fallbackAccountLabel = fallbackAccountLabel,
                colors = colors,
                onEditDisplayName = onEditDisplayName,
                onChangePassword = onChangePassword,
            )
            AccountSecurityPanel.EditDisplayName -> EditAccountDisplayNameContent(
                accountProfile = accountProfile,
                fallbackAccountLabel = fallbackAccountLabel,
                isBusy = isBusy,
                colors = colors,
                onSave = onSaveDisplayName,
            )
            AccountSecurityPanel.ChangePassword -> ChangePasswordContent(
                isBusy = isBusy,
                colors = colors,
                onSubmit = onSubmitPassword,
            )
        }
    }
}

@Composable
private fun AccountSecurityHome(
    accountProfile: AuthMeResult?,
    fallbackAccountLabel: String,
    colors: MochiColors,
    onEditDisplayName: () -> Unit,
    onChangePassword: () -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(8.dp))
                .background(colors.surface)
                .border(0.5.dp, colors.divider, RoundedCornerShape(8.dp))
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            AccountInfoRow("账户显示", accountProfile?.accountDisplayName ?: fallbackAccountLabel, colors)
            AccountInfoRow("注册手机号", accountProfile?.phoneNumberMasked ?: "同步后显示", colors)
        }

        OutlinedButton(
            onClick = onEditDisplayName,
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(8.dp),
        ) {
            Icon(Icons.Default.Edit, contentDescription = null, modifier = Modifier.size(20.dp))
            Spacer(modifier = Modifier.width(8.dp))
            Text("修改用户名")
        }
        OutlinedButton(
            onClick = onChangePassword,
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(8.dp),
        ) {
            Icon(Icons.Default.Lock, contentDescription = null, modifier = Modifier.size(20.dp))
            Spacer(modifier = Modifier.width(8.dp))
            Text("修改密码")
        }
    }
}

@Composable
private fun EditAccountDisplayNameContent(
    accountProfile: AuthMeResult?,
    fallbackAccountLabel: String,
    isBusy: Boolean,
    colors: MochiColors,
    onSave: (String) -> Unit,
) {
    var draft by remember(accountProfile?.displayName, fallbackAccountLabel) {
        mutableStateOf(accountProfile?.displayName.orEmpty())
    }
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        OutlinedTextField(
            value = draft,
            onValueChange = { draft = it.take(32) },
            label = { Text("用户名") },
            placeholder = { Text(fallbackAccountLabel) },
            modifier = Modifier.fillMaxWidth(),
            singleLine = true,
            shape = RoundedCornerShape(8.dp),
            colors = mochiTextFieldColors(colors),
        )
        Text(
            text = "留空不保存。用户名保存后会作为账户显示；未设置时显示脱敏手机号。",
            color = colors.textSecondary,
            fontSize = 12.sp,
        )
        Button(
            onClick = { onSave(draft) },
            enabled = !isBusy && draft.trim().isNotEmpty(),
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(8.dp),
            colors = ButtonDefaults.buttonColors(
                containerColor = colors.primary,
                contentColor = colors.onPrimary,
            ),
        ) {
            Text(if (isBusy) "正在保存..." else "保存用户名")
        }
    }
}

@Composable
private fun ChangePasswordContent(
    isBusy: Boolean,
    colors: MochiColors,
    onSubmit: (String, String) -> Unit,
) {
    var currentPassword by remember { mutableStateOf("") }
    var newPassword by remember { mutableStateOf("") }
    var confirmNewPassword by remember { mutableStateOf("") }
    var validationMessage by remember { mutableStateOf<String?>(null) }

    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        OutlinedTextField(
            value = currentPassword,
            onValueChange = { currentPassword = it },
            label = { Text("当前密码") },
            modifier = Modifier.fillMaxWidth(),
            singleLine = true,
            visualTransformation = PasswordVisualTransformation(),
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
            shape = RoundedCornerShape(8.dp),
            colors = mochiTextFieldColors(colors),
        )
        OutlinedTextField(
            value = newPassword,
            onValueChange = { newPassword = it },
            label = { Text("新密码") },
            modifier = Modifier.fillMaxWidth(),
            singleLine = true,
            visualTransformation = PasswordVisualTransformation(),
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
            shape = RoundedCornerShape(8.dp),
            colors = mochiTextFieldColors(colors),
        )
        OutlinedTextField(
            value = confirmNewPassword,
            onValueChange = { confirmNewPassword = it },
            label = { Text("确认新密码") },
            modifier = Modifier.fillMaxWidth(),
            singleLine = true,
            visualTransformation = PasswordVisualTransformation(),
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
            shape = RoundedCornerShape(8.dp),
            colors = mochiTextFieldColors(colors),
        )
        validationMessage?.let {
            Text(text = it, color = colors.recordingRed, fontSize = 12.sp)
        }
        Button(
            onClick = {
                validationMessage = when {
                    currentPassword.isBlank() -> "请输入当前密码"
                    newPassword.length < 8 -> "新密码至少 8 位"
                    newPassword != confirmNewPassword -> "两次新密码不一致"
                    else -> null
                }
                if (validationMessage == null) onSubmit(currentPassword, newPassword)
            },
            enabled = !isBusy,
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(8.dp),
            colors = ButtonDefaults.buttonColors(
                containerColor = colors.primary,
                contentColor = colors.onPrimary,
            ),
        ) {
            Text(if (isBusy) "正在修改..." else "确认修改密码")
        }
    }
}

@Composable
private fun AccountInfoRow(label: String, value: String, colors: MochiColors) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(label, color = colors.textSecondary, fontSize = 13.sp)
        Text(
            value,
            color = colors.textPrimary,
            fontSize = 14.sp,
            fontWeight = FontWeight.Medium,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
    }
}

@Composable
private fun SettingsTopBar(
    isDark: Boolean,
    colors: MochiColors,
    onToggleTheme: () -> Unit,
    onBack: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(colors.surface)
            .padding(horizontal = 12.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(
                text = "设置",
                fontSize = 16.sp,
                fontWeight = FontWeight.SemiBold,
                color = colors.textPrimary,
            )
            Text(
                text = "Gateway 与配对",
                fontSize = 11.sp,
                color = colors.textSecondary,
            )
        }

        SettingsIconButton(
            imageVector = if (isDark) Icons.Filled.LightMode else Icons.Filled.DarkMode,
            contentDescription = if (isDark) "切换到浅色模式" else "切换到深色模式",
            tint = if (isDark) colors.accent else colors.primary,
            background = if (isDark) colors.secondary.copy(alpha = 0.72f) else Color.Transparent,
            onClick = onToggleTheme,
        )
        SettingsIconButton(
            imageVector = Icons.Filled.ChatBubble,
            contentDescription = "返回聊天",
            tint = colors.icon,
            background = colors.inputBg,
            onClick = onBack,
        )
    }
}

@Composable
private fun SettingsIconButton(
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
private fun AddAgentButton(
    enabled: Boolean,
    colors: MochiColors,
    onClick: () -> Unit,
) {
    Box(
        modifier = Modifier.fillMaxWidth(),
        contentAlignment = Alignment.Center,
    ) {
        Box(
            modifier = Modifier
                .size(width = 52.dp, height = 40.dp)
                .clip(CircleShape)
                .background(if (enabled) colors.inputBg else colors.inputBorder.copy(alpha = 0.45f))
                .border(0.5.dp, colors.inputBorder, CircleShape)
                .clickable(enabled = enabled, onClick = onClick),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                imageVector = Icons.Default.AddCircle,
                contentDescription = "新增 Agent",
                tint = if (enabled) colors.primary else colors.textSecondary.copy(alpha = 0.45f),
                modifier = Modifier.size(24.dp),
            )
        }
    }
}

@Composable
private fun SegmentedControl(
    leftText: String,
    rightText: String,
    leftSelected: Boolean,
    colors: MochiColors,
    onSelectLeft: () -> Unit,
    onSelectRight: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(8.dp))
            .background(colors.inputBg)
            .border(1.dp, colors.inputBorder, RoundedCornerShape(8.dp))
            .padding(3.dp),
        horizontalArrangement = Arrangement.spacedBy(3.dp),
    ) {
        SegmentOption(
            text = leftText,
            selected = leftSelected,
            colors = colors,
            onClick = onSelectLeft,
            modifier = Modifier.weight(1f),
        )
        SegmentOption(
            text = rightText,
            selected = !leftSelected,
            colors = colors,
            onClick = onSelectRight,
            modifier = Modifier.weight(1f),
        )
    }
}

@Composable
private fun SegmentOption(
    text: String,
    selected: Boolean,
    colors: MochiColors,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Box(
        modifier = modifier
            .height(34.dp)
            .clip(RoundedCornerShape(7.dp))
            .background(if (selected) colors.primary else Color.Transparent)
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text = text,
            fontSize = 13.sp,
            fontWeight = FontWeight.Medium,
            color = if (selected) colors.onPrimary else colors.textSecondary,
            maxLines = 1,
        )
    }
}

@Composable
private fun StatusPill(
    text: String,
    color: Color,
) {
    Text(
        text = text,
        fontSize = 11.sp,
        fontWeight = FontWeight.Medium,
        color = color,
        maxLines = 1,
        modifier = Modifier
            .clip(RoundedCornerShape(8.dp))
            .background(color.copy(alpha = 0.12f))
            .padding(horizontal = 8.dp, vertical = 4.dp),
    )
}

private fun agentStatusColor(
    status: AgentAvailabilityStatus,
    colors: MochiColors,
): Color {
    return when (status) {
        AgentAvailabilityStatus.AVAILABLE -> colors.onlineGreen
        AgentAvailabilityStatus.PAIRING, AgentAvailabilityStatus.CONNECTING, AgentAvailabilityStatus.OFFLINE -> colors.accent
        AgentAvailabilityStatus.UNCONFIGURED, AgentAvailabilityStatus.UNPAIRED -> colors.textSecondary
    }
}

@Composable
private fun mochiTextFieldColors(colors: MochiColors) = OutlinedTextFieldDefaults.colors(
    focusedTextColor = colors.inputText,
    unfocusedTextColor = colors.inputText,
    cursorColor = colors.primary,
    focusedBorderColor = colors.primary,
    unfocusedBorderColor = colors.inputBorder,
    focusedLabelColor = colors.primary,
    unfocusedLabelColor = colors.textSecondary,
    focusedContainerColor = colors.inputBg,
    unfocusedContainerColor = colors.inputBg,
    focusedPlaceholderColor = colors.inputPlaceholder,
    unfocusedPlaceholderColor = colors.inputPlaceholder,
)

@Composable
private fun AgentFormCard(
    form: AgentFormState,
    index: Int,
    selected: Boolean,
    status: AgentAvailabilityStatus,
    onlyPersistedProfile: Boolean,
    colors: MochiColors,
    onChange: (AgentFormState) -> Unit,
    onSelect: () -> Unit,
    onRemove: () -> Unit,
    onPair: () -> Unit,
) {
    val statusColor = agentStatusColor(status, colors)
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(8.dp))
            .background(colors.surface)
            .border(
                width = if (selected) 1.5.dp else 0.5.dp,
                color = if (selected) colors.primary else colors.divider,
                shape = RoundedCornerShape(8.dp),
            )
            .padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(
                modifier = Modifier
                    .clip(RoundedCornerShape(8.dp))
                    .clickable(onClick = onSelect)
                    .padding(vertical = 4.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Icon(
                    imageVector = if (selected) Icons.Filled.CheckCircle else Icons.Default.Link,
                    contentDescription = if (selected) "当前 Agent" else "选择 Agent",
                    tint = if (selected) colors.primary else colors.textPrimary,
                    modifier = Modifier.size(17.dp),
                )
                Column {
                    Text(
                        text = "Agent ${index + 1}",
                        fontSize = 14.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = if (selected) colors.primary else colors.textPrimary,
                    )
                    Text(
                        text = form.platform.label,
                        fontSize = 11.sp,
                        color = colors.textSecondary,
                    )
                }
            }

            StatusPill(status.label, statusColor)

            Spacer(modifier = Modifier.weight(1f))

            SettingsIconButton(
                imageVector = Icons.Filled.RemoveCircle,
                contentDescription = if (onlyPersistedProfile) "清空 Agent" else "删除 Agent",
                tint = colors.recordingRed,
                background = colors.recordingRed.copy(alpha = 0.10f),
                onClick = onRemove,
            )
        }

        OutlinedTextField(
            value = form.displayName,
            onValueChange = { onChange(form.copy(displayName = it)) },
            label = { Text("Agent 名称") },
            placeholder = { Text(form.platform.defaultDisplayName) },
            modifier = Modifier.fillMaxWidth(),
            singleLine = true,
            shape = RoundedCornerShape(8.dp),
            colors = mochiTextFieldColors(colors),
        )
        OutlinedTextField(
            value = form.gatewayUrl,
            onValueChange = { onChange(form.copy(gatewayUrl = it)) },
            label = { Text("Gateway URL") },
            placeholder = { Text(AgentProfile.DEFAULT_GATEWAY_URL) },
            modifier = Modifier.fillMaxWidth(),
            singleLine = true,
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri),
            shape = RoundedCornerShape(8.dp),
            colors = mochiTextFieldColors(colors),
        )
        OutlinedTextField(
            value = form.backendId,
            onValueChange = { onChange(form.copy(backendId = it)) },
            label = { Text("Backend ID") },
            placeholder = { Text("bk_xxx") },
            modifier = Modifier.fillMaxWidth(),
            singleLine = true,
            shape = RoundedCornerShape(8.dp),
            colors = mochiTextFieldColors(colors),
        )
        Button(
            onClick = onPair,
            enabled = form.backendId.isNotBlank(),
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(8.dp),
            colors = ButtonDefaults.buttonColors(
                containerColor = colors.primary,
                contentColor = colors.onPrimary,
                disabledContainerColor = colors.textSecondary.copy(alpha = 0.30f),
                disabledContentColor = colors.surface,
            ),
            contentPadding = PaddingValues(vertical = 12.dp),
        ) {
            Icon(Icons.Default.Link, contentDescription = null, modifier = Modifier.size(20.dp))
            Spacer(modifier = Modifier.width(8.dp))
            Text("配对", fontSize = 15.sp, fontWeight = FontWeight.Medium)
        }
    }
}

@Composable
private fun ConnectionStatusCard(
    connectionState: ConnectionState,
    pairingState: PairingState,
    pairedBackendLabel: String?,
    colors: MochiColors,
    onUnpair: () -> Unit
) {
    val statusText = settingsConnectionStatusText(connectionState, pairingState, pairedBackendLabel)
    val (statusColor, statusIcon) = when {
        pairingState == PairingState.PAIRED && connectionState == ConnectionState.PAIRED -> Pair(
            colors.primary,
            Icons.Default.Link
        )
        pairingState == PairingState.PAIRED -> Pair(
            colors.accent,
            Icons.Default.Link
        )
        pairingState == PairingState.PENDING -> Pair(
            colors.accent,
            Icons.Default.Link
        )
        connectionState == ConnectionState.CONNECTED || connectionState == ConnectionState.REGISTERED -> Pair(
            colors.accent,
            Icons.Default.Link
        )
        connectionState == ConnectionState.CONNECTING -> Pair(
            colors.accent,
            Icons.Default.Link
        )
        else -> Pair(
            colors.recordingRed,
            Icons.Default.LinkOff
        )
    }

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .background(statusColor.copy(alpha = 0.10f))
            .border(0.5.dp, statusColor.copy(alpha = 0.16f), RoundedCornerShape(12.dp))
            .padding(16.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Icon(
            imageVector = statusIcon,
            contentDescription = null,
            tint = statusColor,
            modifier = Modifier.size(24.dp)
        )
        Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(
                text = "连接状态",
                fontSize = 12.sp,
                color = colors.textSecondary,
            )
            Text(
                text = statusText,
                fontSize = 14.sp,
                fontWeight = FontWeight.Medium,
                color = statusColor,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
        if (pairingState == PairingState.PAIRED) {
            TextButton(onClick = onUnpair) {
                Text("取消配对", color = colors.recordingRed, fontSize = 12.sp)
            }
        }
    }
}

internal fun settingsConnectionStatusText(
    connectionState: ConnectionState,
    pairingState: PairingState,
    pairedBackendLabel: String?,
): String {
    val pairedStatusSuffix = if (pairedBackendLabel != null) "：$pairedBackendLabel" else ""
    return when {
        pairingState == PairingState.PAIRED && connectionState == ConnectionState.PAIRED -> "已配对$pairedStatusSuffix"
        pairingState == PairingState.PAIRED -> "重连中$pairedStatusSuffix"
        pairingState == PairingState.PENDING -> "正在连接 Agent$pairedStatusSuffix"
        connectionState == ConnectionState.CONNECTED || connectionState == ConnectionState.REGISTERED ->
            "Router 已连接，Agent 未配对"
        connectionState == ConnectionState.CONNECTING -> "连接中..."
        else -> "未连接"
    }
}

@Composable
private fun SectionTitle(text: String, colors: MochiColors) {
    Text(
        text = text,
        fontSize = 13.sp,
        fontWeight = FontWeight.Medium,
        color = colors.primary,
        modifier = Modifier.padding(top = 8.dp)
    )
}

@Composable
private fun HelpCard(colors: MochiColors) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(8.dp))
            .background(colors.surface.copy(alpha = 0.60f))
            .border(0.5.dp, colors.divider, RoundedCornerShape(8.dp))
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Text(
            text = "使用说明",
            fontSize = 14.sp,
            fontWeight = FontWeight.Medium,
            color = colors.textPrimary,
        )
        Text(
            text = """
                    1. 扫描 Gateway Plugin 生成的二维码
                    2. 相同 Gateway + Backend ID 会覆盖旧 Agent
                    3. 新 Backend ID 会新增 Agent，最多 3 个
                    4. 在顶部 Agent 标签中切换会话
                """.trimIndent(),
            fontSize = 12.sp,
            color = colors.textSecondary,
            lineHeight = 18.sp
        )
    }
}

@Composable
private fun AiServiceSummaryCard(
    config: GatewayConfig,
    asrMode: String,
    asrProfileId: String,
    ttsEngine: String,
    minimaxApiKey: String,
    minimaxVoiceId: String,
    colors: MochiColors,
    onOpenWallet: () -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(8.dp))
            .background(colors.surface)
            .border(0.5.dp, colors.divider, RoundedCornerShape(8.dp))
            .padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        AiServiceInfoRow("会员 / 钱包", if (config.accountId.isBlank()) "未登录" else "可查看套餐与余额", colors)
        AiServiceInfoRow("Router LLM", "会员模型 · default", colors)
        AiServiceInfoRow(
            "ASR",
            if (asrMode == "backend") "Agent 后端识别" else "Router 识别 · ${asrProfileId.ifBlank { "默认" }}",
            colors,
        )
        AiServiceInfoRow(
            "本机 TTS",
            if (ttsEngine == "minimax") {
                val keyStatus = if (minimaxApiKey.isBlank()) "Key 未保存" else "Key 已保存"
                "MiniMax · $keyStatus · ${minimaxVoiceId.ifBlank { MiniMaxVoiceCatalog.DEFAULT_VOICE_ID }}"
            } else {
                "系统 TTS"
            },
            colors,
        )
        OutlinedButton(
            onClick = onOpenWallet,
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(8.dp),
        ) {
            Icon(Icons.Default.CreditCard, contentDescription = null, modifier = Modifier.size(20.dp))
            Spacer(modifier = Modifier.width(8.dp))
            Text("钱包与套餐")
        }
    }
}

@Composable
private fun AiServiceInfoRow(label: String, value: String, colors: MochiColors) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(label, color = colors.textSecondary, fontSize = 12.sp)
        Text(
            value,
            color = colors.textPrimary,
            fontSize = 13.sp,
            fontWeight = FontWeight.Medium,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.weight(1f, fill = false),
        )
    }
}

private data class AsrProviderProfile(
    val id: String,
    val providerLabel: String,
    val modelLabel: String,
)

private fun voiceLabel(voice: MiniMaxVoiceOption): String =
    "${voice.category} · ${voice.name}"

private fun accountDisplayLabel(accountId: String, accountProfile: AuthMeResult?): String {
    val displayName = accountProfile?.accountDisplayName?.trim().orEmpty()
    if (displayName.isNotEmpty()) return displayName
    return if (accountId.isBlank()) "未登录" else "账号已登录"
}

private suspend fun fetchAsrProfiles(gatewayUrl: String): Pair<String?, List<AsrProviderProfile>> {
    return withContext(Dispatchers.IO) {
        try {
            val url = URL(asrProvidersUrl(gatewayUrl))
            val body = url.readText()
            val json = JSONObject(body)
            val defaultProfileId = json.optString("defaultProfileId").ifEmpty { null }
            val profilesJson = json.optJSONArray("profiles")
            val profiles = buildList {
                if (profilesJson != null) {
                    for (i in 0 until profilesJson.length()) {
                        val item = profilesJson.optJSONObject(i) ?: continue
                        val id = item.optString("id")
                        if (id.isBlank()) continue
                        val provider = item.optString("provider")
                        val model = item.optString("model")
                        add(
                            AsrProviderProfile(
                                id = id,
                                providerLabel = item.optString("providerLabel").ifEmpty { provider },
                                modelLabel = item.optString("modelLabel").ifEmpty { model },
                            )
                        )
                    }
                }
            }
            defaultProfileId to profiles
        } catch (_: Exception) {
            null to emptyList()
        }
    }
}

private fun asrProvidersUrl(gatewayUrl: String): String {
    var value = gatewayUrl.trim()
    value = when {
        value.startsWith("wss://") -> "https://" + value.removePrefix("wss://")
        value.startsWith("ws://") -> "http://" + value.removePrefix("ws://")
        else -> "https://$value"
    }
    if (value.endsWith("/ws")) {
        value = value.removeSuffix("/ws")
    }
    return value.trimEnd('/') + "/api/asr/providers"
}
