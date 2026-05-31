import SwiftUI

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
    }

    private var accountTitle: String {
        let accountId = settingsManager.config.accountId.trimmingCharacters(in: .whitespacesAndNewlines)
        return accountId.isEmpty ? "未登录" : maskedAccountLabel(accountId)
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

    private func maskedAccountLabel(_ accountId: String) -> String {
        let value = accountId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.count > 12 else { return value }
        return "\(value.prefix(8))...\(value.suffix(4))"
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
