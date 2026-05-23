package com.openclaw.remote.ui.screen

import androidx.compose.foundation.background
import androidx.compose.foundation.border
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
import com.openclaw.remote.data.AgentProfile
import com.openclaw.remote.data.GatewayConfig
import com.openclaw.remote.ui.theme.MochiColors
import com.openclaw.remote.ui.theme.MochiTheme
import kotlinx.coroutines.launch

private enum class AuthMode { Login, Register, ForgotPassword }
private enum class LoginMode { Password, Sms }

@Composable
fun AuthScreen(
    config: GatewayConfig,
    notice: String?,
    onAuthenticated: (AuthSessionResult, String) -> Unit,
    onNoticeShown: () -> Unit = {},
) {
    val colors = MochiTheme.colors
    val scope = rememberCoroutineScope()
    val snackbarHostState = remember { SnackbarHostState() }
    val authClient = remember { GatewayAuthClient() }

    var authMode by remember { mutableStateOf(AuthMode.Login) }
    var loginMode by remember { mutableStateOf(LoginMode.Password) }
    var gatewayUrl by remember(config.gatewayUrl) {
        mutableStateOf(config.gatewayUrl.ifBlank { AgentProfile.DEFAULT_GATEWAY_URL })
    }
    var phoneNumber by remember { mutableStateOf("") }
    var smsCode by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    var confirmPassword by remember { mutableStateOf("") }
    var terminalLabel by remember(config.deviceLabel) {
        mutableStateOf(config.deviceLabel.ifBlank { "我的设备" })
    }
    var isBusy by remember { mutableStateOf(false) }
    var statusMessage by remember { mutableStateOf<String?>(null) }

    suspend fun showMessage(message: String) {
        statusMessage = message
        snackbarHostState.showSnackbar(message)
    }

    fun normalizedGateway(): String =
        gatewayUrl.trim().ifEmpty { AgentProfile.DEFAULT_GATEWAY_URL }

    fun canSubmitPassword(): Boolean =
        phoneNumber.isNotBlank() && password.length >= 8

    fun canSubmitWithCode(): Boolean =
        phoneNumber.isNotBlank() && smsCode.isNotBlank()

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
            AuthHeader(colors)

            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(colors.surface, RoundedCornerShape(8.dp))
                    .border(1.dp, colors.divider, RoundedCornerShape(8.dp))
                    .padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp),
            ) {
                if (authMode != AuthMode.ForgotPassword) {
                    AuthSegmentedControl(
                        leftText = "登录",
                        rightText = "注册",
                        leftSelected = authMode != AuthMode.Register,
                        colors = colors,
                        onSelectLeft = { authMode = AuthMode.Login },
                        onSelectRight = { authMode = AuthMode.Register },
                    )

                    HorizontalDivider(color = colors.divider)
                }

            when (authMode) {
                AuthMode.Login -> {
                    AuthSegmentedControl(
                        leftText = "密码",
                        rightText = "验证码",
                        leftSelected = loginMode == LoginMode.Password,
                        colors = colors,
                        onSelectLeft = { loginMode = LoginMode.Password },
                        onSelectRight = { loginMode = LoginMode.Sms },
                    )
                    AuthPhoneField(phoneNumber, { phoneNumber = it }, colors)
                    if (loginMode == LoginMode.Password) {
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
                                            terminalLabel = terminalLabel.ifBlank { "我的设备" },
                                        )
                                    }.onSuccess {
                                        onAuthenticated(it, normalizedGateway())
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
                                            terminalLabel = terminalLabel.ifBlank { "我的设备" },
                                        )
                                    }.onSuccess {
                                        onAuthenticated(it, normalizedGateway())
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
                    TextButton(
                        onClick = {
                            authMode = AuthMode.ForgotPassword
                            smsCode = ""
                            password = ""
                            confirmPassword = ""
                        },
                        modifier = Modifier.align(Alignment.End),
                    ) {
                        Text("忘记密码", color = colors.primary)
                    }
                }

                AuthMode.Register -> {
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
                    AuthPasswordField("设置密码", password, { password = it }, colors)
                    AuthPasswordField("确认密码", confirmPassword, { confirmPassword = it }, colors)
                    Button(
                        onClick = {
                            scope.launch {
                                if (!canSubmitWithCode() || password.length < 8 || password != confirmPassword) {
                                    showMessage("请检查手机号、验证码和两次密码")
                                    return@launch
                                }
                                isBusy = true
                                runCatching {
                                    authClient.registerPassword(
                                        gatewayUrl = normalizedGateway(),
                                        phoneNumber = phoneNumber,
                                        code = smsCode,
                                        password = password,
                                        terminalLabel = terminalLabel.ifBlank { "我的设备" },
                                    )
                                }.onSuccess {
                                    onAuthenticated(it, normalizedGateway())
                                }.onFailure {
                                    showMessage("注册失败：${it.message ?: "unknown"}")
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
                        Text("注册并登录", modifier = Modifier.padding(start = 8.dp))
                    }
                }

                AuthMode.ForgotPassword -> {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(10.dp),
                    ) {
                        IconButton(
                            onClick = { authMode = AuthMode.Login },
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
                                    onAuthenticated(it, normalizedGateway())
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

                HorizontalDivider(color = colors.divider)

                ConnectionFields(
                    gatewayUrl = gatewayUrl,
                    onGatewayUrlChange = { gatewayUrl = it },
                    terminalLabel = terminalLabel,
                    onTerminalLabelChange = { terminalLabel = it },
                    colors = colors,
                )
            }

            statusMessage?.let { message ->
                AuthNoticeBanner(message = message, colors = colors)
            }
        }
    }
}

@Composable
private fun AuthHeader(colors: MochiColors) {
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
                text = "登录后连接你的 Agent",
                color = colors.textSecondary,
                fontSize = 14.sp,
            )
        }
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
