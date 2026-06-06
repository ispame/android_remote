import SwiftUI
import UIKit

struct AgentsTabView: View {
    @ObservedObject var wsManager: WebSocketManager
    @ObservedObject var settingsManager: SettingsManager
    @ObservedObject var audioRecorder: AudioRecorder
    @ObservedObject var headsetController: HeadsetConversationController
    @ObservedObject var messageSpeechController: MessageSpeechController
    let isDark: Bool
    let colors: MochiColors
    let onToggleTheme: () -> Void
    let onSelectProfile: (String) -> Void
    let onRequestScan: () -> Void

    private var profiles: [AgentProfile] {
        let sorted = settingsManager.profiles.sortedForAgentList(
            unreadCounts: wsManager.unreadCounts,
            activities: wsManager.agentListActivities
        )
        if sorted.count == 1,
           sorted[0].backendId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           sorted[0].token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return []
        }
        return sorted
    }

    var body: some View {
        List {
            Section {
                ForEach(profiles) { profile in
                    NavigationLink(
                        destination: AgentChatScreen(
                            profileId: profile.id,
                            wsManager: wsManager,
                            settingsManager: settingsManager,
                            audioRecorder: audioRecorder,
                            headsetController: headsetController,
                            messageSpeechController: messageSpeechController,
                            isDark: isDark,
                            colors: colors,
                            onToggleTheme: onToggleTheme,
                            onSelectProfile: onSelectProfile
                        )
                    ) {
                        AgentRowView(
                            profile: profile,
                            status: wsManager.availabilityStatus(for: profile),
                            unreadCount: wsManager.unreadCount(for: profile.id),
                            activity: wsManager.agentListActivities[profile.id],
                            colors: colors
                        )
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            delete(profile)
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                        Button {
                            settingsManager.setProfilePinned(profile.id, isPinned: !profile.isPinned)
                        } label: {
                            Label(profile.isPinned ? "取消置顶" : "置顶", systemImage: "pin.fill")
                        }
                        .tint(.orange)
                    }
                    .onAppear {
                        wsManager.syncProfiles(settingsManager.profiles)
                    }
                }
            } header: {
                Text("已连接的 Agent")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Agent")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: onRequestScan) {
                    Text("扫码添加")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(colors.textSecondary)
                }
            }
        }
        .overlay {
            if profiles.isEmpty {
                EmptyStateView(
                    systemName: "qrcode.viewfinder",
                    title: "还没有 Agent",
                    message: "点击右上角扫码添加 Agent。"
                )
            }
        }
    }

    private func delete(_ profile: AgentProfile) {
        if settingsManager.profiles.count <= 1 {
            settingsManager.clearProfile(profile.id)
            wsManager.clearProfileState(profileId: profile.id)
        } else {
            settingsManager.deleteProfile(profile.id)
            wsManager.removeProfileState(profileId: profile.id)
        }
        wsManager.syncProfiles(settingsManager.profiles)
        onSelectProfile(settingsManager.selectedProfile.id)
    }
}

private struct AgentRowView: View {
    let profile: AgentProfile
    let status: AgentAvailabilityStatus
    let unreadCount: Int
    let activity: AgentListActivity?
    let colors: MochiColors

    private var statusColor: Color {
        switch status {
        case .available: return colors.onlineGreen
        case .pairing, .connecting: return colors.accent
        case .unconfigured, .unpaired: return colors.textSecondary
        case .offline: return colors.recordingRed
        }
    }

    private var recentPreview: String {
        let preview = activity?.latestMessagePreview?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return preview?.isEmpty == false ? preview! : "暂无对话"
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                Circle()
                    .fill(colors.primary.opacity(0.14))
                    .frame(width: 46, height: 46)
                Image(systemName: profile.platform.iconName)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(colors.primary)
                    .frame(width: 46, height: 46)
                StatusDot(color: statusColor)
                    .background(Circle().fill(Color(.systemBackground)).frame(width: 12, height: 12))
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(profile.resolvedDisplayName)
                        .font(.system(size: 16, weight: .semibold))
                        .lineLimit(1)
                    if profile.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.orange)
                    }
                    if unreadCount > 0 {
                        Circle()
                            .fill(colors.recordingRed)
                            .frame(width: 8, height: 8)
                    }
                }
                Text("\(profile.platform.label) · \(status.label)")
                    .font(.system(size: 12))
                    .foregroundColor(statusColor)
                Text(recentPreview)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)
        }
        .padding(.vertical, 6)
    }
}

private struct AgentChatScreen: View {
    let profileId: String
    @ObservedObject var wsManager: WebSocketManager
    @ObservedObject var settingsManager: SettingsManager
    @ObservedObject var audioRecorder: AudioRecorder
    @ObservedObject var headsetController: HeadsetConversationController
    @ObservedObject var messageSpeechController: MessageSpeechController
    let isDark: Bool
    let colors: MochiColors
    let onToggleTheme: () -> Void
    let onSelectProfile: (String) -> Void

    @State private var showConfig = false

    private var profile: AgentProfile {
        settingsManager.profiles.first { $0.id == profileId } ?? settingsManager.selectedProfile
    }

    var body: some View {
        MainScreenView(
            wsManager: wsManager,
            settingsManager: settingsManager,
            audioRecorder: audioRecorder,
            headsetController: headsetController,
            messageSpeechController: messageSpeechController,
            isDark: isDark,
            colors: colors,
            onToggleTheme: onToggleTheme,
            onNavigateToSettings: { showConfig = true },
            onSelectProfile: onSelectProfile,
            showsTopBar: false,
            showsHeadsetStrip: true
        )
        .navigationTitle(profile.resolvedDisplayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 8) {
                    playbackControls
                    Button {
                        showConfig = true
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("Agent 配置")
                }
            }
        }
        .hideTabBarWhileVisible()
        .onAppear {
            onSelectProfile(profileId)
        }
        .sheet(isPresented: $showConfig) {
            CompatibleNavigationStack {
                AgentConfigView(
                    profile: profile,
                    colors: colors,
                    onSave: saveProfile,
                    onTtsAutoSave: saveTtsProfile
                )
            }
        }
    }

    private var playbackControls: some View {
        PlaybackControlsView(
            soundPlaybackEnabled: messageSpeechController.soundPlaybackEnabled,
            isPlaybackSpeaking: messageSpeechController.isSpeaking,
            colors: colors,
            onToggleSoundPlayback: {
                messageSpeechController.setSoundPlaybackEnabled(!messageSpeechController.soundPlaybackEnabled)
            },
            onInterruptPlayback: {
                messageSpeechController.interruptCurrentPlayback()
            }
        )
    }

    private func saveProfile(_ profile: AgentProfile) {
        guard settingsManager.saveProfile(profile, select: true) else { return }
        wsManager.syncProfiles(settingsManager.profiles)
        wsManager.applyProfile(
            settingsManager.selectedProfile,
            deviceLabel: settingsManager.config.deviceLabel,
            accessToken: settingsManager.config.accessToken
        )
    }

    private func saveTtsProfile(_ profile: AgentProfile) {
        settingsManager.updateProfile(profile)
        wsManager.syncProfiles(settingsManager.profiles)
    }
}

private struct AgentConfigView: View {
    let profile: AgentProfile
    let colors: MochiColors
    let onSave: (AgentProfile) -> Void
    let onTtsAutoSave: (AgentProfile) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var displayName: String
    @State private var gatewayUrl: String
    @State private var backendId: String
    @State private var token: String
    @State private var ttsEngine: String
    @State private var minimaxApiKey: String
    @State private var minimaxVoiceId: String
    @State private var fetchedMiniMaxVoices: [MiniMaxVoiceOption] = []
    @State private var isRefreshingMiniMaxVoices = false
    @State private var ttsStatusMessage: String?
    @State private var lastPersistedTtsEngine: String
    @State private var lastPersistedMiniMaxApiKey: String
    @State private var lastPersistedMiniMaxVoiceId: String
    @State private var didCommitFullSave = false
    @State private var showsToken = false

    init(
        profile: AgentProfile,
        colors: MochiColors,
        onSave: @escaping (AgentProfile) -> Void,
        onTtsAutoSave: @escaping (AgentProfile) -> Void
    ) {
        self.profile = profile
        self.colors = colors
        self.onSave = onSave
        self.onTtsAutoSave = onTtsAutoSave
        _displayName = State(initialValue: profile.resolvedDisplayName)
        _gatewayUrl = State(initialValue: profile.gatewayUrl)
        _backendId = State(initialValue: profile.backendId)
        _token = State(initialValue: profile.token)
        _ttsEngine = State(initialValue: profile.ttsEngine.isEmpty ? "system" : profile.ttsEngine)
        _minimaxApiKey = State(initialValue: profile.minimaxApiKey)
        _minimaxVoiceId = State(initialValue: profile.minimaxVoiceId.isEmpty ? MiniMaxVoiceCatalog.defaultVoiceId : profile.minimaxVoiceId)
        _lastPersistedTtsEngine = State(initialValue: Self.normalizedTtsEngine(profile.ttsEngine))
        _lastPersistedMiniMaxApiKey = State(initialValue: profile.minimaxApiKey.trimmingCharacters(in: .whitespacesAndNewlines))
        _lastPersistedMiniMaxVoiceId = State(initialValue: Self.normalizedMiniMaxVoiceId(profile.minimaxVoiceId))
    }

    var body: some View {
        Form {
            Section("Agent") {
                TextField("Agent 名称", text: $displayName)
                TextField("URL", text: $gatewayUrl)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("backend ID", text: $backendId)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            Section("Agent 连接 Token") {
                HStack {
                    if showsToken {
                        TextField("Token", text: $token)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    } else {
                        SecureField("Token", text: $token)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    Button {
                        showsToken.toggle()
                    } label: {
                        Image(systemName: showsToken ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.borderless)
                }

                HStack {
                    Button("复制") {
                        UIPasteboard.general.string = token
                    }
                    Spacer()
                    Button("粘贴") {
                        token = UIPasteboard.general.string ?? token
                    }
                }
            }

            Section("AI 服务") {
                AiServiceInfoRow(label: "Router LLM", value: "会员模型 · default")
                AiServiceInfoRow(label: "ASR", value: profile.asrMode == "backend" ? "Agent 后端识别" : "Router 识别")

                Picker("TTS 引擎", selection: $ttsEngine) {
                    Text("系统 TTS").tag("system")
                    Text("MiniMax").tag("minimax")
                }
                .pickerStyle(.segmented)

                if ttsEngine == "minimax" {
                    AiServiceInfoRow(label: "本机 Key", value: minimaxApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "未保存" : "已保存")
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
                }

                if let ttsStatusMessage {
                    Text(ttsStatusMessage)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle("Agent 配置")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: ttsEngine) { _ in persistTtsConfigurationIfChanged() }
        .onChange(of: minimaxApiKey) { _ in persistTtsConfigurationIfChanged() }
        .onChange(of: minimaxVoiceId) { _ in persistTtsConfigurationIfChanged() }
        .onDisappear { persistTtsConfigurationIfChanged() }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    saveAllConfigurationAndDismiss()
                }
            }
        }
    }

    private var minimaxVoices: [MiniMaxVoiceOption] {
        MiniMaxVoiceCatalog.buildSelectableVoices(
            currentVoiceId: minimaxVoiceId,
            fetchedVoices: fetchedMiniMaxVoices
        )
    }

    private func voiceLabel(_ voice: MiniMaxVoiceOption) -> String {
        voice.name == voice.id ? voice.id : "\(voice.name) · \(voice.id)"
    }

    private func saveAllConfigurationAndDismiss() {
        var updated = profile
        updated.displayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.gatewayUrl = gatewayUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.backendId = backendId.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        applyCurrentTtsConfiguration(to: &updated)
        updated.updatedAt = Date()
        didCommitFullSave = true
        markTtsConfigurationPersisted(
            engine: updated.ttsEngine,
            apiKey: updated.minimaxApiKey,
            voiceId: updated.minimaxVoiceId
        )
        onSave(updated)
        dismiss()
    }

    private func persistTtsConfigurationIfChanged() {
        guard !didCommitFullSave else { return }
        let normalizedEngine = Self.normalizedTtsEngine(ttsEngine)
        let normalizedApiKey = minimaxApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedVoiceId = Self.normalizedMiniMaxVoiceId(minimaxVoiceId)
        guard normalizedEngine != lastPersistedTtsEngine ||
                normalizedApiKey != lastPersistedMiniMaxApiKey ||
                normalizedVoiceId != lastPersistedMiniMaxVoiceId else {
            return
        }

        var updated = profile
        updated.ttsEngine = normalizedEngine
        updated.minimaxApiKey = normalizedApiKey
        updated.minimaxVoiceId = normalizedVoiceId
        updated.updatedAt = Date()
        onTtsAutoSave(updated)
        markTtsConfigurationPersisted(
            engine: normalizedEngine,
            apiKey: normalizedApiKey,
            voiceId: normalizedVoiceId
        )
    }

    private func applyCurrentTtsConfiguration(to profile: inout AgentProfile) {
        profile.ttsEngine = Self.normalizedTtsEngine(ttsEngine)
        profile.minimaxApiKey = minimaxApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.minimaxVoiceId = Self.normalizedMiniMaxVoiceId(minimaxVoiceId)
    }

    private func markTtsConfigurationPersisted(engine: String, apiKey: String, voiceId: String) {
        lastPersistedTtsEngine = engine
        lastPersistedMiniMaxApiKey = apiKey
        lastPersistedMiniMaxVoiceId = voiceId
    }

    private static func normalizedTtsEngine(_ value: String) -> String {
        value == "minimax" ? "minimax" : "system"
    }

    private static func normalizedMiniMaxVoiceId(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? MiniMaxVoiceCatalog.defaultVoiceId : trimmed
    }

    @MainActor
    private func refreshMiniMaxVoices() async {
        guard !minimaxApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            ttsStatusMessage = "请先填写 MiniMax API Key"
            return
        }
        isRefreshingMiniMaxVoices = true
        defer { isRefreshingMiniMaxVoices = false }
        do {
            fetchedMiniMaxVoices = try await MiniMaxVoiceCatalog.fetchAvailableVoices(apiKey: minimaxApiKey)
            ttsStatusMessage = "已刷新 \(fetchedMiniMaxVoices.count) 个 MiniMax 音色"
        } catch {
            ttsStatusMessage = "刷新音色失败：\(error.localizedDescription)"
        }
    }
}

private struct AiServiceInfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
    }
}
