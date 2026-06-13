package com.openclaw.remote.ui.screen

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.filled.Error
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.Password
import androidx.compose.material.icons.filled.Sms
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
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
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.openclaw.remote.auth.AuthSessionResult
import com.openclaw.remote.auth.GatewayAuthClient
import com.openclaw.remote.data.GatewayConfig
import com.openclaw.remote.ui.theme.MochiColors
import com.openclaw.remote.ui.theme.MochiTheme
import kotlinx.coroutines.launch

@Composable
fun AuthScreen(
    config: GatewayConfig,
    notice: String?,
    onAuthenticated: (AuthSuccessPayload) -> Unit,
    onNoticeShown: () -> Unit = {},
) {
    val colors = MochiTheme.colors
    val scope = rememberCoroutineScope()
    val snackbarHostState = remember { SnackbarHostState() }
    val authClient = remember { GatewayAuthClient() }

    val initialState = remember(config.gatewayUrl, config.deviceLabel, config.lastLoginMode, config.lastPhoneNumber) {
        initialAuthUiState(
            gatewayUrl = config.gatewayUrl,
            deviceLabel = config.deviceLabel,
            lastLoginMode = config.lastLoginMode,
            lastPhoneNumber = config.lastPhoneNumber,
        )
    }
    var authMode by remember { mutableStateOf(initialState.mode) }
    var loginMode by remember { mutableStateOf(initialState.loginMode) }
    var gatewayUrl by remember(initialState.gatewayUrl) { mutableStateOf(initialState.gatewayUrl) }
    var phoneNumber by remember(initialState.phoneNumber) { mutableStateOf(initialState.phoneNumber) }
    var smsCode by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    var confirmPassword by remember { mutableStateOf("") }
    var terminalLabel by remember(initialState.terminalLabel) { mutableStateOf(initialState.terminalLabel) }
    var isBusy by remember { mutableStateOf(false) }
    var statusMessage by remember { mutableStateOf<String?>(null) }
    var acceptedTerms by remember { mutableStateOf(false) }

    suspend fun showMessage(message: String) {
        statusMessage = message
        snackbarHostState.showSnackbar(message)
    }

    fun normalizedGateway(): String =
        gatewayUrl.normalizedGatewayUrl()

    fun canSubmitPassword(): Boolean =
        phoneNumber.trim().isNotBlank() && password.length >= 8

    fun canSubmitWithCode(): Boolean =
        phoneNumber.trim().isNotBlank() && smsCode.trim().isNotBlank()

    LaunchedEffect(notice) {
        val message = notice?.takeIf { it.isNotBlank() } ?: return@LaunchedEffect
        showMessage(message)
        onNoticeShown()
    }

    DisposableEffect(Unit) {
        onDispose { authClient.close() }
    }

    Scaffold(
        containerColor = colors.background,
        snackbarHost = { SnackbarHost(snackbarHostState) },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .background(colors.background)
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp, vertical = 28.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            AuthHeader(colors, authMode)

            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(colors.surface, RoundedCornerShape(8.dp))
                    .border(1.dp, colors.divider, RoundedCornerShape(8.dp))
                    .padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp),
            ) {
            when (authMode) {
                AuthModeSpec.LOGIN -> {
                    AuthPhoneField(phoneNumber, { phoneNumber = it }, colors)
                    if (loginMode == AuthLoginModeSpec.PASSWORD) {
                        AuthPasswordField("密码", password, { password = it }, colors)
                        Button(
                            onClick = {
                                scope.launch {
                                    if (!canSubmitPassword()) {
                                        showMessage("请填写手机号和不少于 8 位的密码")
                                        return@launch
                                    }
                                    isBusy = true
                                    runCatching {
                                        authClient.loginPassword(
                                            gatewayUrl = normalizedGateway(),
                                            phoneNumber = phoneNumber,
                                            password = password,
                                            terminalLabel = terminalLabel.normalizedTerminalLabel(),
                                        )
                                    }.onSuccess {
                                        onAuthenticated(
                                            buildAuthSuccessPayload(
                                                session = it,
                                                gatewayUrl = gatewayUrl,
                                                terminalLabel = terminalLabel,
                                                loginMode = AuthLoginModeSpec.PASSWORD,
                                                phoneNumber = phoneNumber,
                                            )
                                        )
                                    }.onFailure {
                                        showMessage("登录失败：${it.message ?: "unknown"}")
                                    }
                                    isBusy = false
                                }
                            },
                            enabled = !isBusy,
                            modifier = Modifier
                                .fillMaxWidth()
                                .heightIn(min = 48.dp),
                            shape = RoundedCornerShape(8.dp),
                            colors = ButtonDefaults.buttonColors(colors.primary, colors.onPrimary),
                        ) {
                            Icon(Icons.Default.Lock, contentDescription = null)
                            Text("密码登录", modifier = Modifier.padding(start = 8.dp))
                        }
                    } else {
                        SmsCodeRow(
                            smsCode = smsCode,
                            onSmsCodeChange = { smsCode = it },
                            colors = colors,
                            isBusy = isBusy,
                            onRequestCode = {
                                scope.launch {
                                    if (phoneNumber.isBlank()) {
                                        showMessage("请先填写手机号")
                                        return@launch
                                    }
                                    isBusy = true
                                    runCatching {
                                        authClient.requestSms(
                                            gatewayUrl = normalizedGateway(),
                                            phoneNumber = phoneNumber,
                                        )
                                    }.onSuccess {
                                        showMessage("验证码已发送，${it.retryAfterSeconds} 秒后可重试")
                                    }.onFailure {
                                        showMessage("发送验证码失败：${it.message ?: "unknown"}")
                                    }
                                    isBusy = false
                                }
                            },
                        )
                        Button(
                            onClick = {
                                scope.launch {
                                    if (!canSubmitWithCode()) {
                                        showMessage("请填写手机号和验证码")
                                        return@launch
                                    }
                                    isBusy = true
                                    runCatching {
                                        authClient.verifySms(
                                            gatewayUrl = normalizedGateway(),
                                            phoneNumber = phoneNumber,
                                            code = smsCode,
                                            terminalLabel = terminalLabel.normalizedTerminalLabel(),
                                        )
                                    }.onSuccess {
                                        onAuthenticated(
                                            buildAuthSuccessPayload(
                                                session = it,
                                                gatewayUrl = gatewayUrl,
                                                terminalLabel = terminalLabel,
                                                loginMode = AuthLoginModeSpec.SMS,
                                                phoneNumber = phoneNumber,
                                            )
                                        )
                                    }.onFailure {
                                        showMessage("登录失败：${it.message ?: "unknown"}")
                                    }
                                    isBusy = false
                                }
                            },
                            enabled = !isBusy,
                            modifier = Modifier
                                .fillMaxWidth()
                                .heightIn(min = 48.dp),
                            shape = RoundedCornerShape(8.dp),
                            colors = ButtonDefaults.buttonColors(colors.primary, colors.onPrimary),
                        ) {
                            Icon(Icons.Default.Sms, contentDescription = null)
                            Text("验证码登录", modifier = Modifier.padding(start = 8.dp))
                        }
                    }
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        TextButton(
                            onClick = {
                                if (loginMode == AuthLoginModeSpec.PASSWORD) {
                                    loginMode = AuthLoginModeSpec.SMS
                                    password = ""
                                } else {
                                    loginMode = AuthLoginModeSpec.PASSWORD
                                    smsCode = ""
                                }
                            },
                        ) {
                            Text(
                                if (loginMode == AuthLoginModeSpec.PASSWORD) "验证码登录" else "密码登录",
                                color = colors.primary,
                            )
                        }
                        androidx.compose.foundation.layout.Spacer(Modifier.weight(1f))
                        TextButton(
                            onClick = {
                                authMode = AuthModeSpec.FORGOT
                                smsCode = ""
                                password = ""
                                confirmPassword = ""
                                acceptedTerms = false
                            },
                        ) {
                            Text("忘记密码", color = colors.textSecondary)
                        }
                    }
                    HorizontalDivider(color = colors.divider)
                    TextButton(
                        onClick = {
                            authMode = AuthModeSpec.REGISTER
                            phoneNumber = ""
                            password = ""
                            smsCode = ""
                            confirmPassword = ""
                            acceptedTerms = false
                        },
                        modifier = Modifier.align(Alignment.CenterHorizontally),
                    ) {
                        Text("还没有账号？立即注册", color = colors.primary)
                    }
                }

                AuthModeSpec.REGISTER -> {
                    Text("填写以下信息完成注册", color = colors.textSecondary, fontSize = 14.sp)
                    AuthPhoneField(phoneNumber, { phoneNumber = it }, colors)
                    AuthPasswordField("设置密码", password, { password = it }, colors)
                    SmsCodeRow(
                        smsCode = smsCode,
                        onSmsCodeChange = { smsCode = it },
                        colors = colors,
                        isBusy = isBusy,
                        onRequestCode = {
                            scope.launch {
                                if (phoneNumber.isBlank()) {
                                    showMessage("请先填写手机号")
                                    return@launch
                                }
                                isBusy = true
                                runCatching {
                                    authClient.requestSms(
                                        gatewayUrl = normalizedGateway(),
                                        phoneNumber = phoneNumber,
                                        purpose = "register",
                                    )
                                }.onSuccess {
                                    showMessage("验证码已发送，${it.retryAfterSeconds} 秒后可重试")
                                }.onFailure {
                                    showMessage("发送验证码失败：${it.message ?: "unknown"}")
                                }
                                isBusy = false
                            }
                        },
                    )
                    TermsAgreementRow(
                        accepted = acceptedTerms,
                        colors = colors,
                        onToggle = { acceptedTerms = !acceptedTerms },
                    )
                    Button(
                        onClick = {
                            scope.launch {
                                if (!acceptedTerms) {
                                    showMessage("请先阅读并同意用户协议和隐私政策")
                                    return@launch
                                }
                                if (!canSubmitWithCode() || password.length < 8) {
                                    showMessage("请检查手机号、验证码和密码（至少8位）")
                                    return@launch
                                }
                                isBusy = true
                                runCatching {
                                    authClient.registerPassword(
                                        gatewayUrl = normalizedGateway(),
                                        phoneNumber = phoneNumber,
                                        code = smsCode,
                                        password = password,
                                        terminalLabel = terminalLabel.normalizedTerminalLabel(),
                                    )
                                }.onSuccess {
                                    onAuthenticated(
                                        buildAuthSuccessPayload(
                                            session = it,
                                            gatewayUrl = gatewayUrl,
                                            terminalLabel = terminalLabel,
                                            loginMode = AuthLoginModeSpec.PASSWORD,
                                            phoneNumber = phoneNumber,
                                        )
                                    )
                                }.onFailure {
                                    showMessage("注册失败：${it.message ?: "unknown"}")
                                }
                                isBusy = false
                            }
                        },
                        enabled = !isBusy && acceptedTerms,
                        modifier = Modifier
                            .fillMaxWidth()
                            .heightIn(min = 48.dp),
                        shape = RoundedCornerShape(8.dp),
                        colors = ButtonDefaults.buttonColors(colors.primary, colors.onPrimary),
                    ) {
                        Icon(Icons.Default.Password, contentDescription = null)
                        Text("注册", modifier = Modifier.padding(start = 8.dp))
                    }
                    HorizontalDivider(color = colors.divider)
                    TextButton(
                        onClick = {
                            authMode = AuthModeSpec.LOGIN
                            smsCode = ""
                            confirmPassword = ""
                            acceptedTerms = false
                        },
                        modifier = Modifier.align(Alignment.CenterHorizontally),
                    ) {
                        Text("已有账号？直接登录", color = colors.primary)
                    }
                }

                AuthModeSpec.FORGOT -> {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(10.dp),
                    ) {
                        IconButton(
                            onClick = { authMode = AuthModeSpec.LOGIN },
                            modifier = Modifier
                                .size(32.dp)
                                .background(colors.inputBg, RoundedCornerShape(8.dp))
                                .border(1.dp, colors.inputBorder, RoundedCornerShape(8.dp)),
                        ) {
                            Icon(
                                Icons.AutoMirrored.Filled.ArrowBack,
                                contentDescription = null,
                                tint = colors.textPrimary,
                                modifier = Modifier.size(16.dp),
                            )
                        }
                        Text("找回密码", color = colors.textPrimary, fontSize = 18.sp, fontWeight = FontWeight.Medium)
                    }
                    AuthPhoneField(phoneNumber, { phoneNumber = it }, colors)
                    SmsCodeRow(
                        smsCode = smsCode,
                        onSmsCodeChange = { smsCode = it },
                        colors = colors,
                        isBusy = isBusy,
                        onRequestCode = {
                            scope.launch {
                                if (phoneNumber.isBlank()) {
                                    showMessage("请先填写手机号")
                                    return@launch
                                }
                                isBusy = true
                                runCatching {
                                    authClient.requestPasswordReset(
                                        gatewayUrl = normalizedGateway(),
                                        phoneNumber = phoneNumber,
                                    )
                                }.onSuccess {
                                    showMessage("验证码已发送，${it.retryAfterSeconds} 秒后可重试")
                                }.onFailure {
                                    showMessage("发送验证码失败：${it.message ?: "unknown"}")
                                }
                                isBusy = false
                            }
                        },
                    )
                    AuthPasswordField("新密码", password, { password = it }, colors)
                    AuthPasswordField("确认新密码", confirmPassword, { confirmPassword = it }, colors)
                    Button(
                        onClick = {
                            scope.launch {
                                if (!canSubmitWithCode() || password.length < 8 || password != confirmPassword) {
                                    showMessage("请检查手机号、验证码和两次密码")
                                    return@launch
                                }
                                isBusy = true
                                runCatching {
                                    authClient.resetPassword(
                                        gatewayUrl = normalizedGateway(),
                                        phoneNumber = phoneNumber,
                                        code = smsCode,
                                        password = password,
                                    )
                                }.onSuccess {
                                    onAuthenticated(
                                        buildAuthSuccessPayload(
                                            session = it,
                                            gatewayUrl = gatewayUrl,
                                            terminalLabel = terminalLabel,
                                            loginMode = AuthLoginModeSpec.PASSWORD,
                                            phoneNumber = phoneNumber,
                                        )
                                    )
                                }.onFailure {
                                    showMessage("重置失败：${it.message ?: "unknown"}")
                                }
                                isBusy = false
                            }
                        },
                        enabled = !isBusy,
                        modifier = Modifier
                            .fillMaxWidth()
                            .heightIn(min = 48.dp),
                        shape = RoundedCornerShape(8.dp),
                        colors = ButtonDefaults.buttonColors(colors.primary, colors.onPrimary),
                    ) {
                        Icon(Icons.Default.Password, contentDescription = null)
                        Text("重置并登录", modifier = Modifier.padding(start = 8.dp))
                    }
                }
            }
            }

            statusMessage?.let { message ->
                AuthNoticeBanner(message = message, colors = colors)
            }
        }
    }
}

@Composable
private fun AuthHeader(colors: MochiColors, authMode: AuthModeSpec) {
    val subtitle = when (authMode) {
        AuthModeSpec.LOGIN -> "欢迎回来"
        AuthModeSpec.REGISTER -> "注册新账号"
        AuthModeSpec.FORGOT -> "找回密码"
    }
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Icon(
            Icons.Default.Lock,
            contentDescription = null,
            tint = colors.primary,
            modifier = Modifier
                .size(46.dp)
                .background(colors.primary.copy(alpha = 0.12f), RoundedCornerShape(8.dp))
                .padding(12.dp),
        )

        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(
                text = "OpenClaw Remote",
                color = colors.textPrimary,
                fontSize = 26.sp,
                fontWeight = FontWeight.SemiBold,
            )
            Text(
                text = subtitle,
                color = colors.textSecondary,
                fontSize = 14.sp,
            )
        }
    }
}

@Composable
private fun TermsAgreementRow(
    accepted: Boolean,
    colors: MochiColors,
    onToggle: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onToggle),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Text(
            text = if (accepted) "☑" else "☐",
            color = if (accepted) colors.primary else colors.textSecondary,
            fontSize = 16.sp,
        )
        Text("我已阅读并同意", color = colors.textSecondary, fontSize = 13.sp)
        Text("《用户协议》", color = colors.primary, fontSize = 13.sp, fontWeight = FontWeight.Medium)
        Text("和", color = colors.textSecondary, fontSize = 13.sp)
        Text("《隐私政策》", color = colors.primary, fontSize = 13.sp, fontWeight = FontWeight.Medium)
    }
}

@Composable
private fun ConnectionFields(
    gatewayUrl: String,
    onGatewayUrlChange: (String) -> Unit,
    terminalLabel: String,
    onTerminalLabelChange: (String) -> Unit,
    colors: MochiColors,
) {
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text(
            text = "连接入口",
            color = colors.textPrimary,
            fontSize = 13.sp,
            fontWeight = FontWeight.Medium,
        )
        OutlinedTextField(
            value = gatewayUrl,
            onValueChange = onGatewayUrlChange,
            label = { Text("Gateway") },
            modifier = Modifier.fillMaxWidth(),
            singleLine = true,
            shape = RoundedCornerShape(8.dp),
            colors = authTextFieldColors(colors),
        )
        OutlinedTextField(
            value = terminalLabel,
            onValueChange = onTerminalLabelChange,
            label = { Text("终端名称") },
            modifier = Modifier.fillMaxWidth(),
            singleLine = true,
            shape = RoundedCornerShape(8.dp),
            colors = authTextFieldColors(colors),
        )
    }
}

@Composable
private fun AuthNoticeBanner(message: String, colors: MochiColors) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(colors.recordingRed.copy(alpha = 0.10f), RoundedCornerShape(8.dp))
            .border(1.dp, colors.recordingRed.copy(alpha = 0.18f), RoundedCornerShape(8.dp))
            .padding(horizontal = 12.dp, vertical = 10.dp),
        verticalAlignment = Alignment.Top,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Icon(
            Icons.Default.Error,
            contentDescription = null,
            tint = colors.recordingRed,
            modifier = Modifier.size(15.dp),
        )
        Text(
            text = message,
            color = colors.textPrimary,
            fontSize = 13.sp,
        )
    }
}

@Composable
private fun AuthPhoneField(value: String, onValueChange: (String) -> Unit, colors: MochiColors) {
    OutlinedTextField(
        value = value,
        onValueChange = onValueChange,
        label = { Text("手机号") },
        placeholder = { Text("+8613800138000") },
        modifier = Modifier.fillMaxWidth(),
        singleLine = true,
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Phone),
        shape = RoundedCornerShape(8.dp),
        colors = authTextFieldColors(colors),
    )
}

@Composable
private fun AuthPasswordField(
    label: String,
    value: String,
    onValueChange: (String) -> Unit,
    colors: MochiColors,
) {
    OutlinedTextField(
        value = value,
        onValueChange = onValueChange,
        label = { Text(label) },
        modifier = Modifier.fillMaxWidth(),
        singleLine = true,
        visualTransformation = PasswordVisualTransformation(),
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
        shape = RoundedCornerShape(8.dp),
        colors = authTextFieldColors(colors),
    )
}

@Composable
private fun SmsCodeRow(
    smsCode: String,
    onSmsCodeChange: (String) -> Unit,
    colors: MochiColors,
    isBusy: Boolean,
    onRequestCode: () -> Unit,
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        OutlinedTextField(
            value = smsCode,
            onValueChange = onSmsCodeChange,
            label = { Text("验证码") },
            modifier = Modifier.weight(1f),
            singleLine = true,
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
            shape = RoundedCornerShape(8.dp),
            colors = authTextFieldColors(colors),
        )
        OutlinedButton(
            onClick = onRequestCode,
            enabled = !isBusy,
            modifier = Modifier.height(56.dp),
            shape = RoundedCornerShape(8.dp),
            contentPadding = PaddingValues(horizontal = 14.dp),
        ) {
            Icon(
                Icons.AutoMirrored.Filled.Send,
                contentDescription = null,
                modifier = Modifier.size(14.dp),
            )
            Text("发送", modifier = Modifier.padding(start = 6.dp))
        }
    }
}

@Composable
private fun AuthSegmentedControl(
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
            .background(colors.secondary, RoundedCornerShape(8.dp))
            .padding(3.dp),
        horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        AuthSegmentButton(
            text = leftText,
            selected = leftSelected,
            colors = colors,
            onClick = onSelectLeft,
            modifier = Modifier.weight(1f),
        )
        AuthSegmentButton(
            text = rightText,
            selected = !leftSelected,
            colors = colors,
            onClick = onSelectRight,
            modifier = Modifier.weight(1f),
        )
    }
}

@Composable
private fun AuthSegmentButton(
    text: String,
    selected: Boolean,
    colors: MochiColors,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val container = if (selected) colors.surface else colors.secondary
    val content = if (selected) colors.textPrimary else colors.textSecondary
    TextButton(
        onClick = onClick,
        modifier = modifier.background(container, RoundedCornerShape(6.dp)),
        contentPadding = PaddingValues(vertical = 9.dp),
    ) {
        Text(text = text, color = content, fontWeight = if (selected) FontWeight.Medium else FontWeight.Normal)
    }
}

@Composable
private fun authTextFieldColors(colors: MochiColors) = OutlinedTextFieldDefaults.colors(
    focusedTextColor = colors.inputText,
    unfocusedTextColor = colors.inputText,
    focusedContainerColor = colors.inputBg,
    unfocusedContainerColor = colors.inputBg,
    focusedBorderColor = colors.primary,
    unfocusedBorderColor = colors.inputBorder,
    focusedLabelColor = colors.primary,
    unfocusedLabelColor = colors.textSecondary,
    cursorColor = colors.primary,
)
