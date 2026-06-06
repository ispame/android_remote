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
                footer: Text("切换账号和退出登录会清除当前登录态，但保留本机 Agent、录音和耳机配置。")
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
                Button(role: .destructive) {
                    onLogout()
                } label: {
                    Text("退出登录")
                }
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
        let ttsLabel = tts.mode == "byok" && tts.providerId == "minimax" ? "MiniMax" : "系统"
        return "LLM / ASR / \(ttsLabel)"
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

private struct AiServiceSettingsView: View {
    @ObservedObject var settingsManager: SettingsManager
    let colors: MochiColors

    @State private var billingSummary: GatewayBillingSummaryResponse?
    @State private var draftAsrMode = "router"
    @State private var draftAsrProfileId = ""
    @State private var draftTtsMode = "system"
    @State private var minimaxApiKey = ""
    @State private var minimaxVoiceId = MiniMaxVoiceCatalog.defaultVoiceId
    @State private var fetchedMiniMaxVoices: [MiniMaxVoiceOption] = []
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

            Section("Router LLM") {
                AiSettingsInfoRow(label: "模式", value: "Router 会员模型")
                AiSettingsInfoRow(label: "Profile", value: llmProfileId)
                AiSettingsInfoRow(label: "调用方", value: "App / Agent 后端")
            }

            Section("ASR") {
                Picker("识别服务", selection: $draftAsrMode) {
                    Text("Router ASR").tag("router")
                    Text("Agent 后端").tag("backend")
                }
                .pickerStyle(.segmented)

                if draftAsrMode == "router" {
                    TextField("Profile ID", text: $draftAsrProfileId)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } else {
                    Text("录音或语音识别交给当前 Agent 后端处理")
                        .foregroundColor(.secondary)
                }
            }

            Section {
                Picker("TTS 引擎", selection: $draftTtsMode) {
                    Text("系统 TTS").tag("system")
                    Text("MiniMax").tag("minimax")
                }
                .pickerStyle(.segmented)

                if draftTtsMode == "minimax" {
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
                } else {
                    Text("使用 iOS 系统语音合成，不需要 API Key")
                        .foregroundColor(.secondary)
                }
            } header: {
                Text("TTS 引擎")
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
        .onChange(of: draftAsrMode) { _ in saveDraft() }
        .onChange(of: draftAsrProfileId) { _ in saveDraft() }
        .onChange(of: draftTtsMode) { _ in saveDraft() }
        .onChange(of: minimaxApiKey) { _ in saveDraft() }
        .onChange(of: minimaxVoiceId) { _ in saveDraft() }
    }

    private var llmProfileId: String {
        let profileId = settingsManager.aiSettings.defaults.llm.profileId.trimmingCharacters(in: .whitespacesAndNewlines)
        return profileId.isEmpty ? "default" : profileId
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

    private func syncDraftFromSettings() {
        didLoadDraft = false
        let defaults = settingsManager.aiSettings.defaults
        draftAsrMode = defaults.asr.mode == "backend" ? "backend" : "router"
        draftAsrProfileId = draftAsrMode == "router" ? defaults.asr.profileId : ""
        let tts = defaults.tts
        draftTtsMode = tts.mode == "byok" && tts.providerId == "minimax" ? "minimax" : "system"
        minimaxVoiceId = normalizedMiniMaxVoiceId(tts.voiceId)
        minimaxApiKey = settingsManager.localTtsCredential(providerId: "minimax") ?? ""
        DispatchQueue.main.async {
            didLoadDraft = true
        }
    }

    private func saveDraft() {
        guard didLoadDraft else { return }
        let normalizedVoiceId = normalizedMiniMaxVoiceId(minimaxVoiceId)
        settingsManager.updateLocalTtsCredential(providerId: "minimax", apiKey: minimaxApiKey)
        settingsManager.updateAiSettings(
            AiServiceSettings(
                defaults: AiServiceDefaults(
                    llm: settingsManager.aiSettings.defaults.llm,
                    asr: AiServiceChoice(
                        mode: draftAsrMode == "backend" ? "backend" : "router",
                        profileId: draftAsrMode == "router" ? draftAsrProfileId.trimmingCharacters(in: .whitespacesAndNewlines) : ""
                    ),
                    tts: draftTtsMode == "minimax"
                        ? AiServiceChoice(mode: "byok", providerId: "minimax", voiceId: normalizedVoiceId)
                        : AiServiceChoice(mode: "system", providerId: "system", voiceId: normalizedVoiceId)
                ),
                agentOverrides: settingsManager.aiSettings.agentOverrides
            )
        )
        statusMessage = "AI 服务设置已保存"
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
    private func refreshMiniMaxVoices() async {
        guard !minimaxApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            statusMessage = "请先填写 MiniMax API Key"
            return
        }
        isRefreshingMiniMaxVoices = true
        defer { isRefreshingMiniMaxVoices = false }
        do {
            fetchedMiniMaxVoices = try await MiniMaxVoiceCatalog.fetchAvailableVoices(apiKey: minimaxApiKey)
            statusMessage = "已刷新 \(fetchedMiniMaxVoices.count) 个 MiniMax 音色"
        } catch {
            statusMessage = "刷新音色失败：\(error.localizedDescription)"
        }
    }

    private func agentOverrideSummary(_ defaults: AiServiceDefaults) -> String {
        let asr = defaults.asr.mode == "backend" ? "Agent ASR" : "Router ASR"
        let tts = defaults.tts.mode == "byok" && defaults.tts.providerId == "minimax" ? "MiniMax" : "系统 TTS"
        return "继承全局 · \(asr) · \(tts)"
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
        RecordingType.allCases.filter { type in
            if type == .custom {
                return !draft.customPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            return true
        }
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
                Text("本机录音后，直接以默认录音类型发送给主 Agent 处理")
            }

            Section {
                Picker("默认录音类型", selection: $draft.defaultRecordingType) {
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
                Text("默认录音类型")
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
