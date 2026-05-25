import SwiftUI

struct SimpleSettingsTabView: View {
    @ObservedObject var wsManager: WebSocketManager
    @ObservedObject var settingsManager: SettingsManager
    let isDark: Bool
    let colors: MochiColors
    let onToggleTheme: () -> Void
    let onRequestPair: (String) -> Void
    let onSelectProfile: (String) -> Void
    let onSwitchAccount: () -> Void
    let onLogout: () -> Void
    @State private var showAdvancedSettings = false
    @State private var showRecordingSettings = false

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

                Button {
                    showAdvancedSettings = true
                } label: {
                    HStack {
                        Label("高级设置", systemImage: "slider.horizontal.3")
                        Spacer()
                    }
                }
                .foregroundColor(.primary)

                Button {
                    showRecordingSettings = true
                } label: {
                    HStack {
                        Label("录音设置", systemImage: "waveform")
                        Spacer()
                    }
                }
                .foregroundColor(.primary)
            }

            Section(
                header: Text("账号"),
                footer: Text("切换账号和退出登录会清除当前登录态，但保留本机 Agent、任务、录音和耳机配置。")
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
        .sheet(isPresented: $showAdvancedSettings) {
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
                onBack: {
                    showAdvancedSettings = false
                },
                onNavigateToQRScanner: {},
                onSelectProfile: onSelectProfile
            )
        }
        .sheet(isPresented: $showRecordingSettings) {
            CompatibleNavigationStack {
                RecordingSettingsView(
                    settingsManager: settingsManager,
                    colors: colors,
                    onClose: {
                        showRecordingSettings = false
                    }
                )
            }
        }
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
    let onClose: () -> Void

    @State private var draft = RecordingSettings()
    @State private var asrProfiles: [AsrProviderProfile] = []
    @State private var statusMessage: String?

    private var configuredProfiles: [AgentProfile] {
        settingsManager.profiles.filter { !$0.backendId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    var body: some View {
        Form {
            Section("投递") {
                if configuredProfiles.isEmpty {
                    Text("请先配置 Agent")
                        .foregroundColor(.secondary)
                } else {
                    Picker("主 Agent", selection: $draft.primaryAgentProfileId) {
                        ForEach(configuredProfiles) { profile in
                            Text(profile.resolvedDisplayName).tag(profile.id)
                        }
                    }
                    Toggle("发送给 Agent", isOn: $draft.deliverToAgent)
                }
            }

            Section("录音 Prompt") {
                TextEditor(text: $draft.prompt)
                    .frame(minHeight: 140)
                Button("恢复默认 Prompt") {
                    draft.prompt = RecordingSettings.defaultPrompt
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
            ToolbarItem(placement: .navigationBarLeading) {
                Button("取消", action: onClose)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("保存") {
                    save()
                }
                .disabled(configuredProfiles.isEmpty)
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
            onClose()
        }
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
                if draft.asrProfileId.isEmpty {
                    draft.asrProfileId = defaultProfileId ?? profiles.first?.id ?? ""
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
