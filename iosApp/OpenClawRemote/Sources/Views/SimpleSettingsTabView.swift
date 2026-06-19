import SwiftUI
import UIKit

struct SimpleSettingsTabView: View {
    @ObservedObject var wsManager: WebSocketManager
    @ObservedObject var settingsManager: SettingsManager
    @ObservedObject var headsetSettingsStore: HeadsetSettingsStore
    let isDark: Bool
    let colors: MochiColors
    let onToggleTheme: () -> Void
    let onRequestPair: (String) -> Void
    let onSelectProfile: (String) -> Void
    let onSwitchAccount: () -> Void
    let onLogout: () -> Void

    @State private var accountProfile: GatewayAuthMeResponse?

    var body: some View {
        List {
            Section {
                HStack {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 36))
                        .foregroundColor(colors.primary)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(accountTitle)
                            .font(.system(size: 16, weight: .semibold))
                        Text("当前 Agent：\(settingsManager.selectedProfile.resolvedDisplayName)")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 6)
            }

            Section("偏好") {
                Button {
                    onToggleTheme()
                } label: {
                    HStack {
                        Label(isDark ? "浅色模式" : "深色模式", systemImage: isDark ? "sun.max.fill" : "moon.fill")
                        Spacer()
                    }
                }
                .foregroundColor(.primary)

                NavigationLink {
                    SettingsScreenView(
                        wsManager: wsManager,
                        settingsManager: settingsManager,
                        isDark: isDark,
                        colors: colors,
                        onToggleTheme: onToggleTheme,
                        onRequestPair: onRequestPair,
                        onUnpair: {
                            wsManager.unpair()
                        },
                        onNavigateToQRScanner: {},
                        onSelectProfile: onSelectProfile
                    )
                    .navigationTitle("高级设置")
                } label: {
                    HStack {
                        Label("高级设置", systemImage: "slider.horizontal.3")
                        Spacer()
                    }
                }

                NavigationLink {
                    AiServiceSettingsView(
                        settingsManager: settingsManager,
                        colors: colors
                    )
                    .navigationTitle("AI 服务")
                } label: {
                    HStack {
                        Label("AI 服务", systemImage: "sparkles")
                        Spacer()
                        Text(aiServiceSummary)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }

                NavigationLink {
                    RecordingSettingsView(
                        settingsManager: settingsManager,
                        colors: colors
                    )
                    .navigationTitle("录音设置")
                } label: {
                    HStack {
                        Label("录音设置", systemImage: "waveform")
                        Spacer()
                    }
                }

                NavigationLink {
                    HeadsetSettingsMenuView(
                        headsetSettingsStore: headsetSettingsStore,
                        colors: colors
                    )
                    .navigationTitle("耳机设置")
                } label: {
                    HStack {
                        Label("耳机设置", systemImage: "headphones")
                        Spacer()
                    }
                }
            }

            Section(
                header: Text("账号"),
                footer: Text("退出登录会保留本机 Agent 配置，重新登录后可继续使用；切换账号会清空本机 Agent 配置。录音和耳机配置始终保留。")
            ) {
                NavigationLink {
                    WalletAndPlanView(
                        settingsManager: settingsManager,
                        colors: colors
                    )
                    .navigationTitle("钱包与套餐")
                } label: {
                    Label("钱包与套餐", systemImage: "creditcard.fill")
                }

                NavigationLink {
                    AccountSecurityView(
                        wsManager: wsManager,
                        settingsManager: settingsManager,
                        colors: colors,
                        accountProfile: accountProfile,
                        onProfileUpdated: { accountProfile = $0 }
                    )
                    .navigationTitle("账号与安全")
                } label: {
                    Label("账号与安全", systemImage: "key.fill")
                }

                Button("切换账号") {
                    onSwitchAccount()
                }
                Text("切换账号会清空本机 Agent 配置")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Button(role: .destructive) {
                    onLogout()
                } label: {
                    Text("退出登录")
                }
                Text("退出登录会保留本机 Agent 配置")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Section("关于") {
                HStack {
                    Text("APP 版本")
                    Spacer()
                    Text(appVersion)
                        .foregroundColor(.secondary)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: settingsManager.config.accessToken) {
            await loadAccountProfile()
        }
    }

    private var accountTitle: String {
        if let displayName = accountProfile?.accountDisplayName.trimmingCharacters(in: .whitespacesAndNewlines),
           !displayName.isEmpty {
            return displayName
        }
        return settingsManager.config.accountId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "未登录" : "账号已登录"
    }

    private var aiServiceSummary: String {
        let tts = settingsManager.aiSettings.defaults.tts
        let ttsLabel: String
        switch tts.mode {
        case "byok": ttsLabel = providerLabel(tts)
        default: ttsLabel = "系统"
        }
        return "LLM / ASR / \(ttsLabel)"
    }

    private func providerLabel(_ choice: AiServiceChoice) -> String {
        let displayName = choice.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !displayName.isEmpty { return displayName }
        let providerId = choice.providerId.trimmingCharacters(in: .whitespacesAndNewlines)
        return providerId.isEmpty ? "BYOK" : providerId
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        switch (version, build) {
        case let (.some(version), .some(build)):
            return "\(version) (\(build))"
        case let (.some(version), .none):
            return version
        default:
            return "1.0"
        }
    }

    @MainActor
    private func loadAccountProfile() async {
        let config = settingsManager.config
        guard !config.accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            accountProfile = nil
            return
        }
        accountProfile = try? await GatewayAuthClient.me(
            gatewayUrl: config.gatewayUrl,
            accessToken: config.accessToken
        )
    }
}

struct WalletAndPlanView: View {
    @ObservedObject var settingsManager: SettingsManager
    let colors: MochiColors
    var initialNotice: String?

    @State private var summary: GatewayBillingSummaryResponse?
    @State private var activeOrder: GatewayBillingOrderResponse?
    @State private var qrImage: UIImage?
    @State private var selectedProvider = "manual_qr"
    @State private var isLoading = false
    @State private var creatingProductId: String?
    @State private var statusMessage: String?
    @State private var pollTask: Task<Void, Never>?

    var body: some View {
        Form {
            if config.accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Section {
                    Text("请先登录账号")
                    Text("登录后才能查看套餐、余额和订单。")
                        .foregroundColor(.secondary)
                }
            } else {
                Section("当前权益") {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(currentPlanTitle)
                                .font(.system(size: 18, weight: .semibold))
                            if let end = summary?.currentSubscription?.currentPeriodEnd {
                                Text("有效期至 \(end)")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("余额")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                            Text(money(summary?.wallet.balanceCents ?? 0, summary?.wallet.currency ?? "CNY"))
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(colors.primary)
                        }
                    }

                    Button {
                        Task { await loadSummary() }
                    } label: {
                        Label(isLoading ? "正在刷新" : "刷新", systemImage: "arrow.clockwise")
                    }
                    .disabled(isLoading)
                }

                Section("支付方式") {
                    Picker("支付方式", selection: $selectedProvider) {
                        ForEach(providerOptions, id: \.id) { option in
                            Text(option.label).tag(option.id)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("套餐") {
                    ForEach(summary?.products.plans ?? []) { product in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .firstTextBaseline) {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(product.title)
                                            .font(.system(size: 16, weight: .semibold))
                                        if let badge = product.badge {
                                            Text(badge)
                                                .font(.system(size: 11, weight: .medium))
                                                .foregroundColor(colors.primary)
                                        }
                                    }
                                    Text(product.subtitle)
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Text(money(product.amountCents, product.currency))
                                    .font(.system(size: 17, weight: .bold))
                                    .foregroundColor(colors.primary)
                            }

                            ForEach(product.benefits.prefix(4), id: \.self) { benefit in
                                Label(benefit, systemImage: "checkmark.circle.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }

                            Button {
                                Task { await createOrder(for: product) }
                            } label: {
                                Text(creatingProductId == product.productId ? "正在创建订单..." : "生成支付二维码")
                            }
                            .disabled(creatingProductId != nil)
                        }
                        .padding(.vertical, 4)
                    }
                }

                if let activeOrder {
                    Section("支付订单") {
                        HStack {
                            Text(money(activeOrder.amountCents, activeOrder.currency))
                                .font(.system(size: 22, weight: .bold))
                                .foregroundColor(colors.primary)
                            Spacer()
                            Text(activeOrder.status)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(statusColor(activeOrder.status))
                        }

                        if let qrImage {
                            Image(uiImage: qrImage)
                                .resizable()
                                .interpolation(.none)
                                .scaledToFit()
                                .frame(maxWidth: .infinity, minHeight: 220, maxHeight: 260)
                                .padding(12)
                                .background(Color.white)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        } else {
                            HStack {
                                ProgressView()
                                Text("正在加载二维码")
                                    .foregroundColor(.secondary)
                            }
                        }

                        Text("订单号 \(activeOrder.orderId)")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                        Text("过期时间 \(activeOrder.expiresAt)")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)

                        Button {
                            UIPasteboard.general.string = billingPaymentClipboardText(for: activeOrder)
                            statusMessage = "支付链接已复制"
                        } label: {
                            Label("复制支付链接", systemImage: "doc.on.doc")
                        }
                    }
                }

                if !(summary?.recentOrders ?? []).isEmpty {
                    Section("最近订单") {
                        ForEach(summary?.recentOrders ?? []) { order in
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(order.productId)
                                        .font(.system(size: 13, weight: .medium))
                                    Text(order.orderId)
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Text(money(order.amountCents, order.currency))
                                Text(order.status)
                                    .foregroundColor(statusColor(order.status))
                                    .font(.system(size: 12))
                            }
                        }
                    }
                }
            }

            if let statusMessage {
                Section {
                    Text(statusMessage)
                        .foregroundColor(statusMessage.contains("失败") ? colors.recordingRed : colors.primary)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if let initialNotice, !initialNotice.isEmpty {
                statusMessage = initialNotice
            }
            await loadSummary()
        }
        .onDisappear {
            pollTask?.cancel()
        }
    }

    private var config: GatewayConfig {
        settingsManager.config
    }

    private var currentPlanTitle: String {
        guard let subscription = summary?.currentSubscription else { return "未开通套餐" }
        return summary?.products.plans.first(where: { $0.productId == subscription.productId })?.title ?? subscription.productId
    }

    private var providerOptions: [(id: String, label: String)] {
        let available = Set(summary?.products.plans.flatMap(\.availableProviders) ?? [])
        let all = [("manual_qr", "手动"), ("wechat_qr", "微信"), ("alipay_qr", "支付宝")]
        let filtered = all.filter { available.isEmpty || available.contains($0.0) }
        return filtered.isEmpty ? [("manual_qr", "手动")] : filtered
    }

    @MainActor
    private func loadSummary() async {
        let accessToken = config.accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !accessToken.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            summary = try await GatewayAuthClient.billingSummary(
                gatewayUrl: config.gatewayUrl,
                accessToken: accessToken
            )
        } catch {
            statusMessage = "钱包加载失败：\(error.localizedDescription)"
        }
    }

    @MainActor
    private func createOrder(for product: GatewayBillingProduct) async {
        let accessToken = config.accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !accessToken.isEmpty else {
            statusMessage = "请先登录"
            return
        }
        creatingProductId = product.productId
        defer { creatingProductId = nil }
        do {
            let provider = product.availableProviders.contains(selectedProvider)
                ? selectedProvider
                : (product.availableProviders.first ?? "manual_qr")
            let order = try await GatewayAuthClient.createBillingOrder(
                gatewayUrl: config.gatewayUrl,
                accessToken: accessToken,
                productId: product.productId,
                provider: provider
            )
            activeOrder = order
            statusMessage = "订单已创建"
            await loadQr(for: order)
            startPolling(order)
        } catch {
            statusMessage = "创建订单失败：\(error.localizedDescription)"
        }
    }

    @MainActor
    private func loadQr(for order: GatewayBillingOrderResponse) async {
        qrImage = nil
        do {
            let data = try await GatewayAuthClient.billingOrderQrData(
                gatewayUrl: config.gatewayUrl,
                accessToken: config.accessToken,
                orderId: order.orderId
            )
            qrImage = UIImage(data: data)
        } catch {
            statusMessage = "二维码加载失败：\(error.localizedDescription)"
        }
    }

    @MainActor
    private func startPolling(_ order: GatewayBillingOrderResponse) {
        pollTask?.cancel()
        pollTask = Task {
            var current = order
            while !Task.isCancelled && current.status == "pending" {
                try? await Task.sleep(nanoseconds: UInt64(max(current.pollAfterMs, 1000)) * 1_000_000)
                do {
                    current = try await GatewayAuthClient.billingOrder(
                        gatewayUrl: config.gatewayUrl,
                        accessToken: config.accessToken,
                        orderId: current.orderId
                    )
                    await MainActor.run {
                        activeOrder = current
                    }
                    if current.status == "paid" {
                        await MainActor.run {
                            statusMessage = "支付成功，套餐已更新"
                        }
                        await loadSummary()
                        break
                    }
                    if current.status == "closed" || current.status == "refunded" {
                        await MainActor.run {
                            statusMessage = "订单已结束"
                        }
                        await loadSummary()
                        break
                    }
                } catch {
                    await MainActor.run {
                        statusMessage = "订单状态刷新失败：\(error.localizedDescription)"
                    }
                    break
                }
            }
        }
    }

    private func money(_ amountCents: Int, _ currency: String) -> String {
        let value = String(format: "%.2f", Double(amountCents) / 100.0)
        return currency.uppercased() == "CNY" ? "¥\(value)" : "\(currency.uppercased()) \(value)"
    }

    private func statusColor(_ status: String) -> Color {
        switch status.lowercased() {
        case "paid", "active":
            return colors.onlineGreen
        case "closed", "refunded":
            return .secondary
        default:
            return colors.accent
        }
    }
}

private func billingPaymentClipboardText(for order: GatewayBillingOrderResponse) -> String {
    let paymentUrl = order.paymentUrl.trimmingCharacters(in: .whitespacesAndNewlines)
    return paymentUrl.isEmpty ? order.copyText : paymentUrl
}

struct AIServiceNavigationLink: View {
    @ObservedObject var settingsManager: SettingsManager
    let colors: MochiColors

    var body: some View {
        NavigationLink {
            AiServiceSettingsView(
                settingsManager: settingsManager,
                colors: colors
            )
            .navigationTitle("AI 服务")
        } label: {
            Label("打开 AI 服务", systemImage: "sparkles")
        }
    }
}

struct AiServiceSettingsView: View {
    @ObservedObject var settingsManager: SettingsManager
    @StateObject private var asrTestRecorder = AudioRecorder()
    let colors: MochiColors

    @State private var billingSummary: GatewayBillingSummaryResponse?
    @State private var draftLlmMode = "router"
    @State private var draftLlmProfileId = "default"
    @State private var draftLlmProviderId = "openai-compatible"
    @State private var draftLlmBaseUrl = "https://api.openai.com/v1"
    @State private var draftLlmModel = "gpt-4o-mini"
    @State private var llmApiKey = ""
    @State private var draftAsrMode = "router"
    @State private var draftAsrProfileId = ""
    @State private var draftAsrProviderId = "openai-compatible"
    @State private var draftAsrBaseUrl = "https://api.openai.com/v1"
    @State private var draftAsrModel = "whisper-1"
    @State private var asrApiKey = ""
    @State private var draftTtsMode = "system"
    @State private var draftTtsProviderId = "minimax"
    @State private var draftTtsBaseUrl = "https://api.minimaxi.com/v1"
    @State private var draftTtsModel = "speech-2.8-hd"
    @State private var minimaxApiKey = ""
    @State private var minimaxVoiceId = MiniMaxVoiceCatalog.defaultVoiceId
    @State private var fetchedMiniMaxVoices: [MiniMaxVoiceOption] = []
    @State private var isTestingLlm = false
    @State private var isTestingAsr = false
    @State private var hasStartedAsrTestGesture = false
    @State private var isRefreshingMiniMaxVoices = false
    @State private var isLoadingBilling = false
    @State private var didLoadDraft = false
    @State private var statusMessage: String?

    var body: some View {
        Form {
            Section("权益与钱包") {
                AiSettingsInfoRow(label: "会员套餐", value: currentPlanText)
                AiSettingsInfoRow(label: "钱包余额", value: walletBalanceText)
                NavigationLink {
                    WalletAndPlanView(
                        settingsManager: settingsManager,
                        colors: colors
                    )
                    .navigationTitle("钱包与套餐")
                } label: {
                    Label("查看钱包与套餐", systemImage: "creditcard.fill")
                }
                Button {
                    Task { await loadBillingSummary() }
                } label: {
                    Label(isLoadingBilling ? "正在刷新" : "刷新权益", systemImage: "arrow.clockwise")
                }
                .disabled(isLoadingBilling)
            }

            Section("业务场景") {
                serviceConfigPicker(
                    title: "Provider Chat LLM",
                    selectedId: settingsManager.aiSettings.sceneSelections.providerChat.llmConfigId,
                    configs: selectableLlmConfigs,
                    emptyText: "请先保存 LLM 配置"
                ) { configId in
                    settingsManager.updateAiSceneSelection(providerChatLlmConfigId: configId)
                }
                serviceConfigPicker(
                    title: "录音 ASR",
                    selectedId: settingsManager.aiSettings.sceneSelections.recording.asrConfigId,
                    configs: selectableAsrConfigs,
                    emptyText: "请先保存 ASR 配置"
                ) { configId in
                    settingsManager.updateAiSceneSelection(recordingAsrConfigId: configId)
                }
                serviceConfigPicker(
                    title: "播放 TTS",
                    selectedId: settingsManager.aiSettings.sceneSelections.playback.ttsConfigId,
                    configs: selectableTtsConfigs,
                    emptyText: "请先保存 TTS 配置"
                ) { configId in
                    settingsManager.updateAiSceneSelection(playbackTtsConfigId: configId)
                }
            }

            Section("LLM 配置") {
                Picker("模型服务", selection: $draftLlmMode) {
                    Text("Router").tag("router")
                    Text("BYOK").tag("byok")
                    Text("Agent").tag("agent")
                }
                .pickerStyle(.segmented)

                if draftLlmMode == "router" {
                    AiSettingsInfoRow(label: "模式", value: "Router 会员模型")
                    TextField("Profile ID", text: $draftLlmProfileId)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } else if draftLlmMode == "byok" {
                    Picker("Provider", selection: $draftLlmProviderId) {
                        ForEach(AiProviderCatalog.llmByokProviders) { provider in
                            Text(provider.label).tag(provider.id)
                        }
                    }
                    TextField("Base URL", text: $draftLlmBaseUrl)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Model", text: $draftLlmModel)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    AiSettingsInfoRow(label: "本机 Key", value: llmApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "未保存" : "已保存")
                    SecureField("LLM API Key", text: $llmApiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button {
                        Task { await testLlm() }
                    } label: {
                        Label(isTestingLlm ? "正在测试 LLM..." : "测试 LLM", systemImage: "bolt.horizontal.circle")
                    }
                    .disabled(isTestingLlm)
                    Button {
                        saveLlmKey()
                    } label: {
                        Label("保存 LLM Key", systemImage: "key.fill")
                    }
                } else {
                    Text("LLM 由当前 Agent 后端自行配置，本机不保存 Key。")
                        .foregroundColor(.secondary)
                }
                Button {
                    saveLlmConfig()
                } label: {
                    Label("保存 LLM 配置", systemImage: "tray.and.arrow.down.fill")
                }
            }

            Section("ASR 配置") {
                Picker("识别服务", selection: $draftAsrMode) {
                    Text("Router").tag("router")
                    Text("BYOK").tag("byok")
                    Text("Agent 后端").tag("backend")
                }
                .pickerStyle(.segmented)

                if draftAsrMode == "router" {
                    AiSettingsInfoRow(label: "模式", value: "Router ASR")
                    TextField("Profile ID", text: $draftAsrProfileId)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } else if draftAsrMode == "byok" {
                    Picker("Provider", selection: $draftAsrProviderId) {
                        ForEach(AiProviderCatalog.asrByokProviders) { provider in
                            Text(provider.label).tag(provider.id)
                        }
                    }
                    TextField("Base URL", text: $draftAsrBaseUrl)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Model", text: $draftAsrModel)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if draftAsrProviderId == "volcengine" {
                        Text("火山云 ASR：API Key 填 appKey:accessKey；Base URL 填 wss endpoint；Model 填 Resource ID。")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    AiSettingsInfoRow(label: "本机 Key", value: asrApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "未保存" : "已保存")
                    SecureField("ASR API Key", text: $asrApiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    HStack {
                        Label(
                            isTestingAsr
                                ? (asrTestRecorder.isRecording ? "松开测试 ASR" : "正在测试 ASR...")
                                : "按住测试 ASR",
                            systemImage: asrTestRecorder.isRecording ? "mic.fill" : "waveform.badge.magnifyingglass"
                        )
                        Spacer()
                        Text(asrTestRecorder.isRecording ? "录音中" : "按住说话")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { _ in
                                if !hasStartedAsrTestGesture {
                                    hasStartedAsrTestGesture = true
                                    startAsrTestRecording()
                                }
                            }
                            .onEnded { _ in
                                hasStartedAsrTestGesture = false
                                finishAsrTestRecording()
                            }
                    )
                    .allowsHitTesting(!isTestingAsr || asrTestRecorder.isRecording)
                    .opacity(isTestingAsr && !asrTestRecorder.isRecording ? 0.6 : 1)
                    .accessibilityAddTraits(.isButton)
                    Button {
                        saveAsrKey()
                    } label: {
                        Label("保存 ASR Key", systemImage: "key.fill")
                    }
                } else {
                    Text("录音或语音识别交给当前 Agent 后端处理")
                        .foregroundColor(.secondary)
                }
                Button {
                    saveAsrConfig()
                } label: {
                    Label("保存 ASR 配置", systemImage: "tray.and.arrow.down.fill")
                }
            }

            Section {
                Picker("TTS 引擎", selection: $draftTtsMode) {
                    Text("BYOK").tag("byok")
                    Text("系统 TTS").tag("system")
                }
                .pickerStyle(.segmented)

                if draftTtsMode == "byok" {
                    Picker("Provider", selection: $draftTtsProviderId) {
                        ForEach(AiProviderCatalog.ttsByokProviders) { provider in
                            Text(provider.label).tag(provider.id)
                        }
                    }
                    TextField("Base URL", text: $draftTtsBaseUrl)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Model", text: $draftTtsModel)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    AiSettingsInfoRow(label: "本机 Key", value: minimaxApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "未保存" : "已保存")
                    SecureField("MiniMax API Key", text: $minimaxApiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    Picker("MiniMax 音色", selection: $minimaxVoiceId) {
                        ForEach(minimaxVoices) { voice in
                            Text(voiceLabel(voice)).tag(voice.id)
                        }
                    }

                    Button {
                        Task { await refreshMiniMaxVoices() }
                    } label: {
                        Label(isRefreshingMiniMaxVoices ? "正在刷新音色..." : "从 MiniMax 刷新可用音色", systemImage: "arrow.clockwise")
                    }
                    .disabled(isRefreshingMiniMaxVoices)
                    Button {
                        saveTtsKey()
                    } label: {
                        Label("保存 TTS Key", systemImage: "key.fill")
                    }
                } else {
                    Text("使用 iOS 系统语音合成，不需要 API Key")
                        .foregroundColor(.secondary)
                }
                Button {
                    saveTtsConfig()
                } label: {
                    Label("保存 TTS 配置", systemImage: "tray.and.arrow.down.fill")
                }
            } header: {
                Text("TTS 配置")
            } footer: {
                Text("MiniMax API Key 只保存在本机 Keychain，不会写入 UserDefaults 或同步到 Router。")
            }

            Section("Agent 覆盖") {
                ForEach(settingsManager.profiles) { profile in
                    let resolved = settingsManager.aiSettings.resolved(for: profile.id)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(profile.resolvedDisplayName)
                        Text(agentOverrideSummary(resolved))
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }
                Text("Agent 级 ASR/TTS 覆盖请在对应 Agent 右上角配置页直接下拉修改。")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            if let statusMessage {
                Section {
                    Text(statusMessage)
                        .foregroundColor(statusMessage.contains("失败") ? colors.recordingRed : colors.primary)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            syncDraftFromSettings()
        }
        .task(id: settingsManager.config.accessToken) {
            await loadBillingSummary()
        }
        .onChange(of: draftLlmProviderId) { _ in applyLlmProviderDefaults() }
        .onChange(of: draftAsrProviderId) { _ in applyAsrProviderDefaults() }
        .onChange(of: draftTtsProviderId) { _ in applyTtsProviderDefaults() }
    }

    private var currentPlanText: String {
        guard let subscription = billingSummary?.currentSubscription,
              subscription.status.lowercased() == "active" else {
            return "无有效套餐"
        }
        return "\(subscription.productId) · 至 \(subscription.currentPeriodEnd)"
    }

    private var walletBalanceText: String {
        guard let wallet = billingSummary?.wallet else { return "未加载" }
        return money(wallet.balanceCents, wallet.currency)
    }

    private var minimaxVoices: [MiniMaxVoiceOption] {
        MiniMaxVoiceCatalog.buildSelectableVoices(
            currentVoiceId: minimaxVoiceId,
            fetchedVoices: fetchedMiniMaxVoices
        )
    }

    private var selectableLlmConfigs: [AiServiceConfig] {
        settingsManager.aiSettings.serviceConfigs.llm.filter(\.isSelectable)
    }

    private var selectableAsrConfigs: [AiServiceConfig] {
        settingsManager.aiSettings.serviceConfigs.asr.filter(\.isSelectable)
    }

    private var selectableTtsConfigs: [AiServiceConfig] {
        settingsManager.aiSettings.serviceConfigs.tts.filter(\.isSelectable)
    }

    @ViewBuilder
    private func serviceConfigPicker(
        title: String,
        selectedId: String,
        configs: [AiServiceConfig],
        emptyText: String,
        onSelect: @escaping (String) -> Void
    ) -> some View {
        if configs.isEmpty {
            AiSettingsInfoRow(label: title, value: emptyText)
        } else {
            Picker(title, selection: Binding(
                get: { selectedId },
                set: { onSelect($0) }
            )) {
                ForEach(configs) { config in
                    Text(serviceConfigLabel(config)).tag(config.id)
                }
            }
        }
    }

    private func serviceConfigLabel(_ config: AiServiceConfig) -> String {
        switch config.mode {
        case "router":
            return "Router \(config.profileId.isEmpty ? "default" : config.profileId)"
        case "byok":
            return "BYOK \(config.providerId.isEmpty ? config.displayName : config.providerId)"
        case "backend", "agent":
            return "Agent"
        case "system":
            return "System"
        default:
            return config.displayName.isEmpty ? config.id : config.displayName
        }
    }

    private var selectedLlmProvider: AiByokProviderTemplate {
        AiProviderCatalog.llmProvider(id: draftLlmProviderId) ?? AiProviderCatalog.llmByokProviders[0]
    }

    private var selectedAsrProvider: AiByokProviderTemplate {
        AiProviderCatalog.asrProvider(id: draftAsrProviderId) ?? AiProviderCatalog.asrByokProviders[0]
    }

    private var selectedTtsProvider: AiByokProviderTemplate {
        AiProviderCatalog.ttsProvider(id: draftTtsProviderId) ?? AiProviderCatalog.ttsByokProviders[0]
    }

    private func syncDraftFromSettings() {
        didLoadDraft = false
        let defaults = settingsManager.aiSettings.defaults
        let llm = settingsManager.aiSettings.llmConfigForProviderChat()?.toChoice() ?? defaults.llm
        draftLlmMode = llm.mode == "byok" || llm.mode == "agent" ? llm.mode : "router"
        draftLlmProfileId = llm.profileId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "default" : llm.profileId
        let llmProvider = AiProviderCatalog.preferredProvider(
            in: AiProviderCatalog.llmByokProviders,
            currentProviderId: llm.providerId,
            hasCredential: hasLocalCredential
        )
        draftLlmProviderId = llmProvider.id
        draftLlmBaseUrl = llm.baseUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? llmProvider.baseUrlDefault : llm.baseUrl
        draftLlmModel = llm.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? llmProvider.modelDefault : llm.model
        llmApiKey = settingsManager.localCredential(id: llmProvider.credentialId) ?? ""

        let asr = settingsManager.aiSettings.asrConfigForRecording()?.toChoice() ?? defaults.asr
        draftAsrMode = asr.mode == "backend" || asr.mode == "byok" ? asr.mode : "router"
        draftAsrProfileId = draftAsrMode == "router" ? asr.profileId : ""
        let asrProvider = AiProviderCatalog.preferredProvider(
            in: AiProviderCatalog.asrByokProviders,
            currentProviderId: asr.providerId,
            hasCredential: hasLocalCredential
        )
        draftAsrProviderId = asrProvider.id
        draftAsrBaseUrl = asr.baseUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? asrProvider.baseUrlDefault : asr.baseUrl
        draftAsrModel = asr.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? asrProvider.modelDefault : asr.model
        asrApiKey = settingsManager.localCredential(id: asrProvider.credentialId) ?? ""

        let tts = settingsManager.aiSettings.ttsConfigForPlayback()?.toChoice() ?? defaults.tts
        draftTtsMode = tts.mode == "byok" ? "byok" : "system"
        let ttsProvider = AiProviderCatalog.preferredProvider(
            in: AiProviderCatalog.ttsByokProviders,
            currentProviderId: tts.providerId,
            hasCredential: hasLocalCredential
        )
        draftTtsProviderId = ttsProvider.id
        draftTtsBaseUrl = tts.baseUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? ttsProvider.baseUrlDefault : tts.baseUrl
        draftTtsModel = tts.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? ttsProvider.modelDefault : tts.model
        minimaxVoiceId = normalizedMiniMaxVoiceId(tts.voiceId)
        minimaxApiKey = settingsManager.localCredential(id: ttsProvider.credentialId) ?? ""
        DispatchQueue.main.async {
            didLoadDraft = true
        }
    }

    private func saveLlmConfig() {
        settingsManager.upsertAiServiceConfig(llmDraftChoice.toServiceConfig(capability: "llm"))
        statusMessage = "LLM 配置已保存"
    }

    private func saveAsrConfig() {
        settingsManager.upsertAiServiceConfig(asrDraftChoice.toServiceConfig(capability: "asr"))
        statusMessage = "ASR 配置已保存"
    }

    private func saveTtsConfig() {
        settingsManager.upsertAiServiceConfig(ttsDraftChoice.toServiceConfig(capability: "tts"))
        statusMessage = "TTS 配置已保存"
    }

    private func saveLlmKey() {
        settingsManager.updateLocalCredential(id: selectedLlmProvider.credentialId, apiKey: llmApiKey)
        statusMessage = "LLM Key 已保存到本机 Keychain"
    }

    private func saveAsrKey() {
        settingsManager.updateLocalCredential(id: selectedAsrProvider.credentialId, apiKey: asrApiKey)
        statusMessage = "ASR Key 已保存到本机 Keychain"
    }

    private func saveTtsKey() {
        settingsManager.updateLocalCredential(id: selectedTtsProvider.credentialId, apiKey: minimaxApiKey)
        statusMessage = "TTS Key 已保存到本机 Keychain"
    }

    private var llmDraftChoice: AiServiceChoice {
        let provider = selectedLlmProvider
        return AiServiceChoice(
            mode: draftLlmMode,
            profileId: draftLlmMode == "router" ? draftLlmProfileId.trimmingCharacters(in: .whitespacesAndNewlines) : "",
            providerId: draftLlmMode == "router" ? "router" : provider.id,
            baseUrl: draftLlmMode == "byok" ? draftLlmBaseUrl.trimmingCharacters(in: .whitespacesAndNewlines) : "",
            model: draftLlmMode == "byok" ? draftLlmModel.trimmingCharacters(in: .whitespacesAndNewlines) : "",
            credentialId: draftLlmMode == "byok" ? provider.credentialId : "",
            displayName: draftLlmMode == "byok" ? provider.label : "Router LLM"
        )
    }

    private var asrDraftChoice: AiServiceChoice {
        let provider = selectedAsrProvider
        return AiServiceChoice(
            mode: draftAsrMode,
            profileId: draftAsrMode == "router" ? draftAsrProfileId.trimmingCharacters(in: .whitespacesAndNewlines) : "",
            providerId: draftAsrMode == "router" ? "router" : (draftAsrMode == "backend" ? "agent" : provider.id),
            baseUrl: draftAsrMode == "byok" ? draftAsrBaseUrl.trimmingCharacters(in: .whitespacesAndNewlines) : "",
            model: draftAsrMode == "byok" ? draftAsrModel.trimmingCharacters(in: .whitespacesAndNewlines) : "",
            credentialId: draftAsrMode == "byok" ? provider.credentialId : "",
            displayName: draftAsrMode == "backend" ? "Agent 后端识别" : (draftAsrMode == "byok" ? provider.label : "Router ASR")
        )
    }

    private var ttsDraftChoice: AiServiceChoice {
        let provider = selectedTtsProvider
        let normalizedVoiceId = normalizedMiniMaxVoiceId(minimaxVoiceId)
        if draftTtsMode == "byok" {
            return AiServiceChoice(
                mode: "byok",
                providerId: provider.id,
                voiceId: normalizedVoiceId,
                baseUrl: draftTtsBaseUrl.trimmingCharacters(in: .whitespacesAndNewlines),
                model: draftTtsModel.trimmingCharacters(in: .whitespacesAndNewlines),
                credentialId: provider.credentialId,
                displayName: provider.label
            )
        }
        return AiServiceChoice(mode: "system", providerId: "system", voiceId: normalizedVoiceId, displayName: "系统 TTS")
    }

    private func applyLlmProviderDefaults() {
        guard didLoadDraft else { return }
        let provider = selectedLlmProvider
        draftLlmBaseUrl = provider.baseUrlDefault
        draftLlmModel = provider.modelDefault
        llmApiKey = settingsManager.localCredential(id: provider.credentialId) ?? ""
    }

    private func applyAsrProviderDefaults() {
        guard didLoadDraft else { return }
        let provider = selectedAsrProvider
        draftAsrBaseUrl = provider.baseUrlDefault
        draftAsrModel = provider.modelDefault
        asrApiKey = settingsManager.localCredential(id: provider.credentialId) ?? ""
    }

    private func applyTtsProviderDefaults() {
        guard didLoadDraft else { return }
        let provider = selectedTtsProvider
        draftTtsBaseUrl = provider.baseUrlDefault
        draftTtsModel = provider.modelDefault
        minimaxApiKey = settingsManager.localCredential(id: provider.credentialId) ?? ""
    }

    @MainActor
    private func loadBillingSummary() async {
        let config = settingsManager.config
        let accessToken = config.accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !accessToken.isEmpty else {
            billingSummary = nil
            return
        }
        isLoadingBilling = true
        defer { isLoadingBilling = false }
        do {
            billingSummary = try await GatewayAuthClient.billingSummary(
                gatewayUrl: config.gatewayUrl,
                accessToken: accessToken
            )
        } catch {
            statusMessage = "权益加载失败：\(error.localizedDescription)"
        }
    }

    @MainActor
    private func testLlm() async {
        guard !llmApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            statusMessage = "请先填写 LLM API Key"
            return
        }
        isTestingLlm = true
        defer { isTestingLlm = false }
        do {
            let provider = selectedLlmProvider
            let content: String
            if provider.apiStyle == "anthropic" {
                content = try await AnthropicChatClient().testChat(
                    baseUrl: draftLlmBaseUrl,
                    apiKey: llmApiKey,
                    model: draftLlmModel
                )
            } else {
                content = try await OpenAICompatibleChatClient().testChat(
                    baseUrl: draftLlmBaseUrl,
                    apiKey: llmApiKey,
                    model: draftLlmModel
                )
            }
            statusMessage = "LLM 测试成功：\(content.prefix(80))"
        } catch {
            statusMessage = "LLM 测试失败：\(error.localizedDescription)"
        }
    }

    @MainActor
    private func startAsrTestRecording() {
        guard !asrApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            statusMessage = "请先填写 ASR API Key"
            return
        }
        guard !isTestingAsr else { return }
        isTestingAsr = true
        statusMessage = "正在录音，松开后测试 ASR"
        asrTestRecorder.startRecording()
    }

    @MainActor
    private func finishAsrTestRecording() {
        guard asrTestRecorder.isRecording else { return }
        asrTestRecorder.stopRecording { data in
            Task { await testAsr(audioData: data) }
        }
    }

    @MainActor
    private func testAsr(audioData: Data) async {
        defer { isTestingAsr = false }
        guard !asrApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            statusMessage = "请先填写 ASR API Key"
            return
        }
        guard audioData.count > 44 else {
            statusMessage = "ASR 测试失败：请按住按钮说一句话后松开"
            return
        }
        do {
            let transcript = try await ByokAsrTranscriptionClient.transcribe(
                choice: asrDraftChoice,
                apiKey: asrApiKey,
                audioData: audioData
            )
            let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                statusMessage = "ASR 测试没有识别到文本，请按住按钮说一句话后松开"
                return
            }
            statusMessage = "ASR 测试成功：\(String(text.prefix(80)))"
        } catch {
            let message = error.localizedDescription
            if message.contains("缺少识别文本") {
                statusMessage = "ASR 测试没有识别到文本，请按住按钮说一句话后松开"
            } else {
                statusMessage = "ASR 测试失败：\(message)"
            }
        }
    }

    @MainActor
    private func refreshMiniMaxVoices() async {
        guard !minimaxApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            statusMessage = "请先填写 MiniMax API Key"
            return
        }
        isRefreshingMiniMaxVoices = true
        defer { isRefreshingMiniMaxVoices = false }
        do {
            fetchedMiniMaxVoices = try await MiniMaxVoiceCatalog.fetchAvailableVoices(apiKey: minimaxApiKey, baseUrl: draftTtsBaseUrl)
            statusMessage = "已刷新 \(fetchedMiniMaxVoices.count) 个 MiniMax 音色"
        } catch {
            statusMessage = "刷新音色失败：\(error.localizedDescription)"
        }
    }

    private func agentOverrideSummary(_ defaults: AiServiceDefaults) -> String {
        let llm: String
        switch defaults.llm.mode {
        case "byok": llm = "BYOK \(providerLabel(defaults.llm))"
        case "agent": llm = "Agent LLM"
        default: llm = "Router LLM"
        }
        let asr: String
        switch defaults.asr.mode {
        case "backend": asr = "Agent ASR"
        case "byok": asr = "BYOK \(providerLabel(defaults.asr))"
        default: asr = "Router ASR"
        }
        let tts: String
        switch defaults.tts.mode {
        case "byok": tts = providerLabel(defaults.tts)
        default: tts = "系统 TTS"
        }
        return "\(llm) · \(asr) · \(tts)"
    }

    private func hasLocalCredential(_ credentialId: String) -> Bool {
        guard let value = settingsManager.localCredential(id: credentialId) else { return false }
        return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func providerLabel(_ choice: AiServiceChoice) -> String {
        let displayName = choice.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !displayName.isEmpty { return displayName }
        let providerId = choice.providerId.trimmingCharacters(in: .whitespacesAndNewlines)
        return providerId.isEmpty ? "BYOK" : providerId
    }

    private func voiceLabel(_ voice: MiniMaxVoiceOption) -> String {
        voice.name == voice.id ? voice.id : "\(voice.name) · \(voice.id)"
    }

    private func normalizedMiniMaxVoiceId(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? MiniMaxVoiceCatalog.defaultVoiceId : trimmed
    }

    private func money(_ amountCents: Int, _ currency: String) -> String {
        let value = String(format: "%.2f", Double(amountCents) / 100.0)
        return currency.uppercased() == "CNY" ? "¥\(value)" : "\(currency.uppercased()) \(value)"
    }
}

struct AgentAiOverrideEditorView: View {
    @ObservedObject var settingsManager: SettingsManager
    let profile: AgentProfile
    let colors: MochiColors

    @State private var inherit = true
    @State private var llmMode = "router"
    @State private var llmProfileId = "default"
    @State private var llmProviderId = "openai-compatible"
    @State private var llmBaseUrl = "https://api.openai.com/v1"
    @State private var llmModel = "gpt-4o-mini"
    @State private var asrMode = "router"
    @State private var asrProfileId = ""
    @State private var asrProviderId = "openai-compatible"
    @State private var asrBaseUrl = "https://api.openai.com/v1"
    @State private var asrModel = "whisper-1"
    @State private var ttsMode = "system"
    @State private var ttsProviderId = "minimax"
    @State private var ttsBaseUrl = "https://api.minimaxi.com/v1"
    @State private var ttsModel = "speech-2.8-hd"
    @State private var minimaxVoiceId = MiniMaxVoiceCatalog.defaultVoiceId
    @State private var didLoadDraft = false

    var body: some View {
        Form {
            Section {
                Toggle("继承全局默认", isOn: $inherit)
            } footer: {
                Text("API Key 仍使用本机统一凭据；Agent 覆盖只保存服务、模型和音色选择。")
            }

            if !inherit {
                Section("LLM") {
                    Picker("模型服务", selection: $llmMode) {
                        Text("Router").tag("router")
                        Text("BYOK").tag("byok")
                        Text("Agent").tag("agent")
                    }
                    .pickerStyle(.segmented)
                    if llmMode == "router" {
                        TextField("Profile ID", text: $llmProfileId)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    } else if llmMode == "byok" {
                        Picker("Provider", selection: $llmProviderId) {
                            ForEach(AiProviderCatalog.llmByokProviders) { provider in
                                Text(provider.label).tag(provider.id)
                            }
                        }
                        TextField("Base URL", text: $llmBaseUrl)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        TextField("Model", text: $llmModel)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    } else {
                        Text("LLM 由 Agent 后端自行配置。")
                            .foregroundColor(.secondary)
                    }
                }

                Section("ASR") {
                    Picker("识别服务", selection: $asrMode) {
                        Text("Router").tag("router")
                        Text("BYOK").tag("byok")
                        Text("Agent 后端").tag("backend")
                    }
                    .pickerStyle(.segmented)
                    if asrMode == "router" {
                        TextField("Profile ID", text: $asrProfileId)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    } else if asrMode == "byok" {
                        Picker("Provider", selection: $asrProviderId) {
                            ForEach(AiProviderCatalog.asrByokProviders) { provider in
                                Text(provider.label).tag(provider.id)
                            }
                        }
                        TextField("Base URL", text: $asrBaseUrl)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        TextField("Model", text: $asrModel)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    } else {
                        Text("音频会交给 Agent 后端识别。")
                            .foregroundColor(.secondary)
                    }
                }

                Section("TTS 引擎") {
                    Picker("TTS 引擎", selection: $ttsMode) {
                        Text("BYOK").tag("byok")
                        Text("系统 TTS").tag("system")
                    }
                    .pickerStyle(.segmented)
                    if ttsMode == "byok" {
                        Picker("Provider", selection: $ttsProviderId) {
                            ForEach(AiProviderCatalog.ttsByokProviders) { provider in
                                Text(provider.label).tag(provider.id)
                            }
                        }
                        TextField("Base URL", text: $ttsBaseUrl)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        TextField("Model", text: $ttsModel)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        TextField("MiniMax 音色", text: $minimaxVoiceId)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .onAppear { syncDraftFromSettings() }
        .onChange(of: inherit) { _ in saveOverride() }
        .onChange(of: llmMode) { _ in saveOverride() }
        .onChange(of: llmProfileId) { _ in saveOverride() }
        .onChange(of: llmProviderId) { _ in applyLlmProviderDefaults() }
        .onChange(of: llmBaseUrl) { _ in saveOverride() }
        .onChange(of: llmModel) { _ in saveOverride() }
        .onChange(of: asrMode) { _ in saveOverride() }
        .onChange(of: asrProfileId) { _ in saveOverride() }
        .onChange(of: asrProviderId) { _ in applyAsrProviderDefaults() }
        .onChange(of: asrBaseUrl) { _ in saveOverride() }
        .onChange(of: asrModel) { _ in saveOverride() }
        .onChange(of: ttsMode) { _ in saveOverride() }
        .onChange(of: ttsProviderId) { _ in applyTtsProviderDefaults() }
        .onChange(of: ttsBaseUrl) { _ in saveOverride() }
        .onChange(of: ttsModel) { _ in saveOverride() }
        .onChange(of: minimaxVoiceId) { _ in saveOverride() }
    }

    private func syncDraftFromSettings() {
        didLoadDraft = false
        let override = settingsManager.aiSettings.agentOverrides[profile.id]
        inherit = override?.inherit ?? true
        let resolved = inherit ? settingsManager.aiSettings.defaults : settingsManager.aiSettings.resolved(for: profile.id)
        llmMode = resolved.llm.mode == "byok" || resolved.llm.mode == "agent" ? resolved.llm.mode : "router"
        llmProfileId = resolved.llm.profileId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "default" : resolved.llm.profileId
        let llmProvider = AiProviderCatalog.llmProvider(id: resolved.llm.providerId) ?? AiProviderCatalog.llmByokProviders[0]
        llmProviderId = llmProvider.id
        llmBaseUrl = resolved.llm.baseUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? llmProvider.baseUrlDefault : resolved.llm.baseUrl
        llmModel = resolved.llm.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? llmProvider.modelDefault : resolved.llm.model
        asrMode = resolved.asr.mode == "backend" || resolved.asr.mode == "byok" ? resolved.asr.mode : "router"
        asrProfileId = asrMode == "router" ? resolved.asr.profileId : ""
        let asrProvider = AiProviderCatalog.asrProvider(id: resolved.asr.providerId) ?? AiProviderCatalog.asrByokProviders[0]
        asrProviderId = asrProvider.id
        asrBaseUrl = resolved.asr.baseUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? asrProvider.baseUrlDefault : resolved.asr.baseUrl
        asrModel = resolved.asr.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? asrProvider.modelDefault : resolved.asr.model
        ttsMode = resolved.tts.mode == "byok" ? "byok" : "system"
        let ttsProvider = AiProviderCatalog.preferredProvider(
            in: AiProviderCatalog.ttsByokProviders,
            currentProviderId: resolved.tts.providerId,
            hasCredential: { credentialId in
                guard let value = settingsManager.localCredential(id: credentialId) else { return false }
                return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
        )
        ttsProviderId = ttsProvider.id
        ttsBaseUrl = resolved.tts.baseUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? ttsProvider.baseUrlDefault : resolved.tts.baseUrl
        ttsModel = resolved.tts.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? ttsProvider.modelDefault : resolved.tts.model
        minimaxVoiceId = resolved.tts.voiceId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? MiniMaxVoiceCatalog.defaultVoiceId : resolved.tts.voiceId
        DispatchQueue.main.async {
            didLoadDraft = true
        }
    }

    private func saveOverride() {
        guard didLoadDraft else { return }
        var settings = settingsManager.aiSettings
        let llmProvider = AiProviderCatalog.llmProvider(id: llmProviderId) ?? AiProviderCatalog.llmByokProviders[0]
        let asrProvider = AiProviderCatalog.asrProvider(id: asrProviderId) ?? AiProviderCatalog.asrByokProviders[0]
        let ttsProvider = AiProviderCatalog.ttsProvider(id: ttsProviderId) ?? AiProviderCatalog.ttsByokProviders[0]
        if inherit {
            settings.agentOverrides[profile.id] = AiAgentOverride(inherit: true)
        } else {
            settings.agentOverrides[profile.id] = AiAgentOverride(
                inherit: false,
                llm: AiServiceChoice(
                    mode: llmMode,
                    profileId: llmMode == "router" ? llmProfileId.trimmingCharacters(in: .whitespacesAndNewlines) : "",
                    providerId: llmProvider.id,
                    baseUrl: llmBaseUrl.trimmingCharacters(in: .whitespacesAndNewlines),
                    model: llmModel.trimmingCharacters(in: .whitespacesAndNewlines),
                    credentialId: llmProvider.credentialId,
                    displayName: llmProvider.label
                ),
                asr: AiServiceChoice(
                    mode: asrMode,
                    profileId: asrMode == "router" ? asrProfileId.trimmingCharacters(in: .whitespacesAndNewlines) : "",
                    providerId: asrProvider.id,
                    baseUrl: asrBaseUrl.trimmingCharacters(in: .whitespacesAndNewlines),
                    model: asrModel.trimmingCharacters(in: .whitespacesAndNewlines),
                    credentialId: asrProvider.credentialId,
                    displayName: asrProvider.label
                ),
                tts: ttsMode == "byok"
                        ? AiServiceChoice(
                        mode: "byok",
                        providerId: ttsProvider.id,
                        voiceId: minimaxVoiceId,
                        baseUrl: ttsBaseUrl.trimmingCharacters(in: .whitespacesAndNewlines),
                        model: ttsModel.trimmingCharacters(in: .whitespacesAndNewlines),
                        credentialId: ttsProvider.credentialId,
                        displayName: ttsProvider.label
                    )
                        : AiServiceChoice(mode: "system", providerId: "system", voiceId: minimaxVoiceId, credentialId: ttsProvider.credentialId)
            )
        }
        settingsManager.updateAiSettings(settings)
    }

    private func applyLlmProviderDefaults() {
        guard didLoadDraft else { return }
        let provider = AiProviderCatalog.llmProvider(id: llmProviderId) ?? AiProviderCatalog.llmByokProviders[0]
        llmBaseUrl = provider.baseUrlDefault
        llmModel = provider.modelDefault
        saveOverride()
    }

    private func applyAsrProviderDefaults() {
        guard didLoadDraft else { return }
        let provider = AiProviderCatalog.asrProvider(id: asrProviderId) ?? AiProviderCatalog.asrByokProviders[0]
        asrBaseUrl = provider.baseUrlDefault
        asrModel = provider.modelDefault
        saveOverride()
    }

    private func applyTtsProviderDefaults() {
        guard didLoadDraft else { return }
        let provider = AiProviderCatalog.ttsProvider(id: ttsProviderId) ?? AiProviderCatalog.ttsByokProviders[0]
        ttsBaseUrl = provider.baseUrlDefault
        ttsModel = provider.modelDefault
        saveOverride()
    }
}

private struct AiSettingsInfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }
}

private struct AccountSecurityView: View {
    @ObservedObject var wsManager: WebSocketManager
    @ObservedObject var settingsManager: SettingsManager
    let colors: MochiColors
    let accountProfile: GatewayAuthMeResponse?
    let onProfileUpdated: (GatewayAuthMeResponse) -> Void

    var body: some View {
        Form {
            Section(header: Text("当前账号")) {
                HStack {
                    Text("账户显示")
                    Spacer()
                    Text(accountTitle)
                        .foregroundColor(.secondary)
                }
                HStack {
                    Text("注册手机号")
                    Spacer()
                    Text(accountProfile?.phoneNumberMasked ?? "同步后显示")
                        .foregroundColor(.secondary)
                }
            }

            Section(
                header: Text("安全设置"),
                footer: Text("手机号仅展示脱敏信息。修改密码会刷新当前登录态。")
            ) {
                NavigationLink {
                    EditAccountDisplayNameView(
                        settingsManager: settingsManager,
                        colors: colors,
                        accountProfile: accountProfile,
                        onProfileUpdated: onProfileUpdated
                    )
                    .navigationTitle("修改用户名")
                } label: {
                    Label("修改用户名", systemImage: "pencil")
                }

                NavigationLink {
                    ChangePasswordView(
                        wsManager: wsManager,
                        settingsManager: settingsManager,
                        colors: colors
                    )
                    .navigationTitle("修改密码")
                } label: {
                    Label("修改密码", systemImage: "lock.fill")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var accountTitle: String {
        if let displayName = accountProfile?.accountDisplayName.trimmingCharacters(in: .whitespacesAndNewlines),
           !displayName.isEmpty {
            return displayName
        }
        return settingsManager.config.accountId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "未登录" : "账号已登录"
    }
}

private struct EditAccountDisplayNameView: View {
    @ObservedObject var settingsManager: SettingsManager
    let colors: MochiColors
    let accountProfile: GatewayAuthMeResponse?
    let onProfileUpdated: (GatewayAuthMeResponse) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draftName = ""
    @State private var isLoading = false
    @State private var statusMessage: String?

    var body: some View {
        Form {
            Section(
                header: Text("用户名"),
                footer: Text("用户名保存后会作为账户显示；未设置时显示脱敏手机号。")
            ) {
                TextField(accountProfile?.accountDisplayName ?? "用户名", text: $draftName)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onChange(of: draftName) { value in
                        if value.count > 32 {
                            draftName = String(value.prefix(32))
                        }
                    }

                Button {
                    Task { await save() }
                } label: {
                    Text(isLoading ? "正在保存..." : "保存用户名")
                }
                .disabled(isLoading || draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if let statusMessage {
                Section {
                    Text(statusMessage)
                        .foregroundColor(statusMessage == "用户名已更新" ? colors.accent : colors.recordingRed)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            draftName = accountProfile?.displayName ?? ""
        }
    }

    @MainActor
    private func save() async {
        let current = settingsManager.config
        let accessToken = current.accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !accessToken.isEmpty else {
            statusMessage = "请先登录"
            return
        }
        let name = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            statusMessage = "请输入用户名"
            return
        }

        isLoading = true
        defer { isLoading = false }
        do {
            let profile = try await GatewayAuthClient.updateAccountDisplayName(
                gatewayUrl: current.gatewayUrl,
                accessToken: accessToken,
                displayName: name
            )
            onProfileUpdated(profile)
            statusMessage = "用户名已更新"
            dismiss()
        } catch {
            statusMessage = "用户名更新失败：\(error.localizedDescription)"
        }
    }
}

private struct ChangePasswordView: View {
    @ObservedObject var wsManager: WebSocketManager
    @ObservedObject var settingsManager: SettingsManager
    let colors: MochiColors

    @Environment(\.dismiss) private var dismiss
    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmNewPassword = ""
    @State private var isLoading = false
    @State private var statusMessage: String?

    var body: some View {
        Form {
            Section(
                header: Text("修改密码"),
                footer: Text("密码至少 8 位。修改成功后会刷新当前登录态，并继续使用本机已保存的 Agent 配置。")
            ) {
                SecureField("当前密码", text: $currentPassword)
                    .textContentType(.password)
                SecureField("新密码", text: $newPassword)
                    .textContentType(.newPassword)
                SecureField("确认新密码", text: $confirmNewPassword)
                    .textContentType(.newPassword)

                Button {
                    Task { await changePassword() }
                } label: {
                    Text(isLoading ? "正在修改..." : "确认修改密码")
                }
                .disabled(isLoading)
            }

            if let statusMessage {
                Section {
                    Text(statusMessage)
                        .foregroundColor(statusMessage == "密码已修改" ? colors.accent : colors.recordingRed)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var canSubmit: Bool {
        !currentPassword.isEmpty && newPassword.count >= 8 && newPassword == confirmNewPassword
    }

    @MainActor
    private func changePassword() async {
        let current = settingsManager.config
        let accessToken = current.accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !accessToken.isEmpty else {
            statusMessage = "请先登录"
            return
        }
        guard canSubmit else {
            statusMessage = "请检查当前密码和两次新密码"
            return
        }

        isLoading = true
        defer { isLoading = false }
        do {
            let session = try await GatewayAuthClient.changePassword(
                gatewayUrl: current.gatewayUrl,
                accessToken: accessToken,
                currentPassword: currentPassword,
                newPassword: newPassword
            )
            applyAuthSession(session)
            statusMessage = "密码已修改"
            dismiss()
        } catch {
            statusMessage = "修改密码失败：\(error.localizedDescription)"
        }
    }

    @MainActor
    private func applyAuthSession(_ session: GatewayAuthSessionResponse) {
        let current = settingsManager.config
        settingsManager.updateConfig(
            GatewayConfig(
                gatewayUrl: current.gatewayUrl,
                accountId: session.accountId,
                accessToken: session.accessToken,
                refreshToken: session.refreshToken,
                accessExpiresAt: session.accessExpiresAt,
                refreshExpiresAt: session.refreshExpiresAt,
                deviceLabel: current.deviceLabel,
                token: current.token,
                pairedBackendId: current.pairedBackendId,
                pairedBackendLabel: current.pairedBackendLabel,
                asrMode: current.asrMode,
                asrProfileId: current.asrProfileId,
                ttsEngine: current.ttsEngine,
                minimaxApiKey: current.minimaxApiKey,
                minimaxVoiceId: current.minimaxVoiceId,
                lastLoginMode: current.lastLoginMode,
                lastPhoneNumber: current.lastPhoneNumber
            )
        )
        currentPassword = ""
        newPassword = ""
        confirmNewPassword = ""
        wsManager.applyProfile(
            settingsManager.selectedProfile,
            deviceLabel: settingsManager.config.deviceLabel,
            accessToken: settingsManager.config.accessToken
        )
    }
}

private struct RecordingSettingsView: View {
    @ObservedObject var settingsManager: SettingsManager
    let colors: MochiColors

    @Environment(\.dismiss) private var dismiss
    @State private var draft = RecordingSettings()
    @State private var asrProfiles: [AsrProviderProfile] = []
    @State private var statusMessage: String?

    private var configuredProfiles: [AgentProfile] {
        settingsManager.profiles.filter { !$0.backendId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private var availableRecordingTypes: [RecordingType] {
        draft.settingsTypeOptions
    }

    private var promptPreviewText: String {
        switch draft.defaultRecordingType {
        case .audioOnly:
            return "此类型不会发送给任何 Agent，仅保存录音文件"
        case .meeting:
            return RecordingSettings.meetingPrompt
        case .idea:
            return RecordingSettings.ideaPrompt
        case .custom:
            return draft.customPrompt
        }
    }

    var body: some View {
        Form {
            Section("主 Agent") {
                if configuredProfiles.isEmpty {
                    Text("请先配置 Agent")
                        .foregroundColor(.secondary)
                } else {
                    Picker("主 Agent", selection: $draft.primaryAgentProfileId) {
                        ForEach(configuredProfiles) { profile in
                            Text(profile.resolvedDisplayName).tag(profile.id)
                        }
                    }
                }
            }

            Section {
                Toggle("本机录音默认执行", isOn: $draft.defaultDeliverToAgent)
            } footer: {
                Text("本机录音后，直接以录音类型发送给主 Agent 处理")
            }

            Section {
                Picker("录音类型", selection: $draft.defaultRecordingType) {
                    ForEach(availableRecordingTypes) { type in
                        Text(type.label).tag(type)
                    }
                }
                .pickerStyle(.menu)

                if draft.defaultRecordingType == .custom {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("自定义 Prompt")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                        TextEditor(text: $draft.customPrompt)
                            .font(.system(size: 13))
                            .frame(minHeight: 100)
                            .recordingScrollContentBackgroundHidden()
                            .background(colors.surface.opacity(0.5))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(colors.divider, lineWidth: 1)
                            )
                        Text("自定义 Prompt 描述处理录音的方式和后续任务")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(draft.defaultRecordingType == .audioOnly ? "说明" : "Prompt")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                        Text(promptPreviewText)
                            .font(.system(size: 13))
                            .foregroundColor(draft.defaultRecordingType == .audioOnly ? colors.recordingRed : .primary)
                            .textSelection(.enabled)
                    }
                }
            } header: {
                Text("录音类型")
            } footer: {
                if draft.defaultRecordingType == .audioOnly {
                    Text("耳机录音后，仅保存录音文件")
                } else {
                    Text("耳机录音后，自动发送给主 Agent 执行")
                }
            }

            Section("ASR 模型") {
                if asrProfiles.isEmpty {
                    TextField("Profile ID", text: $draft.asrProfileId)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } else {
                    Picker("Provider / Model", selection: $draft.asrProfileId) {
                        ForEach(asrProfiles) { profile in
                            Text("\(profile.providerLabel) · \(profile.modelLabel)").tag(profile.id)
                        }
                    }
                }
            }

            if let statusMessage {
                Section {
                    Text(statusMessage)
                        .font(.system(size: 13))
                        .foregroundColor(colors.primary)
                }
            }
        }
        .navigationTitle("录音设置")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("保存") {
                    save()
                }
                .disabled(configuredProfiles.isEmpty || (draft.defaultRecordingType == .custom && draft.customPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
            }
        }
        .onAppear {
            syncDraft()
            loadAsrProfiles()
        }
        .onReceive(settingsManager.$profiles) { _ in
            if configuredProfiles.isEmpty {
                draft.primaryAgentProfileId = ""
            } else if !configuredProfiles.contains(where: { $0.id == draft.primaryAgentProfileId }) {
                draft.primaryAgentProfileId = configuredProfiles.first?.id ?? ""
            }
        }
        .onChange(of: draft.primaryAgentProfileId) { _ in autoSave() }
        .onChange(of: draft.defaultRecordingType) { _ in autoSave() }
        .onChange(of: draft.customPrompt) { _ in autoSave() }
        .onChange(of: draft.asrProfileId) { _ in autoSave() }
        .onChange(of: draft.defaultDeliverToAgent) { _ in autoSave() }
    }

    private func syncDraft() {
        draft = settingsManager.recordingSettings
        if !configuredProfiles.isEmpty,
           !configuredProfiles.contains(where: { $0.id == draft.primaryAgentProfileId }) {
            draft.primaryAgentProfileId = configuredProfiles.first?.id ?? ""
        }
    }

    private func save() {
        settingsManager.updateRecordingSettings(draft)
        statusMessage = "录音设置已保存"
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            dismiss()
        }
    }

    private func autoSave() {
        settingsManager.updateRecordingSettings(draft)
    }

    private func loadAsrProfiles() {
        guard let url = asrProvidersUrl(from: settingsManager.selectedProfile.gatewayUrl) else { return }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
            let defaultProfileId = json["defaultProfileId"] as? String
            let rawProfiles = json["profiles"] as? [[String: Any]] ?? []
            let profiles = rawProfiles.compactMap { item -> AsrProviderProfile? in
                guard let id = item["id"] as? String,
                      let provider = item["provider"] as? String,
                      let model = item["model"] as? String else { return nil }
                return AsrProviderProfile(
                    id: id,
                    provider: provider,
                    providerLabel: item["providerLabel"] as? String ?? provider,
                    model: model,
                    modelLabel: item["modelLabel"] as? String ?? model
                )
            }
            DispatchQueue.main.async {
                asrProfiles = profiles
                if shouldReplaceRecordingAsrProfile(draft.asrProfileId, profiles: profiles) {
                    draft.asrProfileId = preferredRecordingAsrProfileId(profiles: profiles, defaultProfileId: defaultProfileId)
                    autoSave()
                }
            }
        }.resume()
    }

    private func shouldReplaceRecordingAsrProfile(_ profileId: String, profiles: [AsrProviderProfile]) -> Bool {
        let trimmed = profileId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        guard let profile = profiles.first(where: { $0.id == trimmed }) else { return true }
        return profile.provider == "volcengine-streaming" || profile.provider == "volcengine"
    }

    private func preferredRecordingAsrProfileId(profiles: [AsrProviderProfile], defaultProfileId: String?) -> String {
        profiles.first(where: { $0.provider == "volcengine-file" })?.id
            ?? profiles.first(where: { $0.id.localizedCaseInsensitiveContains("file") })?.id
            ?? defaultProfileId
            ?? profiles.first?.id
            ?? ""
    }

    private func asrProvidersUrl(from gatewayUrl: String) -> URL? {
        var value = gatewayUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("wss://") {
            value = "https://" + String(value.dropFirst("wss://".count))
        } else if value.hasPrefix("ws://") {
            value = "http://" + String(value.dropFirst("ws://".count))
        }
        if value.hasSuffix("/ws") {
            value.removeLast(3)
        }
        if value.hasSuffix("/") {
            value.removeLast()
        }
        return URL(string: "\(value)/api/asr/providers")
    }
}

private extension View {
    @ViewBuilder
    func recordingScrollContentBackgroundHidden() -> some View {
        if #available(iOS 16.0, *) {
            scrollContentBackground(.hidden)
        } else {
            self
        }
    }
}
