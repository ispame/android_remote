import SwiftUI
import Foundation

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

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(colors.textSecondary)

            SecureField(placeholder, text: $text)
                .font(.system(size: 15, weight: .regular))
                .foregroundColor(colors.inputText)
                .textContentType(.password)
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

private struct AgentFormState: Identifiable, Equatable {
    var id: String
    var isDraft: Bool
    var platform: AgentPlatform
    var displayName: String
    var gatewayUrl: String
    var backendId: String
    var token: String
    var backendLabel: String?
    var isPaired: Bool

    init(profile: AgentProfile, isDraft: Bool = false) {
        id = profile.id
        self.isDraft = isDraft
        platform = profile.platform
        displayName = profile.resolvedDisplayName
        gatewayUrl = profile.gatewayUrl
        backendId = profile.backendId
        token = profile.token
        backendLabel = profile.backendLabel
        isPaired = profile.isPaired
    }

    static func draft(gatewayUrl: String) -> AgentFormState {
        AgentFormState(
            profile: AgentProfile(
                id: UUID().uuidString,
                platform: .custom,
                displayName: "",
                gatewayUrl: gatewayUrl,
                backendId: "",
                token: "",
                isPaired: false
            ),
            isDraft: true
        )
    }

    var resolvedName: String {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        if let backendLabel, !backendLabel.isEmpty { return backendLabel }
        return platform.defaultDisplayName
    }
}

private struct AgentFormCardView: View {
    @Binding var form: AgentFormState
    let index: Int
    let status: AgentAvailabilityStatus
    let isSelected: Bool
    let isOnlyPersistedProfile: Bool
    let colors: MochiColors
    let onSelect: () -> Void
    let onRemove: () -> Void
    let onPair: () -> Void

    private var statusColor: Color {
        switch status {
        case .available: return colors.onlineGreen
        case .pairing, .connecting: return colors.accent
        case .unconfigured, .unpaired: return colors.textSecondary
        case .offline: return colors.recordingRed
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Button(action: onSelect) {
                    HStack(spacing: 8) {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : form.platform.iconName)
                            .font(.system(size: 16, weight: .semibold))
                        Text("Agent \(index + 1)")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundColor(isSelected ? colors.primary : colors.textPrimary)
                }
                .buttonStyle(.plain)

                Text(status.label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(statusColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(statusColor.opacity(0.12))
                    .cornerRadius(8)

                Spacer()

                Button(action: onRemove) {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(colors.recordingRed)
                        .frame(width: 32, height: 32)
                }
                .accessibilityLabel(isOnlyPersistedProfile ? "清空Agent配置" : "删除Agent")
            }

            OutlinedTextField(
                label: "Agent 名称（Agent label）",
                placeholder: form.platform.defaultDisplayName,
                text: $form.displayName,
                colors: colors
            )

            OutlinedTextField(
                label: "Gateway URL",
                placeholder: "wss://boson-tech.top/ws",
                text: $form.gatewayUrl,
                colors: colors
            )

            OutlinedTextField(
                label: "Backend Id",
                placeholder: "bk_xxx",
                text: $form.backendId,
                colors: colors
            )

            Button(action: onPair) {
                HStack {
                    Image(systemName: "link")
                    Text("配对")
                }
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(colors.onPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(form.backendId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? colors.textSecondary.opacity(0.35) : colors.primary)
                .cornerRadius(8)
            }
            .disabled(form.backendId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(14)
        .background(colors.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isSelected ? colors.primary : colors.divider, lineWidth: isSelected ? 1.5 : 1)
        )
        .cornerRadius(8)
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
    let onBack: () -> Void
    let onNavigateToQRScanner: () -> Void
    let onSelectProfile: (String) -> Void

    @State private var deviceLabel: String = ""
    @State private var phoneNumber: String = ""
    @State private var smsCode: String = ""
    @State private var isAuthLoading = false
    @State private var currentPassword: String = ""
    @State private var newPassword: String = ""
    @State private var confirmNewPassword: String = ""
    @State private var agentForms: [AgentFormState] = []
    @State private var asrMode: String = "router"
    @State private var asrProfileId: String = ""
    @State private var asrProfiles: [AsrProviderProfile] = []
    @State private var showSaved = false
    @State private var statusMessage: String?

    private var canAddDraft: Bool {
        agentForms.count < SettingsManager.maxAgentProfiles && !agentForms.contains(where: { $0.isDraft })
    }

    var body: some View {
        VStack(spacing: 0) {
            SettingsTopBarView(
                isDark: isDark,
                colors: colors,
                onToggleTheme: onToggleTheme,
                onBack: onBack
            )

            Divider().background(colors.divider)

            ScrollView {
                VStack(spacing: 16) {
                    Button(action: onNavigateToQRScanner) {
                        HStack {
                            Image(systemName: "qrcode.viewfinder")
                            Text("扫码或新增Agent")
                        }
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(colors.onPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(colors.primary)
                        .cornerRadius(8)
                    }

                    VStack(spacing: 12) {
                        ForEach(agentForms.indices, id: \.self) { index in
                            AgentFormCardView(
                                form: $agentForms[index],
                                index: index,
                                status: status(for: agentForms[index]),
                                isSelected: agentForms[index].id == settingsManager.selectedProfileId,
                                isOnlyPersistedProfile: settingsManager.profiles.count == 1 && !agentForms[index].isDraft,
                                colors: colors,
                                onSelect: {
                                    selectForm(agentForms[index])
                                },
                                onRemove: {
                                    removeForm(agentForms[index])
                                },
                                onPair: {
                                    pairForm(agentForms[index])
                                }
                            )
                        }

                        Button(action: addDraftAgent) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundColor(canAddDraft ? colors.primary : colors.textSecondary.opacity(0.4))
                                .frame(width: 44, height: 36)
                        }
                        .disabled(!canAddDraft)
                        .accessibilityLabel("新增Agent")
                    }

                    Divider()

                    SectionTitleView(text: "语音识别", colors: colors)
                    Picker("语音识别", selection: $asrMode) {
                        Text("Router 识别").tag("router")
                        Text("Agent 识别").tag("backend")
                    }
                    .pickerStyle(.segmented)

                    if asrMode == "router", asrProfiles.isEmpty {
                        OutlinedTextField(
                            label: "Provider / Model Profile",
                            placeholder: "默认 profile 或 volcengine-bigmodel",
                            text: $asrProfileId,
                            colors: colors
                        )
                    } else if asrMode == "router" {
                        Picker("Provider / Model", selection: $asrProfileId) {
                            ForEach(asrProfiles) { profile in
                                Text("\(profile.providerLabel) · \(profile.modelLabel)").tag(profile.id)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(colors.inputBg)
                        .cornerRadius(8)
                    }

                    SectionTitleView(text: "短信登录", colors: colors)
                    OutlinedTextField(
                        label: "手机号",
                        placeholder: "+8613800138000",
                        text: $phoneNumber,
                        colors: colors
                    )
                    OutlinedTextField(
                        label: "验证码",
                        placeholder: "123456",
                        text: $smsCode,
                        colors: colors
                    )
                    HStack(spacing: 12) {
                        Button {
                            Task { await requestSmsCode() }
                        } label: {
                            Text("发送验证码")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(colors.textPrimary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(colors.inputBg)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(colors.inputBorder, lineWidth: 1)
                                )
                                .cornerRadius(8)
                        }
                        .disabled(isAuthLoading)

                        Button {
                            Task { await verifySmsCode() }
                        } label: {
                            Text("登录")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(colors.onPrimary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(colors.primary)
                                .cornerRadius(8)
                        }
                        .disabled(isAuthLoading)
                    }
                    Button {
                        Task { await logoutSession() }
                    } label: {
                        Text("退出登录")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(colors.textPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(colors.inputBg)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(colors.inputBorder, lineWidth: 1)
                            )
                            .cornerRadius(8)
                    }
                    .disabled(isAuthLoading)

                    SectionTitleView(text: "修改密码", colors: colors)
                    OutlinedSecureField(
                        label: "当前密码",
                        placeholder: "current password",
                        text: $currentPassword,
                        colors: colors
                    )
                    OutlinedSecureField(
                        label: "新密码",
                        placeholder: "new password",
                        text: $newPassword,
                        colors: colors
                    )
                    OutlinedSecureField(
                        label: "确认新密码",
                        placeholder: "confirm password",
                        text: $confirmNewPassword,
                        colors: colors
                    )
                    Button {
                        Task { await changePassword() }
                    } label: {
                        Text("修改密码")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(colors.textPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(colors.inputBg)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(colors.inputBorder, lineWidth: 1)
                            )
                            .cornerRadius(8)
                    }
                    .disabled(isAuthLoading)

                    SectionTitleView(text: "账号会话", colors: colors)
                    Text(accountStatusText)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(colors.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(colors.inputBg)
                        .cornerRadius(8)

                    SectionTitleView(text: "设备信息", colors: colors)
                    OutlinedTextField(
                        label: "设备名称",
                        placeholder: "例如：我的手机",
                        text: $deviceLabel,
                        colors: colors
                    )

                    Button {
                        saveAll()
                        showSaved = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { showSaved = false }
                    } label: {
                        Text("保存")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(colors.onPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(colors.primary)
                            .cornerRadius(8)
                    }

                    if showSaved {
                        Text("设置已保存")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(colors.accent)
                    }

                    if let statusMessage {
                        Text(statusMessage)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(colors.recordingRed)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(16)
            }
            .background(colors.background)
        }
        .background(colors.background)
        .onAppear {
            syncFormsFromProfiles(keepingDraft: false)
            syncGlobalSettings()
            loadAsrProfiles()
        }
        .onReceive(settingsManager.$profiles) { _ in
            syncFormsFromProfiles(keepingDraft: true)
        }
        .onChange(of: asrGatewayUrl) { _ in
            loadAsrProfiles()
        }
    }

    private var asrGatewayUrl: String {
        agentForms.first(where: { !$0.gatewayUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })?.gatewayUrl
            ?? settingsManager.selectedProfile.gatewayUrl
    }

    private var accountStatusText: String {
        let accountId = settingsManager.config.accountId.trimmingCharacters(in: .whitespacesAndNewlines)
        return accountId.isEmpty ? "未登录" : "已登录 · \(maskedAccountLabel(accountId))"
    }

    private func syncFormsFromProfiles(keepingDraft: Bool) {
        let drafts = keepingDraft ? agentForms.filter(\.isDraft) : []
        var forms = settingsManager.profiles.map { AgentFormState(profile: $0) }
        for draft in drafts where forms.count < SettingsManager.maxAgentProfiles {
            forms.append(draft)
        }
        agentForms = forms
        deviceLabel = settingsManager.config.deviceLabel
    }

    private func syncGlobalSettings() {
        asrMode = settingsManager.globalAsrMode
        asrProfileId = settingsManager.globalAsrProfileId
    }

    private func status(for form: AgentFormState) -> AgentAvailabilityStatus {
        if form.backendId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .unconfigured
        }
        guard !form.isDraft, let profile = settingsManager.profiles.first(where: { $0.id == form.id }) else {
            return .unpaired
        }
        return wsManager.availabilityStatus(for: profile)
    }

    private func selectForm(_ form: AgentFormState) {
        guard !form.isDraft else { return }
        settingsManager.selectProfile(form.id)
        wsManager.applyProfile(
            settingsManager.selectedProfile,
            deviceLabel: settingsManager.config.deviceLabel,
            accessToken: settingsManager.config.accessToken
        )
        onSelectProfile(form.id)
    }

    private func addDraftAgent() {
        guard canAddDraft else {
            statusMessage = "最多支持 \(SettingsManager.maxAgentProfiles) 个 Agent"
            return
        }
        let gateway = agentForms.first(where: { !$0.backendId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })?.gatewayUrl
            ?? settingsManager.selectedProfile.gatewayUrl
        agentForms.append(.draft(gatewayUrl: gateway))
        statusMessage = nil
    }

    private func removeForm(_ form: AgentFormState) {
        if form.isDraft {
            agentForms.removeAll { $0.id == form.id }
            statusMessage = nil
            return
        }

        if !form.backendId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, form.isPaired {
            wsManager.unpair(profileId: form.id, backendId: form.backendId)
        }

        if settingsManager.profiles.count <= 1 {
            settingsManager.clearProfile(form.id)
            wsManager.clearProfileState(profileId: form.id)
        } else {
            settingsManager.deleteProfile(form.id)
            wsManager.removeProfileState(profileId: form.id)
            wsManager.syncProfiles(settingsManager.profiles)
            wsManager.applyProfile(
                settingsManager.selectedProfile,
                deviceLabel: settingsManager.config.deviceLabel,
                accessToken: settingsManager.config.accessToken
            )
        }
        syncFormsFromProfiles(keepingDraft: true)
        statusMessage = nil
    }

    private func pairForm(_ form: AgentFormState) {
        guard let profile = saveForm(form, select: true) else { return }
        guard !profile.backendId.isEmpty else {
            statusMessage = "请填写 Backend Id"
            return
        }
        wsManager.syncProfiles(settingsManager.profiles)
        wsManager.applyProfile(
            profile,
            deviceLabel: settingsManager.config.deviceLabel,
            accessToken: settingsManager.config.accessToken
        )
        wsManager.rememberBackendForPairing(profile.backendId)
        onRequestPair(profile.backendId)
    }

    @discardableResult
    private func saveForm(_ form: AgentFormState, select: Bool) -> AgentProfile? {
        let backendId = form.backendId.trimmingCharacters(in: .whitespacesAndNewlines)
        let gatewayUrl = normalizedGatewayUrl(form.gatewayUrl)
        if let error = sharedGatewayError(for: form, gatewayUrl: gatewayUrl, backendId: backendId) {
            statusMessage = error
            return nil
        }
        if form.isDraft, settingsManager.profiles.count >= SettingsManager.maxAgentProfiles {
            statusMessage = "最多支持 \(SettingsManager.maxAgentProfiles) 个 Agent"
            return nil
        }

        let existing = settingsManager.profiles.first { $0.id == form.id }
        let backendChanged = existing?.backendId != backendId
        let displayName = form.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? form.platform.defaultDisplayName
            : form.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let backendLabel = backendChanged ? (backendId.isEmpty ? nil : backendId) : (existing?.backendLabel ?? form.backendLabel ?? backendId)
        let profile = AgentProfile(
            id: form.id,
            platform: form.platform,
            displayName: displayName,
            gatewayUrl: gatewayUrl,
            backendId: backendId,
            backendLabel: backendLabel,
            token: existing?.token ?? form.token.trimmingCharacters(in: .whitespacesAndNewlines),
            isPaired: !backendId.isEmpty && !backendChanged && (existing?.isPaired ?? form.isPaired),
            asrMode: asrMode,
            asrProfileId: asrMode == "router" ? asrProfileId : ""
        )

        guard settingsManager.saveProfile(profile, select: select) else {
            statusMessage = settingsManager.profileAcceptError(gatewayUrl: gatewayUrl, backendId: backendId) ?? "无法保存 Agent"
            return nil
        }
        agentForms.removeAll { $0.id == form.id && $0.isDraft }
        syncFormsFromProfiles(keepingDraft: true)
        statusMessage = nil
        return settingsManager.profiles.first { $0.id == profile.id } ?? profile
    }

    private func saveAll() {
        for form in agentForms {
            if form.isDraft,
               form.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               form.backendId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                continue
            }
            _ = saveForm(form, select: form.id == settingsManager.selectedProfileId)
        }
        settingsManager.updateConfig(
            GatewayConfig(
                gatewayUrl: settingsManager.selectedProfile.gatewayUrl,
                accountId: settingsManager.config.accountId,
                accessToken: settingsManager.config.accessToken,
                refreshToken: settingsManager.config.refreshToken,
                accessExpiresAt: settingsManager.config.accessExpiresAt,
                refreshExpiresAt: settingsManager.config.refreshExpiresAt,
                deviceLabel: deviceLabel.trimmingCharacters(in: .whitespacesAndNewlines),
                token: settingsManager.selectedProfile.token,
                pairedBackendId: settingsManager.config.pairedBackendId,
                pairedBackendLabel: settingsManager.config.pairedBackendLabel,
                asrMode: asrMode,
                asrProfileId: asrMode == "router" ? asrProfileId : ""
            )
        )
        settingsManager.updateDeviceLabel(deviceLabel)
        settingsManager.updateGlobalAsr(mode: asrMode, profileId: asrProfileId)
        wsManager.syncProfiles(settingsManager.profiles)
        wsManager.updateAsrConfiguration(mode: asrMode, profileId: asrProfileId)
        wsManager.applyProfile(
            settingsManager.selectedProfile,
            deviceLabel: settingsManager.config.deviceLabel,
            accessToken: settingsManager.config.accessToken
        )
        syncFormsFromProfiles(keepingDraft: true)
    }

    private func sharedGatewayError(for form: AgentFormState, gatewayUrl: String, backendId: String) -> String? {
        guard !backendId.isEmpty else { return nil }
        let target = AgentProfile.normalizedGatewayKey(gatewayUrl)
        let otherGateways = agentForms
            .filter { $0.id != form.id && !$0.backendId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { AgentProfile.normalizedGatewayKey(normalizedGatewayUrl($0.gatewayUrl)) }
        if let first = otherGateways.first, first != target {
            return "当前版本仅支持同一 Gateway 下最多 \(SettingsManager.maxAgentProfiles) 个 Agent"
        }
        return nil
    }

    private func normalizedGatewayUrl(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "wss://boson-tech.top/ws" : trimmed
    }

    private func authGatewayUrl() -> String {
        normalizedGatewayUrl(settingsManager.selectedProfile.gatewayUrl)
    }

    private func loadAsrProfiles() {
        guard let url = asrProvidersUrl(from: asrGatewayUrl) else { return }
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
                if asrProfileId.isEmpty {
                    asrProfileId = defaultProfileId ?? profiles.first?.id ?? ""
                }
            }
        }.resume()
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

    @MainActor
    private func applyAuthSession(_ session: GatewayAuthSessionResponse) {
        settingsManager.updateConfig(
            GatewayConfig(
                gatewayUrl: settingsManager.selectedProfile.gatewayUrl,
                accountId: session.accountId,
                accessToken: session.accessToken,
                refreshToken: session.refreshToken,
                accessExpiresAt: session.accessExpiresAt,
                refreshExpiresAt: session.refreshExpiresAt,
                deviceLabel: deviceLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "我的设备" : deviceLabel,
                token: settingsManager.selectedProfile.token,
                pairedBackendId: settingsManager.config.pairedBackendId,
                pairedBackendLabel: settingsManager.config.pairedBackendLabel,
                asrMode: asrMode,
                asrProfileId: asrMode == "router" ? asrProfileId : ""
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

    @MainActor
    private func requestSmsCode() async {
        guard !phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            statusMessage = "请先填写手机号"
            return
        }
        isAuthLoading = true
        defer { isAuthLoading = false }
        do {
            let result = try await GatewayAuthClient.requestSms(
                gatewayUrl: authGatewayUrl(),
                phoneNumber: phoneNumber
            )
            statusMessage = "验证码已发送，\(result.retryAfterSeconds) 秒后可重试"
        } catch {
            statusMessage = "发送验证码失败：\(error.localizedDescription)"
        }
    }

    @MainActor
    private func verifySmsCode() async {
        guard !phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !smsCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            statusMessage = "请填写手机号和验证码"
            return
        }
        isAuthLoading = true
        defer { isAuthLoading = false }
        do {
            let session = try await GatewayAuthClient.verifySms(
                gatewayUrl: authGatewayUrl(),
                phoneNumber: phoneNumber,
                code: smsCode,
                terminalLabel: deviceLabel.isEmpty ? "我的设备" : deviceLabel,
                platform: "ios"
            )
            applyAuthSession(session)
            statusMessage = "登录成功"
        } catch {
            statusMessage = "登录失败：\(error.localizedDescription)"
        }
    }

    @MainActor
    private func changePassword() async {
        let accessToken = settingsManager.config.accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !accessToken.isEmpty else {
            statusMessage = "请先登录"
            return
        }
        guard !currentPassword.isEmpty,
              newPassword.count >= 8,
              newPassword == confirmNewPassword else {
            statusMessage = "请检查当前密码和两次新密码"
            return
        }
        isAuthLoading = true
        defer { isAuthLoading = false }
        do {
            let session = try await GatewayAuthClient.changePassword(
                gatewayUrl: authGatewayUrl(),
                accessToken: accessToken,
                currentPassword: currentPassword,
                newPassword: newPassword
            )
            applyAuthSession(session)
            statusMessage = "密码已修改"
        } catch {
            statusMessage = "修改密码失败：\(error.localizedDescription)"
        }
    }

    @MainActor
    private func logoutSession() async {
        isAuthLoading = true
        defer { isAuthLoading = false }
        do {
            let refreshToken = settingsManager.config.refreshToken.trimmingCharacters(in: .whitespacesAndNewlines)
            if !refreshToken.isEmpty {
                try await GatewayAuthClient.logout(
                    gatewayUrl: authGatewayUrl(),
                    refreshToken: refreshToken
                )
            }
        } catch {
            statusMessage = "退出登录失败：\(error.localizedDescription)"
            return
        }
        wsManager.disconnect()
        settingsManager.updateConfig(
            GatewayConfig(
                gatewayUrl: settingsManager.selectedProfile.gatewayUrl,
                accountId: "",
                accessToken: "",
                refreshToken: "",
                accessExpiresAt: "",
                refreshExpiresAt: "",
                deviceLabel: settingsManager.config.deviceLabel,
                token: settingsManager.selectedProfile.token,
                pairedBackendId: settingsManager.config.pairedBackendId,
                pairedBackendLabel: settingsManager.config.pairedBackendLabel,
                asrMode: asrMode,
                asrProfileId: asrMode == "router" ? asrProfileId : ""
            )
        )
        statusMessage = "已退出登录"
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

    private static func jsonRequest(
        url: String,
        gatewayUrl: String,
        body: [String: String],
        headers: [String: String] = [:]
    ) throws -> URLRequest {
        guard let baseURL = authBaseURL(from: gatewayUrl),
              let requestURL = URL(string: url, relativeTo: baseURL) else {
            throw GatewayAuthError(message: "Invalid gateway URL")
        }
        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        headers.forEach { key, value in
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
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
    let onAuthenticated: (GatewayAuthSessionResponse, String, String) -> Void
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

    var body: some View {
        ZStack {
            colors.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    AuthHeaderView(colors: colors)

                    VStack(alignment: .leading, spacing: 16) {
                        if authMode != .forgot {
                            Picker("认证", selection: $authMode) {
                                Text("登录").tag(AppAuthMode.login)
                                Text("注册").tag(AppAuthMode.register)
                            }
                            .pickerStyle(.segmented)

                            Divider()
                                .background(colors.divider)
                        }

                        switch authMode {
                        case .login:
                            loginFields
                        case .register:
                            registerFields
                        case .forgot:
                            forgotFields
                        }

                        Divider()
                            .background(colors.divider)

                        connectionFields
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
        VStack(alignment: .leading, spacing: 14) {
            Picker("登录方式", selection: $loginMode) {
                Text("密码").tag(AppLoginMode.password)
                Text("验证码").tag(AppLoginMode.sms)
            }
            .pickerStyle(.segmented)

            OutlinedTextField(
                label: "手机号",
                placeholder: "+8613800138000",
                text: $phoneNumber,
                colors: colors
            )

            if loginMode == .password {
                OutlinedSecureField(
                    label: "密码",
                    placeholder: "password",
                    text: $password,
                    colors: colors
                )
                primaryButton("密码登录", systemImage: "lock.fill") {
                    Task { await loginWithPassword() }
                }
                Button {
                    authMode = .forgot
                    smsCode = ""
                    password = ""
                    confirmPassword = ""
                } label: {
                    HStack(spacing: 5) {
                        Text("忘记密码")
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(colors.primary)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .buttonStyle(.plain)
            } else {
                smsCodeRow(purpose: "login")
                primaryButton("验证码登录", systemImage: "message.fill") {
                    Task { await loginWithSms() }
                }
            }
        }
    }

    private var registerFields: some View {
        VStack(alignment: .leading, spacing: 14) {
            OutlinedTextField(
                label: "手机号",
                placeholder: "+8613800138000",
                text: $phoneNumber,
                colors: colors
            )
            smsCodeRow(purpose: "register")
            OutlinedSecureField(label: "设置密码", placeholder: "password", text: $password, colors: colors)
            OutlinedSecureField(label: "确认密码", placeholder: "confirm password", text: $confirmPassword, colors: colors)
            primaryButton("注册并登录", systemImage: "person.badge.plus") {
                Task { await registerPassword() }
            }
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
            onAuthenticated(session, normalizedGatewayUrl(), normalizedTerminalLabel())
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
            onAuthenticated(session, normalizedGatewayUrl(), normalizedTerminalLabel())
        } catch {
            statusMessage = "登录失败：\(error.localizedDescription)"
        }
    }

    @MainActor
    private func registerPassword() async {
        guard !phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !smsCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              password.count >= 8,
              password == confirmPassword else {
            statusMessage = "请检查手机号、验证码和两次密码"
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
            onAuthenticated(session, normalizedGatewayUrl(), normalizedTerminalLabel())
        } catch {
            statusMessage = "注册失败：\(error.localizedDescription)"
        }
    }

    @MainActor
    private func resetPassword() async {
        guard !phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !smsCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              password.count >= 8,
              password == confirmPassword else {
            statusMessage = "请检查手机号、验证码和两次密码"
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
            onAuthenticated(session, normalizedGatewayUrl(), normalizedTerminalLabel())
        } catch {
            statusMessage = "重置失败：\(error.localizedDescription)"
        }
    }
}

private struct AuthHeaderView: View {
    let colors: MochiColors

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
                Text("OpenClaw Remote")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundColor(colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                Text("登录后连接你的 Agent")
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
