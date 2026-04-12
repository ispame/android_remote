package com.openclaw.remote.ui.screen

import android.net.Uri
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Link
import androidx.compose.material.icons.filled.LinkOff
import androidx.compose.material.icons.filled.QrCodeScanner
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.openclaw.remote.*
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(
    settingsManager: SettingsManager,
    connectionState: ConnectionState,
    pairingState: PairingState,
    pairedBackendLabel: String?,
    onRequestPair: (String) -> Unit,
    onUnpair: () -> Unit,
    onBack: () -> Unit
) {
    val scope = rememberCoroutineScope()
    val config by settingsManager.configFlow.collectAsState(initial = GatewayConfig())

    var gatewayUrl by remember(config) { mutableStateOf(config.gatewayUrl) }
    var deviceLabel by remember(config) { mutableStateOf(config.deviceLabel) }
    var manualBackendId by remember(config) { mutableStateOf(config.pairedBackendId ?: "") }
    var manualToken by remember(config) { mutableStateOf(config.token) }
    var showQRScanner by remember { mutableStateOf(false) }
    var pendingPairBackendId by remember { mutableStateOf<String?>(null) }
    var showSavedSnackbar by remember { mutableStateOf(false) }
    val snackbarHostState = remember { SnackbarHostState() }

    LaunchedEffect(showSavedSnackbar) {
        if (showSavedSnackbar) {
            snackbarHostState.showSnackbar("设置已保存")
            showSavedSnackbar = false
        }
    }

    // QR Scanner overlay
    if (showQRScanner) {
        QRScannerScreen(
            onQRCodeScanned = { scannedText ->
                showQRScanner = false
                parseQRPack(scannedText) { result ->
                    when (result) {
                        is QRParseResult.Success -> {
                            gatewayUrl = result.gatewayUrl
                            manualToken = result.token
                            pendingPairBackendId = result.backendId
                            scope.launch {
                                snackbarHostState.showSnackbar("已解析二维码，正在连接并配对...")
                                // Auto-save and trigger pair
                                settingsManager.updateConfig(
                                    GatewayConfig(
                                        gatewayUrl = result.gatewayUrl,
                                        deviceId = config.deviceId,
                                        deviceLabel = deviceLabel.ifEmpty { "我的手机" },
                                        token = result.token,
                                        pairedBackendId = null,
                                        pairedBackendLabel = null
                                    )
                                )
                                // Delay slightly to ensure connection is established
                                kotlinx.coroutines.delay(1000)
                                onRequestPair(result.backendId)
                            }
                        }
                        is QRParseResult.Error -> {
                            scope.launch {
                                snackbarHostState.showSnackbar("二维码解析失败: ${result.message}")
                            }
                        }
                    }
                }
            },
            onClose = { showQRScanner = false }
        )
        return
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
                    IconButton(
                        onClick = {
                            scope.launch {
                                settingsManager.updateConfig(
                                    GatewayConfig(
                                        gatewayUrl = gatewayUrl,
                                        deviceId = config.deviceId,
                                        deviceLabel = deviceLabel.ifEmpty { "我的手机" },
                                        token = manualToken,
                                        pairedBackendId = config.pairedBackendId,
                                        pairedBackendLabel = config.pairedBackendLabel
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
            // ===== 连接状态卡片 =====
            ConnectionStatusCard(
                connectionState = connectionState,
                pairingState = pairingState,
                pairedBackendLabel = pairedBackendLabel,
                onUnpair = onUnpair
            )

            HorizontalDivider()

            // ===== 扫码配对 =====
            SectionTitle("扫码配对 OpenClaw")
            Text(
                text = "扫描 OpenClaw Gateway Plugin 生成的二维码，配对成功后即可开始对话",
                fontSize = 12.sp,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(bottom = 4.dp)
            )
            OutlinedButton(
                onClick = { showQRScanner = true },
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

            // ===== 手动配对 =====
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
                                deviceLabel = deviceLabel.ifEmpty { "我的手机" },
                                token = manualToken,
                                pairedBackendId = null,
                                pairedBackendLabel = null
                            )
                        )
                        snackbarHostState.showSnackbar("正在连接并配对...")
                        kotlinx.coroutines.delay(500)
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

            // ===== 服务器配置 =====
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

            // ===== 设备信息 =====
            SectionTitle("设备信息")
            OutlinedTextField(
                value = deviceLabel,
                onValueChange = { deviceLabel = it },
                label = { Text("设备名称") },
                placeholder = { Text("例如：我的手机") },
                modifier = Modifier.fillMaxWidth(),
                singleLine = true
            )

            // ===== 保存按钮 =====
            Button(
                onClick = {
                    scope.launch {
                        settingsManager.updateConfig(
                            GatewayConfig(
                                gatewayUrl = gatewayUrl,
                                deviceId = config.deviceId,
                                deviceLabel = deviceLabel.ifEmpty { "我的手机" },
                                token = manualToken,
                                pairedBackendId = config.pairedBackendId,
                                pairedBackendLabel = config.pairedBackendLabel
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

// ===== 连接状态卡片 =====
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
        connectionState == ConnectionState.CONNECTED || connectionState == ConnectionState.REGISTERED -> Triple(
            MaterialTheme.colorScheme.tertiary,
            "连接成功，请扫码配对",
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

// ===== QR 解析结果 =====
sealed class QRParseResult {
    data class Success(val gatewayUrl: String, val backendId: String, val token: String) : QRParseResult()
    data class Error(val message: String) : QRParseResult()
}

/**
 * 解析 OpenClaw Gateway Plugin 生成的二维码。
 * 支持格式：
 * - openclaw://connect?gateway=ws://...&agentId=...&token=...
 * - {"gateway":"ws://...","agentId":"...","token":"..."}
 */
fun parseQRPack(
    scannedText: String,
    onResult: (QRParseResult) -> Unit
) {
    try {
        // Format 1: openclaw://connect?gateway=...&agentId=...&token=...
        if (scannedText.startsWith("openclaw://connect")) {
            val uri = Uri.parse(scannedText)
            val gateway = uri.getQueryParameter("gateway") ?: ""
            val agentId = uri.getQueryParameter("agentId") ?: ""
            val token = uri.getQueryParameter("token") ?: ""
            if (gateway.isEmpty() || agentId.isEmpty()) {
                onResult(QRParseResult.Error("缺少 gateway 或 agentId 参数"))
                return
            }
            onResult(QRParseResult.Success(gateway, agentId, token))
            return
        }

        // Format 2: JSON {"gateway":"...", "agentId":"...", "token":"..."}
        if (scannedText.trimStart().startsWith("{")) {
            val json = org.json.JSONObject(scannedText)
            val gateway = json.optString("gateway", "")
            val agentId = json.optString("agentId", json.optString("backendId", ""))
            val token = json.optString("token", "")
            if (gateway.isEmpty() || agentId.isEmpty()) {
                onResult(QRParseResult.Error("缺少 gateway 或 agentId 字段"))
                return
            }
            onResult(QRParseResult.Success(gateway, agentId, token))
            return
        }

        onResult(QRParseResult.Error("不支持的二维码格式"))
    } catch (e: Exception) {
        onResult(QRParseResult.Error("解析失败: ${e.message}"))
    }
}

// ===== UI 组件 =====
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
