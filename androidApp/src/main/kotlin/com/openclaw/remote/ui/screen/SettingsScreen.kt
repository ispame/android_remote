package com.openclaw.remote.ui.screen

import androidx.compose.foundation.background
import androidx.compose.foundation.border
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
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.AddCircle
import androidx.compose.material.icons.filled.DarkMode
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.LightMode
import androidx.compose.material.icons.filled.Link
import androidx.compose.material.icons.filled.LinkOff
import androidx.compose.material.icons.filled.QrCodeScanner
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
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
) {
    val scope = rememberCoroutineScope()
    val config by settingsManager.configFlow.collectAsState(initial = GatewayConfig())
    val profilesState by settingsManager.profilesFlow.collectAsState(
        initial = AgentProfilesState.default(config.deviceId),
    )
    var agentForms by remember { mutableStateOf<List<AgentFormState>>(emptyList()) }
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

    suspend fun saveForm(form: AgentFormState, select: Boolean): AgentProfile? {
        val backendId = form.backendId.trim()
        val gatewayUrl = normalizedGateway(form.gatewayUrl)
        val existing = profilesState.profiles.firstOrNull { it.id == form.id }
        val backendChanged = existing?.backendId != backendId
        val displayName = form.displayName.trim().ifEmpty { form.platform.defaultDisplayName }
        val backendLabel = if (backendChanged) {
            backendId.ifBlank { null }
        } else {
            existing?.backendLabel ?: form.backendLabel ?: backendId.ifBlank { null }
        }
        val profile = AgentProfile(
            id = form.id,
            appClientId = config.deviceId,
            platform = form.platform,
            displayName = displayName,
            gatewayUrl = gatewayUrl,
            backendId = backendId,
            backendLabel = backendLabel,
            token = form.token.trim(),
            isPaired = backendId.isNotEmpty() && !backendChanged && (existing?.isPaired ?: form.isPaired),
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
        topBar = {
            TopAppBar(
                title = { Text("设置") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "返回")
                    }
                },
                actions = {
                    IconButton(onClick = onToggleTheme) {
                        Icon(
                            imageVector = if (isDark) Icons.Filled.LightMode else Icons.Filled.DarkMode,
                            contentDescription = if (isDark) "切换到浅色模式" else "切换到深色模式",
                        )
                    }
                }
            )
        },
        snackbarHost = { SnackbarHost(snackbarHostState) },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            ConnectionStatusCard(connectionState, pairingState, pairedBackendLabel, onUnpair)

            Button(onClick = onNavigateToQRScanner, modifier = Modifier.fillMaxWidth()) {
                Icon(Icons.Default.QrCodeScanner, contentDescription = null, modifier = Modifier.size(20.dp))
                Spacer(modifier = Modifier.width(8.dp))
                Text("扫码或新增 Agent")
            }

            agentForms.forEachIndexed { index, form ->
                val profile = profilesState.profiles.firstOrNull { it.id == form.id }
                AgentFormCard(
                    form = form,
                    index = index,
                    selected = form.id == profilesState.selectedProfileId,
                    status = profile?.let(viewModel::availabilityStatus) ?: AgentAvailabilityStatus.UNPAIRED,
                    onlyPersistedProfile = profilesState.profiles.size == 1 && !form.isDraft,
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

            OutlinedButton(
                onClick = {
                    if (agentForms.size >= SettingsManager.MAX_AGENT_PROFILES) {
                        scope.launch { showMessage("最多支持 ${SettingsManager.MAX_AGENT_PROFILES} 个 Agent") }
                    } else {
                        val gateway = agentForms.firstOrNull { it.backendId.isNotBlank() }?.gatewayUrl
                            ?: profilesState.selectedProfile.gatewayUrl
                        agentForms = agentForms + AgentFormState.draft(gateway)
                    }
                },
                enabled = agentForms.size < SettingsManager.MAX_AGENT_PROFILES,
                modifier = Modifier.fillMaxWidth(),
            ) {
                Icon(Icons.Default.AddCircle, contentDescription = null, modifier = Modifier.size(20.dp))
                Spacer(modifier = Modifier.width(8.dp))
                Text("新增 Agent")
            }

            HorizontalDivider()

            SectionTitle("语音识别")
            Row(verticalAlignment = Alignment.CenterVertically) {
                RadioButton(selected = asrMode != "backend", onClick = { asrMode = "router" })
                Text("Router 识别", modifier = Modifier.weight(1f))
                RadioButton(selected = asrMode == "backend", onClick = { asrMode = "backend" })
                Text("Agent 识别")
            }
            if (asrMode != "backend") {
                if (asrProfiles.isEmpty()) {
                    OutlinedTextField(
                        value = asrProfileId,
                        onValueChange = { asrProfileId = it },
                        label = { Text("Provider / Model Profile") },
                        placeholder = { Text("默认 profile 或 volcengine-bigmodel") },
                        modifier = Modifier.fillMaxWidth(),
                        singleLine = true,
                    )
                } else {
                    Box(modifier = Modifier.fillMaxWidth()) {
                        OutlinedButton(
                            onClick = { asrProfileMenuExpanded = true },
                            modifier = Modifier.fillMaxWidth(),
                        ) {
                            val selected = asrProfiles.firstOrNull { it.id == asrProfileId }
                            Text(selected?.let { "${it.providerLabel} · ${it.modelLabel}" } ?: "选择 Provider / Model")
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

            HorizontalDivider()

            SectionTitle("语音合成 (TTS)")
            Box(modifier = Modifier.fillMaxWidth()) {
                OutlinedButton(onClick = { ttsEngineMenuExpanded = true }, modifier = Modifier.fillMaxWidth()) {
                    Text(ttsEngines.firstOrNull { it.first == ttsEngine }?.second ?: "选择 TTS 引擎")
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
                )
                Box(modifier = Modifier.fillMaxWidth()) {
                    OutlinedButton(onClick = { minimaxVoiceMenuExpanded = true }, modifier = Modifier.fillMaxWidth()) {
                        Text(minimaxVoices.firstOrNull { it.id == minimaxVoiceId }?.let(::voiceLabel) ?: "选择 MiniMax 音色")
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
                ) {
                    Icon(Icons.Default.Refresh, contentDescription = null, modifier = Modifier.size(20.dp))
                    Spacer(modifier = Modifier.width(8.dp))
                    Text(if (isRefreshingMiniMaxVoices) "正在刷新音色..." else "从 MiniMax 刷新可用音色")
                }
            }

            HorizontalDivider()

            SectionTitle("设备信息")
            OutlinedTextField(
                value = deviceLabel,
                onValueChange = { deviceLabel = it },
                label = { Text("设备名称") },
                placeholder = { Text("例如：我的手机") },
                modifier = Modifier.fillMaxWidth(),
                singleLine = true,
            )

            Button(
                onClick = {
                    scope.launch {
                        var ok = true
                        agentForms.forEach { form ->
                            val emptyDraft = form.isDraft &&
                                form.displayName.isBlank() &&
                                form.backendId.isBlank() &&
                                form.token.isBlank()
                            if (!emptyDraft && saveForm(form, select = form.id == profilesState.selectedProfileId) == null) {
                                ok = false
                            }
                        }
                        settingsManager.updateDeviceLabel(deviceLabel)
                        settingsManager.updateGlobalAsr(asrMode, asrProfileId)
                        settingsManager.updateConfig(
                            config.copy(
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
            ) {
                Text("保存")
            }

            HelpCard()
        }
    }
}

@Composable
private fun AgentFormCard(
    form: AgentFormState,
    index: Int,
    selected: Boolean,
    status: AgentAvailabilityStatus,
    onlyPersistedProfile: Boolean,
    onChange: (AgentFormState) -> Unit,
    onSelect: () -> Unit,
    onRemove: () -> Unit,
    onPair: () -> Unit,
) {
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .border(
                width = if (selected) 1.5.dp else 0.5.dp,
                color = if (selected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.outlineVariant,
                shape = MaterialTheme.shapes.medium,
            ),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
    ) {
        Column(modifier = Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                TextButton(onClick = onSelect, contentPadding = PaddingValues(horizontal = 0.dp)) {
                    Text("Agent ${index + 1} · ${form.platform.label}")
                }
                Spacer(modifier = Modifier.weight(1f))
                Text(status.label, fontSize = 12.sp, color = MaterialTheme.colorScheme.primary)
                IconButton(onClick = onRemove) {
                    Icon(
                        Icons.Default.Delete,
                        contentDescription = if (onlyPersistedProfile) "清空 Agent" else "删除 Agent",
                        tint = MaterialTheme.colorScheme.error,
                    )
                }
            }
            OutlinedTextField(
                value = form.displayName,
                onValueChange = { onChange(form.copy(displayName = it)) },
                label = { Text("Agent 名称") },
                placeholder = { Text(form.platform.defaultDisplayName) },
                modifier = Modifier.fillMaxWidth(),
                singleLine = true,
            )
            OutlinedTextField(
                value = form.gatewayUrl,
                onValueChange = { onChange(form.copy(gatewayUrl = it)) },
                label = { Text("Gateway URL") },
                placeholder = { Text(AgentProfile.DEFAULT_GATEWAY_URL) },
                modifier = Modifier.fillMaxWidth(),
                singleLine = true,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri),
            )
            OutlinedTextField(
                value = form.backendId,
                onValueChange = { onChange(form.copy(backendId = it)) },
                label = { Text("Backend ID") },
                placeholder = { Text("bk_xxx") },
                modifier = Modifier.fillMaxWidth(),
                singleLine = true,
            )
            OutlinedTextField(
                value = form.token,
                onValueChange = { onChange(form.copy(token = it)) },
                label = { Text("Token") },
                placeholder = { Text("配对 Token") },
                modifier = Modifier.fillMaxWidth(),
                singleLine = true,
            )
            Button(onClick = onPair, enabled = form.backendId.isNotBlank(), modifier = Modifier.fillMaxWidth()) {
                Icon(Icons.Default.Link, contentDescription = null, modifier = Modifier.size(20.dp))
                Spacer(modifier = Modifier.width(8.dp))
                Text("配对")
            }
        }
    }
}

@Composable
private fun ConnectionStatusCard(
    connectionState: ConnectionState,
    pairingState: PairingState,
    pairedBackendLabel: String?,
    onUnpair: () -> Unit
) {
    val pairedStatusSuffix = if (pairedBackendLabel != null) "：$pairedBackendLabel" else ""
    val (statusColor, statusText, statusIcon) = when {
        pairingState == PairingState.PAIRED && connectionState == ConnectionState.PAIRED -> Triple(
            MaterialTheme.colorScheme.primary,
            "已配对$pairedStatusSuffix",
            Icons.Default.Link
        )
        pairingState == PairingState.PAIRED -> Triple(
            MaterialTheme.colorScheme.secondary,
            "重连中$pairedStatusSuffix",
            Icons.Default.Link
        )
        pairingState == PairingState.PENDING -> Triple(
            MaterialTheme.colorScheme.secondary,
            "正在连接 Agent$pairedStatusSuffix",
            Icons.Default.Link
        )
        connectionState == ConnectionState.CONNECTED || connectionState == ConnectionState.REGISTERED -> Triple(
            MaterialTheme.colorScheme.tertiary,
            "Router 已连接，Agent 未配对",
            Icons.Default.Link
        )
        connectionState == ConnectionState.CONNECTING -> Triple(
            MaterialTheme.colorScheme.secondary,
            "连接中...",
            Icons.Default.Link
        )
        else -> Triple(
            MaterialTheme.colorScheme.error,
            "未连接",
            Icons.Default.LinkOff
        )
    }

    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = statusColor.copy(alpha = 0.1f)
        )
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Icon(
                imageVector = statusIcon,
                contentDescription = null,
                tint = statusColor,
                modifier = Modifier.size(24.dp)
            )
            Spacer(modifier = Modifier.width(12.dp))
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = "连接状态",
                    fontSize = 12.sp,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                Spacer(modifier = Modifier.height(2.dp))
                Text(
                    text = statusText,
                    fontSize = 14.sp,
                    color = statusColor
                )
            }
            if (pairingState == PairingState.PAIRED) {
                TextButton(onClick = onUnpair) {
                    Text("取消配对", color = MaterialTheme.colorScheme.error, fontSize = 12.sp)
                }
            }
        }
    }
}

@Composable
private fun SectionTitle(text: String) {
    Text(
        text = text,
        fontSize = 13.sp,
        color = MaterialTheme.colorScheme.primary,
        modifier = Modifier.padding(top = 8.dp)
    )
}

@Composable
private fun HelpCard() {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f)
        )
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Text(
                text = "使用说明",
                fontSize = 14.sp,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Text(
                text = """
                    1. 扫描 Gateway Plugin 生成的二维码
                    2. 相同 Gateway + Backend ID 会覆盖旧 Agent
                    3. 新 Backend ID 会新增 Agent，最多 3 个
                    4. 在顶部 Agent 标签中切换会话
                """.trimIndent(),
                fontSize = 12.sp,
                color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.7f),
                lineHeight = 18.sp
            )
        }
    }
}

private data class AsrProviderProfile(
    val id: String,
    val providerLabel: String,
    val modelLabel: String,
)

private fun voiceLabel(voice: MiniMaxVoiceOption): String =
    "${voice.category} · ${voice.name}"

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
