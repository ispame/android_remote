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
                appClientId: "",
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

            OutlinedTextField(
                label: "Token",
                placeholder: "配对 Token",
                text: $form.token,
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
        wsManager.applyProfile(settingsManager.selectedProfile, deviceLabel: settingsManager.config.deviceLabel)
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
            wsManager.applyProfile(settingsManager.selectedProfile, deviceLabel: settingsManager.config.deviceLabel)
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
        wsManager.applyProfile(profile, deviceLabel: settingsManager.config.deviceLabel)
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
            appClientId: settingsManager.baseDeviceId,
            platform: form.platform,
            displayName: displayName,
            gatewayUrl: gatewayUrl,
            backendId: backendId,
            backendLabel: backendLabel,
            token: form.token.trimmingCharacters(in: .whitespacesAndNewlines),
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
               form.backendId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               form.token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                continue
            }
            _ = saveForm(form, select: form.id == settingsManager.selectedProfileId)
        }
        settingsManager.updateDeviceLabel(deviceLabel)
        settingsManager.updateGlobalAsr(mode: asrMode, profileId: asrProfileId)
        wsManager.syncProfiles(settingsManager.profiles)
        wsManager.updateAsrConfiguration(mode: asrMode, profileId: asrProfileId)
        wsManager.applyProfile(settingsManager.selectedProfile, deviceLabel: settingsManager.config.deviceLabel)
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
}
