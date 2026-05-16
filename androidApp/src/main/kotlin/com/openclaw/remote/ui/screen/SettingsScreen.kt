package com.openclaw.remote.ui.screen

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.DarkMode
import androidx.compose.material.icons.filled.LightMode
import androidx.compose.material.icons.filled.Link
import androidx.compose.material.icons.filled.LinkOff
import androidx.compose.material.icons.filled.QrCodeScanner
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.openclaw.remote.data.GatewayConfig
import com.openclaw.remote.data.SettingsManager
import com.openclaw.remote.domain.ConnectionState
import com.openclaw.remote.domain.PairingState
import com.openclaw.remote.headset.MiniMaxVoiceCatalog
import com.openclaw.remote.headset.MiniMaxVoiceOption
import kotlinx.coroutines.launch
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.net.URL

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(
    settingsManager: SettingsManager,
    connectionState: ConnectionState,
    pairingState: PairingState,
    pairedBackendLabel: String?,
    isDark: Boolean,
    onToggleTheme: () -> Unit,
    onRequestPair: (String) -> Unit,
    onUnpair: () -> Unit,
    onBack: () -> Unit,
    onNavigateToQRScanner: () -> Unit,
) {
    val scope = rememberCoroutineScope()
    val config by settingsManager.configFlow.collectAsState(initial = GatewayConfig())

    var gatewayUrl by remember(config) { mutableStateOf(config.gatewayUrl) }
    var deviceLabel by remember(config) { mutableStateOf(config.deviceLabel) }
    var manualBackendId by remember(config) { mutableStateOf(config.pairedBackendId ?: "") }
    var manualToken by remember(config) { mutableStateOf(config.token) }
    var asrMode by remember(config) { mutableStateOf(config.asrMode.ifEmpty { "router" }) }
    var asrProfileId by remember(config) { mutableStateOf(config.asrProfileId) }
    var asrProfiles by remember { mutableStateOf<List<AsrProviderProfile>>(emptyList()) }
    var asrProfileMenuExpanded by remember { mutableStateOf(false) }

    // TTS 配置
    var ttsEngine by remember(config) { mutableStateOf(config.ttsEngine.ifEmpty { "system" }) }
    var minimaxApiKey by remember(config) { mutableStateOf(config.minimaxApiKey) }
    var minimaxVoiceId by remember(config) {
        mutableStateOf(config.minimaxVoiceId.ifEmpty { MiniMaxVoiceCatalog.DEFAULT_VOICE_ID })
    }
    var ttsEngineMenuExpanded by remember { mutableStateOf(false) }
    var minimaxVoiceMenuExpanded by remember { mutableStateOf(false) }
    var fetchedMiniMaxVoices by remember { mutableStateOf<List<MiniMaxVoiceOption>>(emptyList()) }
    var isRefreshingMiniMaxVoices by remember { mutableStateOf(false) }
    val ttsEngines = listOf(
        "system" to "系统 TTS",
        "minimax" to "MiniMax"
    )
    val minimaxVoices = remember(fetchedMiniMaxVoices, minimaxVoiceId) {
        MiniMaxVoiceCatalog.buildSelectableVoices(minimaxVoiceId, fetchedMiniMaxVoices)
    }

    var showSavedSnackbar by remember { mutableStateOf(false) }
    val snackbarHostState = remember { SnackbarHostState() }

    LaunchedEffect(showSavedSnackbar) {
        if (showSavedSnackbar) {
            snackbarHostState.showSnackbar("设置已保存")
            showSavedSnackbar = false
        }
    }

    LaunchedEffect(gatewayUrl) {
        val (defaultProfileId, profiles) = fetchAsrProfiles(gatewayUrl)
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
                    IconButton(
                        onClick = {
                            scope.launch {
                                settingsManager.updateConfig(
                                    GatewayConfig(
                                        gatewayUrl = gatewayUrl,
                                        deviceId = config.deviceId,
                                        deviceLabel = deviceLabel.ifEmpty { "我的设备" },
                                        token = manualToken,
                                        pairedBackendId = config.pairedBackendId,
                                        pairedBackendLabel = config.pairedBackendLabel,
                                        asrMode = asrMode,
                                        asrProfileId = asrProfileId,
                                        ttsEngine = ttsEngine,
                                        minimaxApiKey = minimaxApiKey,
                                        minimaxVoiceId = minimaxVoiceId,
                                    )
                                )
                                showSavedSnackbar = true
                            }
                        }
                    ) {
                        Icon(Icons.Default.Check, contentDescription = "保存")
                    }
                }
            )
        },
        snackbarHost = { SnackbarHost(snackbarHostState) }
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            ConnectionStatusCard(
                connectionState = connectionState,
                pairingState = pairingState,
                pairedBackendLabel = pairedBackendLabel,
                onUnpair = onUnpair
            )

            HorizontalDivider()

            SectionTitle("扫码配对 OpenClaw")
            Text(
                text = "扫描 OpenClaw Gateway Plugin 生成的二维码，配对成功后即可开始对话",
                fontSize = 12.sp,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(bottom = 4.dp)
            )
            OutlinedButton(
                onClick = onNavigateToQRScanner,
                modifier = Modifier.fillMaxWidth()
            ) {
                Icon(
                    imageVector = Icons.Default.QrCodeScanner,
                    contentDescription = null,
                    modifier = Modifier.size(20.dp)
                )
                Spacer(modifier = Modifier.width(8.dp))
                Text(if (config.pairedBackendId == null) "扫描二维码配对" else "重新扫码配对")
            }

            HorizontalDivider()

            SectionTitle("手动配对")
            Text(
                text = "输入 Gateway 地址和 Backend ID 进行配对",
                fontSize = 12.sp,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(bottom = 4.dp)
            )

            OutlinedTextField(
                value = manualBackendId,
                onValueChange = { manualBackendId = it },
                label = { Text("Backend ID") },
                placeholder = { Text("agent backend ID") },
                modifier = Modifier.fillMaxWidth(),
                singleLine = true
            )

            OutlinedTextField(
                value = manualToken,
                onValueChange = { manualToken = it },
                label = { Text("Token") },
                placeholder = { Text("配对 Token") },
                modifier = Modifier.fillMaxWidth(),
                singleLine = true
            )

            Button(
                onClick = {
                    if (gatewayUrl.isBlank()) {
                        scope.launch {
                            snackbarHostState.showSnackbar("请先填写 Gateway 地址")
                        }
                        return@Button
                    }
                    if (manualBackendId.isBlank()) {
                        scope.launch {
                            snackbarHostState.showSnackbar("请填写 Backend ID")
                        }
                        return@Button
                    }
                    scope.launch {
                        settingsManager.updateConfig(
                            GatewayConfig(
                                gatewayUrl = gatewayUrl,
                                deviceId = config.deviceId,
                                deviceLabel = deviceLabel.ifEmpty { "我的设备" },
                                token = manualToken,
                                pairedBackendId = manualBackendId,
                                pairedBackendLabel = null,
                                asrMode = asrMode,
                                asrProfileId = asrProfileId,
                                ttsEngine = ttsEngine,
                                minimaxApiKey = minimaxApiKey,
                                minimaxVoiceId = minimaxVoiceId,
                            )
                        )
                        snackbarHostState.showSnackbar("正在连接并配对...")
                        onRequestPair(manualBackendId)
                    }
                },
                modifier = Modifier.fillMaxWidth(),
                enabled = connectionState != ConnectionState.CONNECTING
            ) {
                Icon(
                    imageVector = Icons.Default.Link,
                    contentDescription = null,
                    modifier = Modifier.size(20.dp)
                )
                Spacer(modifier = Modifier.width(8.dp))
                Text("配对")
            }

            HorizontalDivider()

            SectionTitle("Gateway 地址")
            OutlinedTextField(
                value = gatewayUrl,
                onValueChange = { gatewayUrl = it },
                label = { Text("Gateway URL") },
                placeholder = { Text("ws://gateway.example.com:8765") },
                modifier = Modifier.fillMaxWidth(),
                singleLine = true,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri)
            )

            HorizontalDivider()

            SectionTitle("语音识别")
            Text(
                text = "Router 识别使用公网托管配置；OpenClaw 后端识别使用 openclaw.json 中的 ASR 配置",
                fontSize = 12.sp,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Row(verticalAlignment = Alignment.CenterVertically) {
                RadioButton(
                    selected = asrMode != "backend",
                    onClick = { asrMode = "router" }
                )
                Text("Router 识别", modifier = Modifier.weight(1f))
                RadioButton(
                    selected = asrMode == "backend",
                    onClick = { asrMode = "backend" }
                )
                Text("OpenClaw 后端识别")
            }
            if (asrMode != "backend") {
                if (asrProfiles.isEmpty()) {
                    OutlinedTextField(
                        value = asrProfileId,
                        onValueChange = { asrProfileId = it },
                        label = { Text("Provider / Model Profile") },
                        placeholder = { Text("默认 profile 或 volcengine-bigmodel") },
                        modifier = Modifier.fillMaxWidth(),
                        singleLine = true
                    )
                } else {
                    Box(modifier = Modifier.fillMaxWidth()) {
                        OutlinedButton(
                            onClick = { asrProfileMenuExpanded = true },
                            modifier = Modifier.fillMaxWidth()
                        ) {
                            val selected = asrProfiles.firstOrNull { it.id == asrProfileId }
                            Text(selected?.let { "${it.providerLabel} · ${it.modelLabel}" } ?: "选择 Provider / Model")
                        }
                        DropdownMenu(
                            expanded = asrProfileMenuExpanded,
                            onDismissRequest = { asrProfileMenuExpanded = false }
                        ) {
                            asrProfiles.forEach { profile ->
                                DropdownMenuItem(
                                    text = { Text("${profile.providerLabel} · ${profile.modelLabel}") },
                                    onClick = {
                                        asrProfileId = profile.id
                                        asrProfileMenuExpanded = false
                                    }
                                )
                            }
                        }
                    }
                }
            }

            HorizontalDivider()

            SectionTitle("语音合成 (TTS)")
            Text(
                text = "Agent 回复的语音合成引擎",
                fontSize = 12.sp,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )

            // TTS 引擎选择
            Box(modifier = Modifier.fillMaxWidth()) {
                OutlinedButton(
                    onClick = { ttsEngineMenuExpanded = true },
                    modifier = Modifier.fillMaxWidth()
                ) {
                    val selected = ttsEngines.firstOrNull { it.first == ttsEngine }
                    Text(selected?.second ?: "选择 TTS 引擎")
                }
                DropdownMenu(
                    expanded = ttsEngineMenuExpanded,
                    onDismissRequest = { ttsEngineMenuExpanded = false }
                ) {
                    ttsEngines.forEach { (id, label) ->
                        DropdownMenuItem(
                            text = { Text(label) },
                            onClick = {
                                ttsEngine = id
                                ttsEngineMenuExpanded = false
                            }
                        )
                    }
                }
            }

            // MiniMax API Key 输入
            if (ttsEngine == "minimax") {
                OutlinedTextField(
                    value = minimaxApiKey,
                    onValueChange = { minimaxApiKey = it },
                    label = { Text("MiniMax API Key") },
                    placeholder = { Text("输入你的 MiniMax API Key") },
                    modifier = Modifier.fillMaxWidth(),
                    singleLine = true,
                    visualTransformation = PasswordVisualTransformation(),
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password)
                )

                Box(modifier = Modifier.fillMaxWidth()) {
                    OutlinedButton(
                        onClick = { minimaxVoiceMenuExpanded = true },
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Text(
                            minimaxVoices.firstOrNull { it.id == minimaxVoiceId }?.let(::voiceLabel)
                                ?: "选择 MiniMax 音色"
                        )
                    }
                    DropdownMenu(
                        expanded = minimaxVoiceMenuExpanded,
                        onDismissRequest = { minimaxVoiceMenuExpanded = false }
                    ) {
                        minimaxVoices.forEach { voice ->
                            DropdownMenuItem(
                                text = { Text(voiceLabel(voice)) },
                                onClick = {
                                    minimaxVoiceId = voice.id
                                    minimaxVoiceMenuExpanded = false
                                }
                            )
                        }
                    }
                }

                OutlinedButton(
                    onClick = {
                        scope.launch {
                            if (minimaxApiKey.isBlank()) {
                                snackbarHostState.showSnackbar("请先填写 MiniMax API Key")
                                return@launch
                            }
                            isRefreshingMiniMaxVoices = true
                            runCatching {
                                MiniMaxVoiceCatalog.fetchAvailableVoices(minimaxApiKey)
                            }.onSuccess { voices ->
                                fetchedMiniMaxVoices = voices
                                snackbarHostState.showSnackbar("已刷新 ${voices.size} 个 MiniMax 音色")
                            }.onFailure { error ->
                                snackbarHostState.showSnackbar("刷新音色失败：${error.message ?: "unknown"}")
                            }
                            isRefreshingMiniMaxVoices = false
                        }
                    },
                    modifier = Modifier.fillMaxWidth(),
                    enabled = !isRefreshingMiniMaxVoices
                ) {
                    Icon(
                        imageVector = Icons.Default.Refresh,
                        contentDescription = null,
                        modifier = Modifier.size(20.dp)
                    )
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
                singleLine = true
            )

            Button(
                onClick = {
                    scope.launch {
                        settingsManager.updateConfig(
                            GatewayConfig(
                                gatewayUrl = gatewayUrl,
                                deviceId = config.deviceId,
                                deviceLabel = deviceLabel.ifEmpty { "我的设备" },
                                token = manualToken,
                                pairedBackendId = manualBackendId.ifEmpty { null },
                                pairedBackendLabel = config.pairedBackendLabel,
                                asrMode = asrMode,
                                asrProfileId = asrProfileId,
                                ttsEngine = ttsEngine,
                                minimaxApiKey = minimaxApiKey,
                                minimaxVoiceId = minimaxVoiceId,
                            )
                        )
                        showSavedSnackbar = true
                    }
                },
                modifier = Modifier.fillMaxWidth()
            ) {
                Text("保存")
            }

            Spacer(modifier = Modifier.height(16.dp))
            HelpCard()
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
    val (statusColor, statusText, statusIcon) = when {
        pairingState == PairingState.PAIRED -> Triple(
            MaterialTheme.colorScheme.primary,
            "已配对${if (pairedBackendLabel != null) "：$pairedBackendLabel" else ""}",
            Icons.Default.Link
        )
        pairingState == PairingState.PENDING -> Triple(
            MaterialTheme.colorScheme.secondary,
            "正在连接 Agent${if (pairedBackendLabel != null) "：$pairedBackendLabel" else ""}",
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
                    1. 在 OpenClaw 侧启动 Gateway Plugin
                    2. Plugin 会生成配对二维码
                    3. 点击「扫描二维码配对」
                    4. 扫描后自动连接并配对
                    5. 配对成功后即可开始对话
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
