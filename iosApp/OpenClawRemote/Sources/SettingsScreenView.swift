import SwiftUI
import Foundation
import UIKit

// MARK: - Connection Status Card

struct ConnectionStatusCard: View {
    let connectionState: ConnectionState
    let pairingState: PairingState
    let pairedBackendLabel: String?
    let colors: MochiColors
    let onUnpair: () -> Void

    private var statusColor: Color {
        if pairingState == .paired { return colors.primary }
        if connectionState == .connected || connectionState == .registered { return colors.accent }
        if connectionState == .connecting { return colors.secondary }
        return colors.recordingRed
    }

    private var statusText: String {
        if pairingState == .paired {
            return "已配对" + (pairedBackendLabel.map { ": \($0)" } ?? "")
        }
        switch connectionState {
        case .registered: return "连接成功，请扫码配对"
        case .connecting: return "连接中..."
        default: return "未连接"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: pairingState == .paired ? "link" : "link.badge.plus")
                .font(.system(size: 24))
                .foregroundColor(statusColor)

            VStack(alignment: .leading, spacing: 2) {
                Text("连接状态")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(colors.textSecondary)
                Text(statusText)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(statusColor)
            }

            Spacer()

            if pairingState == .paired {
                Button(action: onUnpair) {
                    Text("取消配对")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(colors.recordingRed)
                }
            }
        }
        .padding(16)
        .background(statusColor.opacity(0.1))
        .cornerRadius(12)
    }
}

// MARK: - Section Title

struct SectionTitleView: View {
    let text: String
    let colors: MochiColors

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(colors.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
    }
}

// MARK: - Outlined TextField — matches Android's Material3 OutlinedTextField

struct OutlinedTextField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    let colors: MochiColors

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(colors.textSecondary)

            TextField(placeholder, text: $text)
                .font(.system(size: 15, weight: .regular))
                .foregroundColor(colors.inputText)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(colors.inputBg)
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(colors.inputBorder, lineWidth: 1)
                    }
                )
        }
    }
}

struct OutlinedSecureField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    let colors: MochiColors

    @State private var isRevealed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(colors.textSecondary)

            HStack(spacing: 0) {
                Group {
                    if isRevealed {
                        TextField(placeholder, text: $text)
                            .textContentType(.oneTimeCode)
                    } else {
                        SecureField(placeholder, text: $text)
                            .textContentType(.password)
                    }
                }
                .font(.system(size: 15, weight: .regular))
                .foregroundColor(colors.inputText)

                Button {
                    isRevealed.toggle()
                } label: {
                    Image(systemName: isRevealed ? "eye.slash" : "eye")
                        .font(.system(size: 16))
                        .foregroundColor(colors.textSecondary)
                }
                .padding(.leading, 8)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(colors.inputBg)
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(colors.inputBorder, lineWidth: 1)
                }
            )
        }
    }
}

// MARK: - Help Card

struct HelpCardView: View {
    let colors: MochiColors

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("使用说明")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(colors.textPrimary)

            VStack(alignment: .leading, spacing: 4) {
                Text("1. 在 Agent 侧启动 Boson Relay 连接")
                Text("2. 扫描 Agent 生成的配对二维码")
                Text("3. App 会为每个 Agent 单独保存配置")
                Text("4. 多个 Agent 时可在顶部切换")
                Text("5. 当前 Chat 始终对应当前配置")
            }
            .font(.system(size: 12, weight: .regular))
            .foregroundColor(colors.textSecondary.opacity(0.7))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(colors.surface.opacity(0.5))
        .cornerRadius(12)
    }
}

// MARK: - Settings Screen

struct SettingsTopBarView: View {
    let isDark: Bool
    let colors: MochiColors
    let onToggleTheme: () -> Void
    let onBack: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("设置")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(colors.textPrimary)
                Text("Gateway 与配对")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(colors.textSecondary)
            }

            Spacer()

            Button(action: onToggleTheme) {
                Image(systemName: isDark ? "sun.max.fill" : "moon.fill")
                    .font(.system(size: 20))
                    .foregroundColor(isDark ? colors.accent : colors.primary)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(isDark ? colors.secondary.opacity(0.3) : Color.clear)
                    )
            }

            Button(action: onBack) {
                Image(systemName: "message.fill")
                    .font(.system(size: 20))
                    .foregroundColor(colors.icon)
                    .frame(width: 32, height: 32)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(colors.surface)
    }
}

private struct AdvancedSettingsDraft: Equatable {
    var deviceLabel: String

    init(config: GatewayConfig) {
        deviceLabel = config.deviceLabel
    }

    var normalizedDeviceLabel: String {
        let trimmed = deviceLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "我的设备" : trimmed
    }
}

private struct AdvancedInfoRow: View {
    let title: String
    let value: String
    var isSensitive = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .foregroundColor(.secondary)
            Spacer(minLength: 12)
            Text(displayValue)
                .font(.system(.body, design: isSensitive ? .monospaced : .default))
                .foregroundColor(.primary)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .accessibilityElement(children: .combine)
    }

    private var displayValue: String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "未配置" : trimmed
    }
}

struct SettingsScreenView: View {
    @ObservedObject var wsManager: WebSocketManager
    @ObservedObject var settingsManager: SettingsManager
    let isDark: Bool
    let colors: MochiColors
    let onToggleTheme: () -> Void
    let onRequestPair: (String) -> Void
    let onUnpair: () -> Void
    let onNavigateToQRScanner: () -> Void
    let onSelectProfile: (String) -> Void

    @State private var draft: AdvancedSettingsDraft
    @State private var statusMessage: String?

    init(
        wsManager: WebSocketManager,
        settingsManager: SettingsManager,
        isDark: Bool,
        colors: MochiColors,
        onToggleTheme: @escaping () -> Void,
        onRequestPair: @escaping (String) -> Void,
        onUnpair: @escaping () -> Void,
        onNavigateToQRScanner: @escaping () -> Void,
        onSelectProfile: @escaping (String) -> Void
    ) {
        self.wsManager = wsManager
        self.settingsManager = settingsManager
        self.isDark = isDark
        self.colors = colors
        self.onToggleTheme = onToggleTheme
        self.onRequestPair = onRequestPair
        self.onUnpair = onUnpair
        self.onNavigateToQRScanner = onNavigateToQRScanner
        self.onSelectProfile = onSelectProfile
        _draft = State(initialValue: AdvancedSettingsDraft(config: settingsManager.config))
    }

    var body: some View {
        Form {
            Section(
                header: Text("连接与诊断"),
                footer: Text("Agent 的 URL、Backend ID 和 Token 在 Agent 对话页右上角的配置中修改。")
            ) {
                AdvancedInfoRow(title: "当前 Agent", value: selectedProfile.resolvedDisplayName)
                AdvancedInfoRow(title: "连接状态", value: connectionStatusText)
                AdvancedInfoRow(title: "配对状态", value: pairingStatusText)
                AdvancedInfoRow(title: "Gateway URL", value: selectedProfile.gatewayUrl, isSensitive: true)
                AdvancedInfoRow(title: "Backend ID", value: selectedProfile.backendId, isSensitive: true)
                AdvancedInfoRow(title: "登录状态", value: accountStatusText)

                Button {
                    reconnectCurrentAgent()
                } label: {
                    Label("重连", systemImage: "arrow.clockwise")
                }

                Button(role: .destructive) {
                    unpairCurrentAgent()
                } label: {
                    Label("取消当前 Agent 配对", systemImage: "link.badge.minus")
                }
                .disabled(!canUnpairCurrentAgent)

                Button {
                    copyDiagnostics()
                } label: {
                    Label("复制诊断信息", systemImage: "doc.on.doc")
                }
            }

            Section(
                header: Text("设备信息"),
                footer: Text("该名称会作为终端标签显示在 Agent 配对和会话管理中。")
            ) {
                TextField("设备名称", text: $draft.deviceLabel)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            Section(
                header: Text("AI 服务"),
                footer: Text("LLM、ASR、TTS 的 Router / BYOK / Agent 配置统一在 AI 服务页管理。")
            ) {
                AdvancedInfoRow(title: "AI 服务", value: aiServiceSummary)
                AIServiceNavigationLink(settingsManager: settingsManager, colors: colors)
            }

            Section {
                Button {
                    saveAdvancedSettings()
                } label: {
                    Text("保存高级设置")
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }

            if let statusMessage {
                Section {
                    Text(statusMessage)
                        .foregroundColor(statusMessage == "设置已保存" ? colors.accent : .secondary)
                }
            }
        }
        .listStyle(.insetGrouped)
        .background(colors.background)
        .onAppear {
            syncDraftFromSettings()
        }
        .onChange(of: settingsManager.selectedProfileId) { _ in
            syncDraftFromSettings()
        }
    }

    private var selectedProfile: AgentProfile {
        settingsManager.selectedProfile
    }

    private var accountStatusText: String {
        let accountId = settingsManager.config.accountId.trimmingCharacters(in: .whitespacesAndNewlines)
        return accountId.isEmpty ? "未登录" : "已登录 · \(maskedAccountLabel(accountId))"
    }

    private var connectionStatusText: String {
        switch wsManager.connectionState {
        case .disconnected: return "未连接"
        case .connecting: return "连接中"
        case .connected: return "已连接，等待注册"
        case .registered: return "已注册"
        case .paired: return "已配对"
        }
    }

    private var pairingStatusText: String {
        switch wsManager.pairingState(for: selectedProfile) {
        case .unpaired: return "未配对"
        case .pending: return "配对中"
        case .paired:
            if let label = selectedProfile.backendLabel, !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "已配对 · \(label)"
            }
            return "已配对"
        }
    }

    private var canUnpairCurrentAgent: Bool {
        !selectedProfile.backendId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && wsManager.pairingState(for: selectedProfile) == .paired
    }

    private var diagnosticsText: String {
        [
            "Agent: \(selectedProfile.resolvedDisplayName)",
            "Connection: \(connectionStatusText)",
            "Pairing: \(pairingStatusText)",
            "Gateway URL: \(selectedProfile.gatewayUrl)",
            "Backend ID: \(selectedProfile.backendId)",
            "Account: \(accountStatusText)",
            "Device: \(draft.normalizedDeviceLabel)",
            "AI Service: \(aiServiceSummary)"
        ].joined(separator: "\n")
    }

    private var aiServiceSummary: String {
        let resolved = settingsManager.aiSettings.resolved(for: selectedProfile.id)
        let llm: String
        switch resolved.llm.mode {
        case "byok": llm = "BYOK \(providerLabel(resolved.llm))"
        case "agent": llm = "Agent LLM"
        default: llm = "Router LLM"
        }
        let asr: String
        switch resolved.asr.mode {
        case "byok": asr = "BYOK \(providerLabel(resolved.asr))"
        case "backend": asr = "Agent ASR"
        default: asr = "Router ASR"
        }
        let tts: String
        switch resolved.tts.mode {
        case "router": tts = "Router TTS"
        case "byok": tts = providerLabel(resolved.tts)
        default: tts = "系统 TTS"
        }
        return "\(llm) · \(asr) · \(tts)"
    }

    private func providerLabel(_ choice: AiServiceChoice) -> String {
        let displayName = choice.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !displayName.isEmpty { return displayName }
        let providerId = choice.providerId.trimmingCharacters(in: .whitespacesAndNewlines)
        return providerId.isEmpty ? "BYOK" : providerId
    }

    private func syncDraftFromSettings() {
        draft = AdvancedSettingsDraft(config: settingsManager.config)
        statusMessage = nil
    }

    private func saveAdvancedSettings() {
        settingsManager.updateDeviceLabel(draft.normalizedDeviceLabel)
        wsManager.applyProfile(
            settingsManager.selectedProfile,
            deviceLabel: settingsManager.config.deviceLabel,
            accessToken: settingsManager.config.accessToken
        )
        draft = AdvancedSettingsDraft(config: settingsManager.config)
        statusMessage = "设置已保存"
    }

    private func reconnectCurrentAgent() {
        wsManager.reconnect(to: selectedProfile.gatewayUrl)
        statusMessage = "正在重连当前 Agent"
    }

    private func unpairCurrentAgent() {
        onUnpair()
        statusMessage = "已发送取消配对请求"
    }

    private func copyDiagnostics() {
        UIPasteboard.general.string = diagnosticsText
        statusMessage = "诊断信息已复制"
    }
}

private func maskedAccountLabel(_ accountId: String) -> String {
    let value = accountId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard value.count > 12 else { return value }
    return "\(value.prefix(8))...\(value.suffix(4))"
}

struct GatewaySmsRequestResponse: Decodable {
    let requestId: String
    let retryAfterSeconds: Int

    private enum CodingKeys: String, CodingKey {
        case requestId = "request_id"
        case retryAfterSeconds = "retry_after_seconds"
    }
}

struct GatewayAuthSessionResponse: Decodable {
    let accountId: String
    let accessToken: String
    let refreshToken: String
    let accessExpiresAt: String
    let refreshExpiresAt: String

    private enum CodingKeys: String, CodingKey {
        case accountId = "account_id"
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case accessExpiresAt = "access_expires_at"
        case refreshExpiresAt = "refresh_expires_at"
    }
}

struct GatewayAuthMeResponse: Decodable {
    let accountId: String
    let displayName: String?
    let accountDisplayName: String
    let phoneNumberMasked: String

    private enum CodingKeys: String, CodingKey {
        case accountId = "account_id"
        case displayName = "display_name"
        case accountDisplayName = "account_display_name"
        case phoneNumberMasked = "phone_number_masked"
    }
}

struct GatewayAccountAgentProfile: Codable {
    let agentProfileId: String
    let platform: String
    let displayName: String
    let gatewayUrl: String
    let backendId: String
    let backendLabel: String?
    let isPaired: Bool
    let asrMode: String
    let sortOrder: Int
    let pinned: Bool

    private enum CodingKeys: String, CodingKey {
        case agentProfileId = "agent_profile_id"
        case platform
        case displayName = "display_name"
        case gatewayUrl = "gateway_url"
        case backendId = "backend_id"
        case backendLabel = "backend_label"
        case isPaired = "is_paired"
        case asrMode = "asr_mode"
        case sortOrder = "sort_order"
        case pinned
    }
}

private struct GatewayAccountAgentsResponse: Decodable {
    let agents: [GatewayAccountAgentProfile]
}

private struct GatewayAccountAgentUpsertResponse: Decodable {
    let agent: GatewayAccountAgentProfile
}

struct GatewayBillingProduct: Decodable, Identifiable {
    let productId: String
    let kind: String
    let title: String
    let subtitle: String
    let displayName: String
    let amountCents: Int
    let currency: String
    let billingPeriod: String
    let benefits: [String]
    let badge: String?
    let sortOrder: Int
    let availableProviders: [String]

    var id: String { productId }

    private enum CodingKeys: String, CodingKey {
        case productId = "product_id"
        case kind
        case title
        case subtitle
        case displayName = "display_name"
        case amountCents = "amount_cents"
        case currency
        case billingPeriod = "billing_period"
        case benefits
        case badge
        case sortOrder = "sort_order"
        case availableProviders = "available_providers"
    }
}

struct GatewayBillingProductsResponse: Decodable {
    let walletProducts: [GatewayBillingProduct]
    let plans: [GatewayBillingProduct]

    private enum CodingKeys: String, CodingKey {
        case walletProducts = "wallet_products"
        case plans
    }
}

struct GatewayBillingWalletResponse: Decodable {
    let balanceCents: Int
    let currency: String

    private enum CodingKeys: String, CodingKey {
        case balanceCents = "balance_cents"
        case currency
    }
}

struct GatewayBillingSubscriptionResponse: Decodable {
    let subscriptionId: String
    let productId: String
    let status: String
    let currentPeriodEnd: String

    private enum CodingKeys: String, CodingKey {
        case subscriptionId = "subscription_id"
        case productId = "product_id"
        case status
        case currentPeriodEnd = "current_period_end"
    }
}

struct GatewayBillingOrderResponse: Decodable, Identifiable {
    let orderId: String
    let productId: String
    let productKind: String
    let provider: String
    let status: String
    let amountCents: Int
    let currency: String
    let expiresAt: String
    let paymentUrl: String
    let copyText: String
    let qrImageUrl: String
    let pollAfterMs: Int

    var id: String { orderId }

    private enum CodingKeys: String, CodingKey {
        case orderId = "order_id"
        case productId = "product_id"
        case productKind = "product_kind"
        case provider
        case status
        case amountCents = "amount_cents"
        case currency
        case expiresAt = "expires_at"
        case paymentUrl = "payment_url"
        case copyText = "copy_text"
        case qrImageUrl = "qr_image_url"
        case pollAfterMs = "poll_after_ms"
    }
}

struct GatewayBillingUsageEventResponse: Decodable, Identifiable {
    let usageEventId: String
    let usageType: String
    let quantity: Int
    let amountCents: Int
    let backendId: String?
    let createdAt: String

    var id: String { usageEventId }

    private enum CodingKeys: String, CodingKey {
        case usageEventId = "usage_event_id"
        case usageType = "usage_type"
        case quantity
        case amountCents = "amount_cents"
        case backendId = "backend_id"
        case createdAt = "created_at"
    }
}

struct GatewayBillingUsageSummaryResponse: Decodable {
    let recentEvents: [GatewayBillingUsageEventResponse]

    private enum CodingKeys: String, CodingKey {
        case recentEvents = "recent_events"
    }
}

struct GatewayBillingSummaryResponse: Decodable {
    let accountId: String
    let wallet: GatewayBillingWalletResponse
    let currentSubscription: GatewayBillingSubscriptionResponse?
    let products: GatewayBillingProductsResponse
    let recentOrders: [GatewayBillingOrderResponse]
    let usage: GatewayBillingUsageSummaryResponse

    private enum CodingKeys: String, CodingKey {
        case accountId = "account_id"
        case wallet
        case currentSubscription = "current_subscription"
        case products
        case recentOrders = "recent_orders"
        case usage
    }
}

private struct GatewayBillingOrdersResponse: Decodable {
    let orders: [GatewayBillingOrderResponse]
}

struct GatewayAiChatResponse: Decodable {
    let id: String
    let modelProfileId: String
    let message: GatewayAiChatMessageResponse
    let usage: GatewayAiChatUsageResponse?
    let billing: GatewayAiChatBillingResponse?

    private enum CodingKeys: String, CodingKey {
        case id
        case modelProfileId = "model_profile_id"
        case message
        case usage
        case billing
    }
}

struct GatewayAiChatMessageResponse: Decodable {
    let role: String
    let content: String
}

struct GatewayAiChatUsageResponse: Decodable {
    let promptTokens: Int?
    let completionTokens: Int?
    let totalTokens: Int?

    private enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens = "total_tokens"
    }
}

struct GatewayAiChatBillingResponse: Decodable {
    let chargedCents: Int
    let usageEventId: String?

    private enum CodingKeys: String, CodingKey {
        case chargedCents = "charged_cents"
        case usageEventId = "usage_event_id"
    }
}

enum GatewayAuthClient {
    static func requestSms(
        gatewayUrl: String,
        phoneNumber: String,
        purpose: String = "login"
    ) async throws -> GatewaySmsRequestResponse {
        let request = try jsonRequest(
            url: "/api/v2/auth/sms/request",
            gatewayUrl: gatewayUrl,
            body: [
                "phone_number": phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines),
                "purpose": purpose
            ]
        )
        return try await send(request, as: GatewaySmsRequestResponse.self)
    }

    static func verifySms(
        gatewayUrl: String,
        phoneNumber: String,
        code: String,
        terminalLabel: String,
        platform: String
    ) async throws -> GatewayAuthSessionResponse {
        let request = try jsonRequest(
            url: "/api/v2/auth/sms/verify",
            gatewayUrl: gatewayUrl,
            body: [
                "phone_number": phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines),
                "code": code.trimmingCharacters(in: .whitespacesAndNewlines),
                "terminal_label": terminalLabel.trimmingCharacters(in: .whitespacesAndNewlines),
                "platform": platform
            ]
        )
        return try await send(request, as: GatewayAuthSessionResponse.self)
    }

    static func registerPassword(
        gatewayUrl: String,
        phoneNumber: String,
        code: String,
        password: String,
        terminalLabel: String,
        platform: String
    ) async throws -> GatewayAuthSessionResponse {
        let request = try jsonRequest(
            url: "/api/v2/auth/password/register",
            gatewayUrl: gatewayUrl,
            body: [
                "phone_number": phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines),
                "code": code.trimmingCharacters(in: .whitespacesAndNewlines),
                "password": password,
                "terminal_label": terminalLabel.trimmingCharacters(in: .whitespacesAndNewlines),
                "platform": platform
            ]
        )
        return try await send(request, as: GatewayAuthSessionResponse.self)
    }

    static func loginPassword(
        gatewayUrl: String,
        phoneNumber: String,
        password: String,
        terminalLabel: String,
        platform: String
    ) async throws -> GatewayAuthSessionResponse {
        let request = try jsonRequest(
            url: "/api/v2/auth/password/login",
            gatewayUrl: gatewayUrl,
            body: [
                "phone_number": phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines),
                "password": password,
                "terminal_label": terminalLabel.trimmingCharacters(in: .whitespacesAndNewlines),
                "platform": platform
            ]
        )
        return try await send(request, as: GatewayAuthSessionResponse.self)
    }

    static func requestPasswordReset(
        gatewayUrl: String,
        phoneNumber: String
    ) async throws -> GatewaySmsRequestResponse {
        try await requestSms(gatewayUrl: gatewayUrl, phoneNumber: phoneNumber, purpose: "password_reset")
    }

    static func resetPassword(
        gatewayUrl: String,
        phoneNumber: String,
        code: String,
        password: String
    ) async throws -> GatewayAuthSessionResponse {
        let request = try jsonRequest(
            url: "/api/v2/auth/password/forgot/reset",
            gatewayUrl: gatewayUrl,
            body: [
                "phone_number": phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines),
                "code": code.trimmingCharacters(in: .whitespacesAndNewlines),
                "password": password
            ]
        )
        return try await send(request, as: GatewayAuthSessionResponse.self)
    }

    static func changePassword(
        gatewayUrl: String,
        accessToken: String,
        currentPassword: String,
        newPassword: String
    ) async throws -> GatewayAuthSessionResponse {
        let request = try jsonRequest(
            url: "/api/v2/auth/password/change",
            gatewayUrl: gatewayUrl,
            body: [
                "current_password": currentPassword,
                "new_password": newPassword
            ],
            headers: [
                "Authorization": "Bearer \(accessToken.trimmingCharacters(in: .whitespacesAndNewlines))"
            ]
        )
        return try await send(request, as: GatewayAuthSessionResponse.self)
    }

    static func refresh(gatewayUrl: String, refreshToken: String) async throws -> GatewayAuthSessionResponse {
        let request = try jsonRequest(
            url: "/api/v2/auth/refresh",
            gatewayUrl: gatewayUrl,
            body: [
                "refresh_token": refreshToken.trimmingCharacters(in: .whitespacesAndNewlines)
            ]
        )
        return try await send(request, as: GatewayAuthSessionResponse.self)
    }

    static func logout(gatewayUrl: String, refreshToken: String) async throws {
        let request = try jsonRequest(
            url: "/api/v2/auth/logout",
            gatewayUrl: gatewayUrl,
            body: [
                "refresh_token": refreshToken.trimmingCharacters(in: .whitespacesAndNewlines)
            ]
        )
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) || httpResponse.statusCode == 204 else {
            throw GatewayAuthError(message: "HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
        }
    }

    static func me(gatewayUrl: String, accessToken: String) async throws -> GatewayAuthMeResponse {
        let request = try authorizedGetRequest(
            url: "/api/v2/auth/me",
            gatewayUrl: gatewayUrl,
            accessToken: accessToken
        )
        return try await send(request, as: GatewayAuthMeResponse.self)
    }

    static func updateAccountDisplayName(
        gatewayUrl: String,
        accessToken: String,
        displayName: String
    ) async throws -> GatewayAuthMeResponse {
        let request = try jsonRequest(
            url: "/api/v2/auth/me",
            gatewayUrl: gatewayUrl,
            body: [
                "display_name": displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            ],
            method: "PUT",
            headers: [
                "Authorization": "Bearer \(accessToken.trimmingCharacters(in: .whitespacesAndNewlines))"
            ]
        )
        return try await send(request, as: GatewayAuthMeResponse.self)
    }

    static func listAccountAgents(gatewayUrl: String, accessToken: String) async throws -> [GatewayAccountAgentProfile] {
        let request = try authorizedGetRequest(
            url: "/api/v2/account/agents",
            gatewayUrl: gatewayUrl,
            accessToken: accessToken
        )
        return try await send(request, as: GatewayAccountAgentsResponse.self).agents
    }

    static func upsertAccountAgent(
        gatewayUrl: String,
        accessToken: String,
        profile: GatewayAccountAgentProfile
    ) async throws -> GatewayAccountAgentProfile {
        var body: [String: Any] = [
            "agent_profile_id": profile.agentProfileId,
            "platform": profile.platform,
            "display_name": profile.displayName,
            "gateway_url": profile.gatewayUrl,
            "backend_id": profile.backendId,
            "asr_mode": profile.asrMode,
            "sort_order": profile.sortOrder,
            "pinned": profile.pinned
        ]
        if let backendLabel = profile.backendLabel {
            body["backend_label"] = backendLabel
        }
        let request = try jsonRequest(
            url: "/api/v2/account/agents",
            gatewayUrl: gatewayUrl,
            body: body,
            method: "PUT",
            headers: [
                "Authorization": "Bearer \(accessToken.trimmingCharacters(in: .whitespacesAndNewlines))"
            ]
        )
        return try await send(request, as: GatewayAccountAgentUpsertResponse.self).agent
    }

    static func billingSummary(gatewayUrl: String, accessToken: String) async throws -> GatewayBillingSummaryResponse {
        let request = try authorizedGetRequest(
            url: "/api/v2/billing/summary",
            gatewayUrl: gatewayUrl,
            accessToken: accessToken
        )
        return try await send(request, as: GatewayBillingSummaryResponse.self)
    }

    static func aiChat(
        gatewayUrl: String,
        accessToken: String,
        modelProfileId: String,
        messages: [OpenAICompatibleChatMessage]
    ) async throws -> GatewayAiChatResponse {
        let body: [String: Any] = [
            "model_profile_id": modelProfileId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "default" : modelProfileId.trimmingCharacters(in: .whitespacesAndNewlines),
            "messages": messages.map { ["role": $0.role, "content": $0.content] },
        ]
        let request = try jsonRequest(
            url: "/api/v2/ai/chat",
            gatewayUrl: gatewayUrl,
            body: body,
            headers: [
                "Authorization": "Bearer \(accessToken.trimmingCharacters(in: .whitespacesAndNewlines))"
            ]
        )
        return try await send(request, as: GatewayAiChatResponse.self)
    }

    static func createBillingOrder(
        gatewayUrl: String,
        accessToken: String,
        productId: String,
        provider: String
    ) async throws -> GatewayBillingOrderResponse {
        let request = try jsonRequest(
            url: "/api/v2/billing/orders",
            gatewayUrl: gatewayUrl,
            body: [
                "product_id": productId,
                "provider": provider
            ],
            headers: [
                "Authorization": "Bearer \(accessToken.trimmingCharacters(in: .whitespacesAndNewlines))"
            ]
        )
        return try await send(request, as: GatewayBillingOrderResponse.self)
    }

    static func billingOrder(
        gatewayUrl: String,
        accessToken: String,
        orderId: String
    ) async throws -> GatewayBillingOrderResponse {
        let request = try authorizedGetRequest(
            url: "/api/v2/billing/orders/\(orderId.trimmingCharacters(in: .whitespacesAndNewlines))",
            gatewayUrl: gatewayUrl,
            accessToken: accessToken
        )
        return try await send(request, as: GatewayBillingOrderResponse.self)
    }

    static func billingOrderQrData(
        gatewayUrl: String,
        accessToken: String,
        orderId: String
    ) async throws -> Data {
        let request = try authorizedGetRequest(
            url: "/api/v2/billing/orders/\(orderId.trimmingCharacters(in: .whitespacesAndNewlines))/qr.png",
            gatewayUrl: gatewayUrl,
            accessToken: accessToken
        )
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw GatewayAuthError(message: "HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
        }
        return data
    }

    private static func jsonRequest(
        url: String,
        gatewayUrl: String,
        body: [String: Any],
        method: String = "POST",
        headers: [String: String] = [:]
    ) throws -> URLRequest {
        guard let baseURL = authBaseURL(from: gatewayUrl),
              let requestURL = URL(string: url, relativeTo: baseURL) else {
            throw GatewayAuthError(message: "Invalid gateway URL")
        }
        var request = URLRequest(url: requestURL)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        headers.forEach { key, value in
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private static func authorizedGetRequest(
        url: String,
        gatewayUrl: String,
        accessToken: String
    ) throws -> URLRequest {
        guard let baseURL = authBaseURL(from: gatewayUrl),
              let requestURL = URL(string: url, relativeTo: baseURL) else {
            throw GatewayAuthError(message: "Invalid gateway URL")
        }
        var request = URLRequest(url: requestURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken.trimmingCharacters(in: .whitespacesAndNewlines))", forHTTPHeaderField: "Authorization")
        return request
    }

    private static func authBaseURL(from gatewayUrl: String) -> URL? {
        var value = gatewayUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        if value.hasPrefix("wss://") {
            value = "https://" + String(value.dropFirst("wss://".count))
        } else if value.hasPrefix("ws://") {
            value = "http://" + String(value.dropFirst("ws://".count))
        } else if !(value.hasPrefix("https://") || value.hasPrefix("http://")) {
            return nil
        }
        if value.hasSuffix("/ws") {
            value.removeLast(3)
        }
        if value.hasSuffix("/") {
            value.removeLast()
        }
        return URL(string: value)
    }

    private static func send<T: Decodable>(_ request: URLRequest, as type: T.Type) async throws -> T {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GatewayAuthError(message: "Invalid HTTP response")
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let code = errorJson["error"] as? String ?? errorJson["code"] as? String ?? "HTTP \(httpResponse.statusCode)"
                let message = errorJson["message"] as? String ?? code
                throw GatewayAuthError(message: "\(code): \(message)")
            }
            throw GatewayAuthError(message: "HTTP \(httpResponse.statusCode)")
        }
        return try JSONDecoder().decode(type, from: data)
    }
}

struct GatewayAuthError: LocalizedError {
    let message: String

    var errorDescription: String? { message }
}

private enum AppAuthMode: String, CaseIterable, Identifiable {
    case login = "登录"
    case register = "注册"
    case forgot = "找回密码"

    var id: String { rawValue }
}

private enum AppLoginMode: String, CaseIterable, Identifiable {
    case password = "密码"
    case sms = "验证码"

    var id: String { rawValue }
}

struct AuthScreenView: View {
    let config: GatewayConfig
    let colors: MochiColors
    let notice: String?
    let onAuthenticated: (GatewayAuthSessionResponse, String, String, String, String) -> Void
    let onNoticeShown: () -> Void

    @State private var authMode: AppAuthMode = .login
    @State private var loginMode: AppLoginMode = .password
    @State private var gatewayUrl: String = ""
    @State private var terminalLabel: String = ""
    @State private var phoneNumber: String = ""
    @State private var smsCode: String = ""
    @State private var password: String = ""
    @State private var confirmPassword: String = ""
    @State private var isLoading = false
    @State private var statusMessage: String?
    @State private var acceptedTerms = false

    var body: some View {
        ZStack {
            colors.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    AuthHeaderView(colors: colors, authMode: authMode)

                    VStack(alignment: .leading, spacing: 16) {
                        switch authMode {
                        case .login:
                            loginFields
                        case .register:
                            registerFields
                        case .forgot:
                            forgotFields
                        }
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(colors.surface)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(colors.divider, lineWidth: 1)
                    )

                    if let statusMessage {
                        AuthNoticeBanner(message: statusMessage, colors: colors)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 28)
                .padding(.bottom, 28)
            }
        }
        .onAppear {
            authMode = .login
            if !config.lastPhoneNumber.isEmpty {
                phoneNumber = config.lastPhoneNumber
            }
            if gatewayUrl.isEmpty {
                gatewayUrl = config.gatewayUrl.isEmpty ? "wss://boson-tech.top/ws" : config.gatewayUrl
            }
            if terminalLabel.isEmpty {
                terminalLabel = config.deviceLabel.isEmpty ? "我的设备" : config.deviceLabel
            }
            if let notice, !notice.isEmpty {
                statusMessage = notice
                onNoticeShown()
            }
            if !config.lastLoginMode.isEmpty, let mode = AppLoginMode(rawValue: config.lastLoginMode) {
                loginMode = mode
            }
        }
        .onChange(of: notice) { value in
            guard let value, !value.isEmpty else { return }
            statusMessage = value
            onNoticeShown()
        }
    }

    private var connectionFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "network")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(colors.primary)
                Text("连接入口")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(colors.textPrimary)
            }

            OutlinedTextField(
                label: "Gateway",
                placeholder: "wss://boson-tech.top/ws",
                text: $gatewayUrl,
                colors: colors
            )
            OutlinedTextField(
                label: "终端名称",
                placeholder: "我的设备",
                text: $terminalLabel,
                colors: colors
            )
        }
    }

    private var loginFields: some View {
        VStack(alignment: .leading, spacing: 16) {
            OutlinedTextField(
                label: "手机号",
                placeholder: "+8613800138000",
                text: $phoneNumber,
                colors: colors
            )

            if loginMode == .password {
                OutlinedSecureField(
                    label: "密码",
                    placeholder: "请输入密码",
                    text: $password,
                    colors: colors
                )
            } else {
                smsCodeRow(purpose: "login")
            }

            primaryButton("登录", systemImage: "arrow.right") {
                Task {
                    if loginMode == .password {
                        await loginWithPassword()
                    } else {
                        await loginWithSms()
                    }
                }
            }

            HStack {
                Button {
                    if loginMode == .password {
                        loginMode = .sms
                        password = ""
                    } else {
                        loginMode = .password
                        smsCode = ""
                    }
                } label: {
                    Text(loginMode == .password ? "验证码登录" : "密码登录")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(colors.primary)
                }

                Spacer()

                Button("忘记密码") {
                    authMode = .forgot
                    smsCode = ""
                    password = ""
                    confirmPassword = ""
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(colors.textSecondary)
            }

            Divider()
                .background(colors.divider)

            Button {
                authMode = .register
                phoneNumber = ""
                password = ""
                smsCode = ""
                confirmPassword = ""
                acceptedTerms = false
            } label: {
                HStack(spacing: 4) {
                    Text("还没有账号？")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(colors.textSecondary)
                    Text("立即注册")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(colors.primary)
                }
            }
            .frame(maxWidth: .infinity)
            .buttonStyle(.plain)
        }
    }

    private var registerFields: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("填写以下信息完成注册")
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(colors.textSecondary)

            OutlinedTextField(
                label: "手机号",
                placeholder: "+8613800138000",
                text: $phoneNumber,
                colors: colors
            )

            OutlinedSecureField(
                label: "设置密码",
                placeholder: "请设置登录密码",
                text: $password,
                colors: colors
            )

            smsCodeRow(purpose: "register")

            Button {
                acceptedTerms.toggle()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: acceptedTerms ? "checkmark.square.fill" : "square")
                        .font(.system(size: 16))
                        .foregroundColor(acceptedTerms ? colors.primary : colors.textSecondary)
                    Text("我已阅读并同意")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(colors.textSecondary)
                    Text("《用户协议》")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(colors.primary)
                    Text("和")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(colors.textSecondary)
                    Text("《隐私政策》")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(colors.primary)
                }
            }
            .buttonStyle(.plain)

            primaryButton("注册", systemImage: "person.badge.plus") {
                Task { await registerPassword() }
            }
            .disabled(!acceptedTerms)
            .opacity(acceptedTerms ? 1 : 0.6)

            Divider()
                .background(colors.divider)

            Button {
                authMode = .login
            } label: {
                HStack(spacing: 4) {
                    Text("已有账号？")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(colors.textSecondary)
                    Text("直接登录")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(colors.primary)
                }
            }
            .frame(maxWidth: .infinity)
            .buttonStyle(.plain)
        }
    }

    private var forgotFields: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Button {
                    authMode = .login
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(colors.textPrimary)
                        .frame(width: 32, height: 32)
                        .background(colors.inputBg)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(colors.inputBorder, lineWidth: 1)
                        )
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)

                Text("找回密码")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(colors.textPrimary)
                Spacer()
            }
            OutlinedTextField(
                label: "手机号",
                placeholder: "+8613800138000",
                text: $phoneNumber,
                colors: colors
            )
            smsCodeRow(purpose: "password_reset")
            OutlinedSecureField(label: "新密码", placeholder: "new password", text: $password, colors: colors)
            OutlinedSecureField(label: "确认新密码", placeholder: "confirm password", text: $confirmPassword, colors: colors)
            primaryButton("重置并登录", systemImage: "key.fill") {
                Task { await resetPassword() }
            }
        }
    }

    private func smsCodeRow(purpose: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("验证码")
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(colors.textSecondary)

            HStack(spacing: 10) {
                TextField("123456", text: $smsCode)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(colors.inputText)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        ZStack {
                            RoundedRectangle(cornerRadius: 8).fill(colors.inputBg)
                            RoundedRectangle(cornerRadius: 8).strokeBorder(colors.inputBorder, lineWidth: 1)
                        }
                    )

                Button {
                    Task { await requestCode(purpose: purpose) }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 12, weight: .semibold))
                        Text("发送")
                            .lineLimit(1)
                            .minimumScaleFactor(0.9)
                    }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(colors.textPrimary)
                    .frame(width: 88)
                    .padding(.vertical, 12)
                    .background(colors.inputBg)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(colors.inputBorder, lineWidth: 1)
                    )
                    .cornerRadius(8)
                }
                .disabled(isLoading)
            }
        }
    }

    private func primaryButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: isLoading ? "hourglass" : systemImage)
                    .font(.system(size: 14, weight: .semibold))
                Text(title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
            }
            .font(.system(size: 15, weight: .medium))
            .foregroundColor(colors.onPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(colors.primary)
            .cornerRadius(8)
            .opacity(isLoading ? 0.72 : 1)
        }
        .disabled(isLoading)
    }

    private func normalizedGatewayUrl() -> String {
        let trimmed = gatewayUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "wss://boson-tech.top/ws" : trimmed
    }

    private func normalizedTerminalLabel() -> String {
        let trimmed = terminalLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "我的设备" : trimmed
    }

    @MainActor
    private func requestCode(purpose: String) async {
        guard !phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            statusMessage = "请先填写手机号"
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await GatewayAuthClient.requestSms(
                gatewayUrl: normalizedGatewayUrl(),
                phoneNumber: phoneNumber,
                purpose: purpose
            )
            statusMessage = "验证码已发送，\(result.retryAfterSeconds) 秒后可重试"
        } catch {
            statusMessage = "发送验证码失败：\(error.localizedDescription)"
        }
    }

    @MainActor
    private func loginWithPassword() async {
        guard !phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              password.count >= 8 else {
            statusMessage = "请填写手机号和不少于 8 位的密码"
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let session = try await GatewayAuthClient.loginPassword(
                gatewayUrl: normalizedGatewayUrl(),
                phoneNumber: phoneNumber,
                password: password,
                terminalLabel: normalizedTerminalLabel(),
                platform: "ios"
            )
            onAuthenticated(session, normalizedGatewayUrl(), normalizedTerminalLabel(), AppLoginMode.password.rawValue, phoneNumber)
        } catch {
            statusMessage = "登录失败：\(error.localizedDescription)"
        }
    }

    @MainActor
    private func loginWithSms() async {
        guard !phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !smsCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            statusMessage = "请填写手机号和验证码"
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let session = try await GatewayAuthClient.verifySms(
                gatewayUrl: normalizedGatewayUrl(),
                phoneNumber: phoneNumber,
                code: smsCode,
                terminalLabel: normalizedTerminalLabel(),
                platform: "ios"
            )
            onAuthenticated(session, normalizedGatewayUrl(), normalizedTerminalLabel(), AppLoginMode.sms.rawValue, phoneNumber)
        } catch {
            statusMessage = "登录失败：\(error.localizedDescription)"
        }
    }

    @MainActor
    private func registerPassword() async {
        guard !phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !smsCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              password.count >= 8 else {
            statusMessage = "请检查手机号、验证码和密码（至少8位）"
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let session = try await GatewayAuthClient.registerPassword(
                gatewayUrl: normalizedGatewayUrl(),
                phoneNumber: phoneNumber,
                code: smsCode,
                password: password,
                terminalLabel: normalizedTerminalLabel(),
                platform: "ios"
            )
            onAuthenticated(session, normalizedGatewayUrl(), normalizedTerminalLabel(), AppLoginMode.password.rawValue, phoneNumber)
        } catch {
            statusMessage = "注册失败：\(error.localizedDescription)"
        }
    }

    @MainActor
    private func resetPassword() async {
        guard !phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !smsCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              password.count >= 8 else {
            statusMessage = "请检查手机号、验证码和密码（至少8位）"
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let session = try await GatewayAuthClient.resetPassword(
                gatewayUrl: normalizedGatewayUrl(),
                phoneNumber: phoneNumber,
                code: smsCode,
                password: password
            )
            onAuthenticated(session, normalizedGatewayUrl(), normalizedTerminalLabel(), AppLoginMode.password.rawValue, phoneNumber)
        } catch {
            statusMessage = "重置失败：\(error.localizedDescription)"
        }
    }
}

private struct AuthHeaderView: View {
    let colors: MochiColors
    let authMode: AppAuthMode

    private var subtitle: String {
        switch authMode {
        case .login:
            return "欢迎回来"
        case .register:
            return "注册新账号"
        case .forgot:
            return "找回密码"
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(colors.primary.opacity(0.12))
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(colors.primary)
            }
            .frame(width: 46, height: 46)

            VStack(alignment: .leading, spacing: 4) {
                Text("Boson Relay")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundColor(colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                Text(subtitle)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(colors.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
            }

            Spacer(minLength: 0)
        }
    }
}

private struct AuthNoticeBanner: View {
    let message: String
    let colors: MochiColors

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(colors.recordingRed)
                .padding(.top, 1)

            Text(message)
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(colors.recordingRed.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(colors.recordingRed.opacity(0.18), lineWidth: 1)
        )
    }
}
