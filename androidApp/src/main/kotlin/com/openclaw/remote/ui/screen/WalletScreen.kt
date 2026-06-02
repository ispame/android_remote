package com.openclaw.remote.ui.screen

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
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
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.CreditCard
import androidx.compose.material.icons.filled.QrCodeScanner
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
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
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.openclaw.remote.auth.BillingOrderResult
import com.openclaw.remote.auth.BillingProductResult
import com.openclaw.remote.auth.BillingSummaryResult
import com.openclaw.remote.auth.GatewayAuthClient
import com.openclaw.remote.auth.formatBillingAmountCents
import com.openclaw.remote.data.GatewayConfig
import com.openclaw.remote.ui.theme.MochiColors
import com.openclaw.remote.ui.theme.MochiTheme
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.Dispatchers

@Composable
fun WalletScreen(
    config: GatewayConfig,
    colors: MochiColors = MochiTheme.colors,
    initialNotice: String? = null,
    onBack: () -> Unit,
) {
    val scope = rememberCoroutineScope()
    val clipboard = LocalClipboardManager.current
    val snackbarHostState = remember { SnackbarHostState() }
    val authClient = remember { GatewayAuthClient() }
    var summary by remember(config.accountId) { mutableStateOf<BillingSummaryResult?>(null) }
    var activeOrder by remember(config.accountId) { mutableStateOf<BillingOrderResult?>(null) }
    var selectedProvider by remember(config.accountId) { mutableStateOf("manual_qr") }
    var qrBitmap by remember(activeOrder?.orderId) { mutableStateOf<Bitmap?>(null) }
    var loading by remember(config.accountId) { mutableStateOf(false) }
    var creatingProductId by remember { mutableStateOf<String?>(null) }

    suspend fun showMessage(message: String) {
        snackbarHostState.showSnackbar(message)
    }

    suspend fun refreshSummary() {
        if (config.accessToken.isBlank()) {
            summary = null
            return
        }
        loading = true
        runCatching {
            authClient.billingSummary(config.gatewayUrl, config.accessToken)
        }.onSuccess {
            summary = it
        }.onFailure {
            showMessage("钱包加载失败：${it.message ?: "unknown"}")
        }
        loading = false
    }

    LaunchedEffect(config.accountId, config.accessToken, config.gatewayUrl) {
        refreshSummary()
    }

    LaunchedEffect(initialNotice) {
        initialNotice?.takeIf { it.isNotBlank() }?.let { showMessage(it) }
    }

    LaunchedEffect(activeOrder?.orderId) {
        val order = activeOrder ?: return@LaunchedEffect
        qrBitmap = null
        runCatching {
            val bytes = authClient.billingOrderQrBytes(config.gatewayUrl, config.accessToken, order.orderId)
            withContext(Dispatchers.Default) { BitmapFactory.decodeByteArray(bytes, 0, bytes.size) }
        }.onSuccess {
            qrBitmap = it
        }.onFailure {
            showMessage("二维码加载失败：${it.message ?: "unknown"}")
        }
    }

    LaunchedEffect(activeOrder?.orderId) {
        val orderId = activeOrder?.orderId ?: return@LaunchedEffect
        while (isActive && activeOrder?.orderId == orderId && activeOrder?.status == "pending") {
            delay((activeOrder?.pollAfterMs ?: 3000).toLong())
            val updated = runCatching {
                authClient.billingOrder(config.gatewayUrl, config.accessToken, orderId)
            }.getOrElse {
                showMessage("订单状态刷新失败：${it.message ?: "unknown"}")
                return@LaunchedEffect
            }
            activeOrder = updated
            if (updated.status == "paid") {
                showMessage("支付成功，套餐已更新")
                refreshSummary()
                break
            }
            if (updated.status == "closed" || updated.status == "refunded") {
                showMessage("订单已结束")
                refreshSummary()
                break
            }
        }
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
                .padding(padding)
                .background(colors.background),
        ) {
            WalletTopBar(colors = colors, onBack = onBack, onRefresh = { scope.launch { refreshSummary() } })
            HorizontalDivider(color = colors.divider, thickness = 0.5.dp)

            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .verticalScroll(rememberScrollState())
                    .padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp),
            ) {
                if (config.accessToken.isBlank()) {
                    WalletPanel(colors) {
                        Text("请先登录账号", color = colors.textPrimary, fontSize = 16.sp, fontWeight = FontWeight.SemiBold)
                        Text("登录后才能查看套餐、余额和订单。", color = colors.textSecondary, fontSize = 13.sp)
                    }
                } else {
                    val snapshot = summary
                    WalletOverview(summary = snapshot, loading = loading, colors = colors)
                    ProviderSelector(
                        selectedProvider = selectedProvider,
                        availableProviders = snapshot?.products?.plans?.flatMap { it.availableProviders }?.distinct().orEmpty(),
                        colors = colors,
                        onSelect = { selectedProvider = it },
                    )

                    snapshot?.products?.plans.orEmpty().forEach { product ->
                        ProductPlanRow(
                            product = product,
                            colors = colors,
                            isCreating = creatingProductId == product.productId,
                            onCreateOrder = {
                                scope.launch {
                                    creatingProductId = product.productId
                                    runCatching {
                                        authClient.createBillingOrder(
                                            gatewayUrl = config.gatewayUrl,
                                            accessToken = config.accessToken,
                                            productId = product.productId,
                                            provider = selectedProvider.takeIf { it in product.availableProviders }
                                                ?: product.availableProviders.firstOrNull()
                                                ?: "manual_qr",
                                        )
                                    }.onSuccess {
                                        activeOrder = it
                                        showMessage("订单已创建")
                                    }.onFailure {
                                        showMessage("创建订单失败：${it.message ?: "unknown"}")
                                    }
                                    creatingProductId = null
                                }
                            },
                        )
                    }

                    activeOrder?.let { order ->
                        PaymentOrderPanel(
                            order = order,
                            qrBitmap = qrBitmap,
                            colors = colors,
                            onCopy = {
                                clipboard.setText(AnnotatedString(order.copyText.ifBlank { order.paymentUrl }))
                                scope.launch { showMessage("支付链接已复制") }
                            },
                            onClose = { activeOrder = null },
                        )
                    }

                    RecentOrders(summary?.recentOrders.orEmpty(), colors)
                }
            }
        }
    }
}

@Composable
private fun WalletTopBar(
    colors: MochiColors,
    onBack: () -> Unit,
    onRefresh: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(colors.surface)
            .padding(horizontal = 12.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Icon(
            imageVector = Icons.Default.CreditCard,
            contentDescription = null,
            tint = colors.primary,
            modifier = Modifier.size(22.dp),
        )
        Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text("钱包与套餐", color = colors.textPrimary, fontSize = 16.sp, fontWeight = FontWeight.SemiBold)
            Text("套餐优先，余额用于超额扣费", color = colors.textSecondary, fontSize = 11.sp)
        }
        Icon(
            imageVector = Icons.Default.Refresh,
            contentDescription = "刷新钱包",
            tint = colors.icon,
            modifier = Modifier
                .size(32.dp)
                .clip(RoundedCornerShape(8.dp))
                .clickable(onClick = onRefresh)
                .padding(6.dp),
        )
        Icon(
            imageVector = Icons.Default.ArrowBack,
            contentDescription = "返回",
            tint = colors.icon,
            modifier = Modifier
                .size(32.dp)
                .clip(RoundedCornerShape(8.dp))
                .clickable(onClick = onBack)
                .padding(6.dp),
        )
    }
}

@Composable
private fun WalletOverview(summary: BillingSummaryResult?, loading: Boolean, colors: MochiColors) {
    WalletPanel(colors) {
        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Column(verticalArrangement = Arrangement.spacedBy(4.dp), modifier = Modifier.weight(1f)) {
                Text("当前套餐", color = colors.textSecondary, fontSize = 12.sp)
                Text(
                    text = summary?.currentSubscription?.productId ?: "未开通",
                    color = colors.textPrimary,
                    fontSize = 18.sp,
                    fontWeight = FontWeight.SemiBold,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                val end = summary?.currentSubscription?.currentPeriodEnd
                if (!end.isNullOrBlank()) {
                    Text("有效期至 $end", color = colors.textSecondary, fontSize = 12.sp, maxLines = 1)
                }
            }
            Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text("余额", color = colors.textSecondary, fontSize = 12.sp)
                Text(
                    text = summary?.wallet?.let { formatBillingAmountCents(it.balanceCents, it.currency) } ?: "--",
                    color = colors.primary,
                    fontSize = 20.sp,
                    fontWeight = FontWeight.Bold,
                )
            }
        }
        if (loading) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                CircularProgressIndicator(modifier = Modifier.size(16.dp), strokeWidth = 2.dp, color = colors.primary)
                Text("正在刷新", color = colors.textSecondary, fontSize = 12.sp)
            }
        }
    }
}

@Composable
private fun ProviderSelector(
    selectedProvider: String,
    availableProviders: List<String>,
    colors: MochiColors,
    onSelect: (String) -> Unit,
) {
    val providers = listOf("manual_qr" to "手动", "wechat_qr" to "微信", "alipay_qr" to "支付宝")
        .filter { availableProviders.isEmpty() || it.first in availableProviders }
    WalletPanel(colors) {
        Text("支付方式", color = colors.textPrimary, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
            providers.forEach { (id, label) ->
                val selected = id == selectedProvider
                Box(
                    modifier = Modifier
                        .weight(1f)
                        .height(38.dp)
                        .clip(RoundedCornerShape(8.dp))
                        .background(if (selected) colors.primary else colors.inputBg)
                        .border(1.dp, if (selected) colors.primary else colors.inputBorder, RoundedCornerShape(8.dp))
                        .clickable { onSelect(id) },
                    contentAlignment = Alignment.Center,
                ) {
                    Text(label, color = if (selected) colors.onPrimary else colors.textPrimary, fontSize = 13.sp)
                }
            }
        }
    }
}

@Composable
private fun ProductPlanRow(
    product: BillingProductResult,
    colors: MochiColors,
    isCreating: Boolean,
    onCreateOrder: () -> Unit,
) {
    WalletPanel(colors) {
        Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.Top) {
            Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text(product.title, color = colors.textPrimary, fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
                    product.badge?.let {
                        Text(
                            it,
                            color = colors.primary,
                            fontSize = 11.sp,
                            modifier = Modifier
                                .clip(RoundedCornerShape(8.dp))
                                .background(colors.primary.copy(alpha = 0.12f))
                                .padding(horizontal = 7.dp, vertical = 3.dp),
                        )
                    }
                }
                Text(product.subtitle, color = colors.textSecondary, fontSize = 13.sp)
                product.benefits.take(4).forEach { benefit ->
                    Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.Top) {
                        Icon(Icons.Default.CheckCircle, contentDescription = null, tint = colors.onlineGreen, modifier = Modifier.size(15.dp))
                        Text(benefit, color = colors.textSecondary, fontSize = 12.sp)
                    }
                }
            }
            Spacer(Modifier.width(12.dp))
            Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(formatBillingAmountCents(product.amountCents, product.currency), color = colors.primary, fontSize = 18.sp, fontWeight = FontWeight.Bold)
                Button(
                    onClick = onCreateOrder,
                    enabled = !isCreating,
                    shape = RoundedCornerShape(8.dp),
                    colors = ButtonDefaults.buttonColors(containerColor = colors.primary, contentColor = colors.onPrimary),
                    contentPadding = PaddingValues(horizontal = 12.dp, vertical = 8.dp),
                ) {
                    Text(if (isCreating) "创建中" else "购买", fontSize = 13.sp)
                }
            }
        }
    }
}

@Composable
private fun PaymentOrderPanel(
    order: BillingOrderResult,
    qrBitmap: Bitmap?,
    colors: MochiColors,
    onCopy: () -> Unit,
    onClose: () -> Unit,
) {
    WalletPanel(colors) {
        Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Default.QrCodeScanner, contentDescription = null, tint = colors.primary, modifier = Modifier.size(20.dp))
            Spacer(Modifier.width(8.dp))
            Text("支付订单", color = colors.textPrimary, fontSize = 16.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f))
            Text(order.status, color = statusColor(order.status, colors), fontSize = 12.sp)
        }
        Text(formatBillingAmountCents(order.amountCents, order.currency), color = colors.primary, fontSize = 22.sp, fontWeight = FontWeight.Bold)
        Box(
            modifier = Modifier
                .size(230.dp)
                .clip(RoundedCornerShape(8.dp))
                .background(Color.White)
                .border(1.dp, colors.inputBorder, RoundedCornerShape(8.dp))
                .padding(10.dp)
                .align(Alignment.CenterHorizontally),
            contentAlignment = Alignment.Center,
        ) {
            if (qrBitmap == null) {
                CircularProgressIndicator(color = colors.primary)
            } else {
                Image(bitmap = qrBitmap.asImageBitmap(), contentDescription = "支付二维码", modifier = Modifier.fillMaxSize())
            }
        }
        Text("订单号 ${order.orderId}", color = colors.textSecondary, fontSize = 12.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
        Text("过期时间 ${order.expiresAt}", color = colors.textSecondary, fontSize = 12.sp, maxLines = 1)
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.fillMaxWidth()) {
            OutlinedButton(onClick = onCopy, modifier = Modifier.weight(1f), shape = RoundedCornerShape(8.dp)) {
                Icon(Icons.Default.ContentCopy, contentDescription = null, modifier = Modifier.size(16.dp))
                Spacer(Modifier.width(6.dp))
                Text("复制链接")
            }
            OutlinedButton(onClick = onClose, modifier = Modifier.weight(1f), shape = RoundedCornerShape(8.dp)) {
                Text("收起")
            }
        }
    }
}

@Composable
private fun RecentOrders(orders: List<BillingOrderResult>, colors: MochiColors) {
    if (orders.isEmpty()) return
    WalletPanel(colors) {
        Text("最近订单", color = colors.textPrimary, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
        orders.take(5).forEach { order ->
            Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(order.productId, color = colors.textPrimary, fontSize = 13.sp, maxLines = 1)
                    Text(order.orderId, color = colors.textSecondary, fontSize = 11.sp, maxLines = 1)
                }
                Text(formatBillingAmountCents(order.amountCents, order.currency), color = colors.textPrimary, fontSize = 13.sp)
                Spacer(Modifier.width(8.dp))
                Text(order.status, color = statusColor(order.status, colors), fontSize = 12.sp)
            }
        }
    }
}

@Composable
private fun WalletPanel(
    colors: MochiColors,
    content: @Composable ColumnScope.() -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(8.dp))
            .background(colors.surface)
            .border(1.dp, colors.divider, RoundedCornerShape(8.dp))
            .padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
        content = content,
    )
}

private fun statusColor(status: String, colors: MochiColors): Color =
    when (status.lowercase()) {
        "paid", "active" -> colors.onlineGreen
        "closed", "refunded" -> colors.textSecondary
        else -> colors.accent
    }
