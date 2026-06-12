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
                NavigationLink {
                    ProviderChatScreen(
                        settingsManager: settingsManager,
                        audioRecorder: audioRecorder,
                        messageSpeechController: messageSpeechController,
                        colors: colors
                    )
                } label: {
                    AiProviderConversationRow(
                        choice: settingsManager.aiSettings.defaults.llm,
                        keyStatus: providerKeyStatus,
                        colors: colors
                    )
                }
            } header: {
                Text("AI Provider")
            }

            Section {
                if profiles.isEmpty {
                    Text("还没有连接的 Agent。点击右上角扫码添加。")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                } else {
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
    }

    private var providerKeyStatus: String {
        let choice = settingsManager.aiSettings.defaults.llm
        guard choice.mode == "byok" else { return "" }
        let provider = AiProviderCatalog.llmProvider(id: choice.providerId) ?? AiProviderCatalog.llmByokProviders[0]
        return settingsManager.localCredential(id: provider.credentialId) == nil ? "Key 未保存" : "Key 已保存"
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

private struct AiProviderConversationRow: View {
    let choice: AiServiceChoice
    let keyStatus: String
    let colors: MochiColors

    private var title: String {
        switch choice.mode {
        case "byok": return "AI Provider"
        case "agent": return "AI Provider · Agent 模式"
        default: return "AI Provider · Router"
        }
    }

    private var subtitle: String {
        switch choice.mode {
        case "byok":
            let provider = providerLabel
            let model = choice.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "未设置模型" : choice.model
            return "BYOK \(provider) · \(model) · \(keyStatus)"
        case "agent":
            return "当前 LLM 由 Agent 后端配置，不能在这里直聊"
        default:
            let profileId = choice.profileId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "default" : choice.profileId
            return "Router LLM · \(profileId)"
        }
    }

    private var providerLabel: String {
        let displayName = choice.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !displayName.isEmpty { return displayName }
        let providerId = choice.providerId.trimmingCharacters(in: .whitespacesAndNewlines)
        return providerId.isEmpty ? "Provider" : providerId
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(colors.accent.opacity(0.14))
                    .frame(width: 46, height: 46)
                Image(systemName: "sparkles")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(colors.accent)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)
        }
        .padding(.vertical, 6)
    }
}

private struct ProviderChatRecord: Identifiable, Codable, Equatable {
    var id: UUID
    var role: String
    var content: String
    var createdAt: Date

    init(id: UUID = UUID(), role: String, content: String, createdAt: Date = Date()) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
    }

    var isUser: Bool { role == "user" }
}

private enum ProviderChatHistoryStore {
    private static let key = "ai_provider_chat_history_v1"

    static func load() -> [ProviderChatRecord] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let records = try? JSONDecoder().decode([ProviderChatRecord].self, from: data) else {
            return []
        }
        return records
    }

    static func save(_ records: [ProviderChatRecord]) {
        guard let data = try? JSONEncoder().encode(records) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

private struct ProviderChatScreen: View {
    @ObservedObject var settingsManager: SettingsManager
    @ObservedObject var audioRecorder: AudioRecorder
    @ObservedObject var messageSpeechController: MessageSpeechController
    let colors: MochiColors

    @State private var records: [ProviderChatRecord] = ProviderChatHistoryStore.load()
    @State private var inputMode: InputMode = .voice
    @State private var isSending = false
    @State private var statusMessage: String?
    @State private var hasPositionedInitialRecords = false
    private let bottomAnchorId = "provider-chat-bottom"

    private var choice: AiServiceChoice {
        settingsManager.aiSettings.defaults.llm
    }

    private var provider: AiByokProviderTemplate {
        AiProviderCatalog.llmProvider(id: choice.providerId) ?? AiProviderCatalog.llmByokProviders[0]
    }

    private var subtitle: String {
        switch choice.mode {
        case "byok":
            let model = choice.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? provider.modelDefault : choice.model
            return "BYOK \(provider.label) · \(model)"
        case "agent":
            return "Agent 后端模式不可直聊"
        default:
            let profileId = choice.profileId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "default" : choice.profileId
            return "Router LLM · \(profileId)"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ProviderChatHeader(subtitle: subtitle, statusMessage: statusMessage, colors: colors)
            Divider().background(colors.divider)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        if records.isEmpty {
                            VStack(spacing: 10) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 28, weight: .semibold))
                                    .foregroundColor(colors.accent)
                                Text("和当前 LLM Provider 对话")
                                    .font(.system(size: 16, weight: .semibold))
                                Text("这里不连接 Agent，也不会改动 Agent 对话历史。")
                                    .font(.system(size: 13))
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 80)
                        }

                        ForEach(records) { record in
                            ProviderChatBubble(
                                record: record,
                                colors: colors,
                                onSpeak: {
                                    messageSpeechController.speakManualText(record.content, config: settingsManager.config)
                                }
                            )
                                .id(record.id)
                        }

                        if isSending {
                            HStack {
                                ProgressView()
                                Text("正在请求模型...")
                                    .font(.system(size: 13))
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                        }

                        Color.clear.frame(height: 1).id(bottomAnchorId)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
                .onChange(of: records.count) { _ in
                    withAnimation(.easeOut(duration: 0.18)) {
                        proxy.scrollTo(bottomAnchorId, anchor: .bottom)
                    }
                }
                .onAppear {
                    positionProviderChatAtBottom(proxy: proxy)
                }
            }

            Divider().background(colors.divider)
            InputAreaView(
                inputMode: $inputMode,
                isRecording: audioRecorder.isRecording,
                isPaired: choice.mode != "agent",
                isAudioEnabled: true,
                colors: colors,
                quotedMessageSummary: nil,
                onSendText: { text in
                    Task { await send(text) }
                },
                onCancelQuote: {},
                onMicPress: {
                    if !audioRecorder.isRecording {
                        audioRecorder.startRecording()
                    }
                },
                onMicRelease: { cancelled in
                    if audioRecorder.isRecording {
                        audioRecorder.stopRecording { data in
                            if !cancelled {
                                Task { await sendAudioUsingSelectedAsr(data) }
                            }
                        }
                    }
                },
                audioRecorder: audioRecorder
            )
            .disabled(isSending || choice.mode == "agent")
        }
        .background(colors.background.ignoresSafeArea())
        .navigationTitle("AI Provider")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 8) {
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
                    Button(role: .destructive) {
                        records = []
                        ProviderChatHistoryStore.clear()
                        statusMessage = nil
                    } label: {
                        Image(systemName: "trash")
                    }
                    .disabled(records.isEmpty)
                    .accessibilityLabel("清空 Provider 对话")
                }
            }
        }
        .hideTabBarWhileVisible()
        .onAppear {
            if choice.mode == "agent" {
                statusMessage = "当前 LLM 选择 Agent 模式，请到 AI 服务中切换 Router 或 BYOK 后直聊。"
            }
        }
    }

    private func positionProviderChatAtBottom(proxy: ScrollViewProxy) {
        guard !hasPositionedInitialRecords, !records.isEmpty else { return }

        DispatchQueue.main.async {
            guard !hasPositionedInitialRecords, !records.isEmpty else { return }

            var transaction = Transaction()
            transaction.animation = nil
            withTransaction(transaction) {
                proxy.scrollTo(bottomAnchorId, anchor: .bottom)
            }
            hasPositionedInitialRecords = true
        }
    }

    @MainActor
    private func send(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isSending else { return }
        guard choice.mode != "agent" else {
            statusMessage = "当前 LLM 选择 Agent 模式，请到 AI 服务中切换 Router 或 BYOK 后直聊。"
            return
        }

        records.append(ProviderChatRecord(role: "user", content: trimmed))
        persistHistory()
        isSending = true
        statusMessage = nil
        defer { isSending = false }

        do {
            let reply = try await requestReply()
            records.append(ProviderChatRecord(role: "assistant", content: reply))
            persistHistory()
            messageSpeechController.enqueueAssistantReplies(texts: [reply], config: settingsManager.config)
        } catch {
            statusMessage = "Provider 请求失败：\(error.localizedDescription)"
            persistHistory()
        }
    }

    @MainActor
    private func sendAudioUsingSelectedAsr(_ data: Data) async {
        let asr = settingsManager.aiSettings.defaults.asr
        guard asr.mode == "byok" else {
            statusMessage = "Provider 对话语音输入需要在 AI 服务中选择 BYOK ASR"
            inputMode = .text
            return
        }
        let credentialId = asr.credentialId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? localAsrOpenAICompatibleCredentialId
            : asr.credentialId
        guard let apiKey = settingsManager.localCredential(id: credentialId),
              !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            statusMessage = "请先在 AI 服务中保存 ASR API Key"
            return
        }
        statusMessage = "正在使用本机 ASR 识别..."
        do {
            let transcript = try await OpenAICompatibleAsrClient().transcribe(
                baseUrl: asr.baseUrl,
                apiKey: apiKey,
                model: asr.model,
                audioData: data
            )
            let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                statusMessage = "本机 ASR 没有识别到文本"
                return
            }
            statusMessage = nil
            await send(text)
        } catch {
            statusMessage = "本机 ASR 失败：\(error.localizedDescription)"
        }
    }

    private func requestReply() async throws -> String {
        let messages = records.suffix(24).map {
            OpenAICompatibleChatMessage(role: $0.role == "assistant" ? "assistant" : "user", content: $0.content)
        }

        if choice.mode == "router" {
            let accessToken = settingsManager.config.accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !accessToken.isEmpty else {
                throw ProviderChatError("请先登录账号后使用 Router LLM")
            }
            let profileId = choice.profileId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "default" : choice.profileId
            let response = try await GatewayAuthClient.aiChat(
                gatewayUrl: settingsManager.config.gatewayUrl,
                accessToken: accessToken,
                modelProfileId: profileId,
                messages: messages
            )
            return response.message.content
        }

        let apiKey = settingsManager.localCredential(id: provider.credentialId) ?? ""
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProviderChatError("请先在 AI 服务中保存 \(provider.label) API Key")
        }
        let baseUrl = choice.baseUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? provider.baseUrlDefault : choice.baseUrl
        let model = choice.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? provider.modelDefault : choice.model
        if provider.adapter == "anthropic-messages" || provider.apiStyle == "anthropic" {
            return try await AnthropicChatClient().chat(
                baseUrl: baseUrl,
                apiKey: apiKey,
                model: model,
                messages: messages
            )
        }
        return try await OpenAICompatibleChatClient().chat(
            baseUrl: baseUrl,
            apiKey: apiKey,
            model: model,
            messages: messages
        )
    }

    private func persistHistory() {
        ProviderChatHistoryStore.save(records)
    }
}

private struct ProviderChatHeader: View {
    let subtitle: String
    let statusMessage: String?
    let colors: MochiColors

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundColor(colors.accent)
                Text(subtitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(colors.textSecondary)
                    .lineLimit(2)
                Spacer(minLength: 0)
            }
            if let statusMessage {
                Text(statusMessage)
                    .font(.system(size: 12))
                    .foregroundColor(statusMessage.contains("失败") ? colors.recordingRed : colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(colors.surface)
    }
}

private struct ProviderChatBubble: View {
    let record: ProviderChatRecord
    let colors: MochiColors
    let onSpeak: () -> Void

    var body: some View {
        HStack(alignment: .top) {
            if record.isUser {
                Spacer(minLength: 32)
            }
            Text(record.content)
                .font(.system(size: 15))
                .foregroundColor(record.isUser ? colors.userBubbleFg : colors.assistantFg)
                .textSelection(.enabled)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedCornerShape(
                        topLeft: record.isUser ? 16 : 4,
                        topRight: record.isUser ? 4 : 16,
                        bottomLeft: 16,
                        bottomRight: 16
                    )
                    .fill(record.isUser ? colors.userBubble : colors.assistantBg)
                )
                .frame(maxWidth: min(UIScreen.main.bounds.width * 0.76, 560), alignment: record.isUser ? .trailing : .leading)
                .contextMenu {
                    Button {
                        UIPasteboard.general.string = record.content
                    } label: {
                        Label("复制", systemImage: "doc.on.doc")
                    }
                    Button(action: onSpeak) {
                        Label("朗读", systemImage: "speaker.wave.2")
                    }
                }
            if !record.isUser {
                Spacer(minLength: 32)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct ProviderChatError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { message }
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
                    settingsManager: settingsManager,
                    colors: colors,
                    onSave: saveProfile
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

}

private struct AgentConfigView: View {
    let profile: AgentProfile
    @ObservedObject var settingsManager: SettingsManager
    let colors: MochiColors
    let onSave: (AgentProfile) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var displayName: String
    @State private var gatewayUrl: String
    @State private var backendId: String
    @State private var token: String
    @State private var showsToken = false

    init(
        profile: AgentProfile,
        settingsManager: SettingsManager,
        colors: MochiColors,
        onSave: @escaping (AgentProfile) -> Void
    ) {
        self.profile = profile
        _settingsManager = ObservedObject(wrappedValue: settingsManager)
        self.colors = colors
        self.onSave = onSave
        _displayName = State(initialValue: profile.resolvedDisplayName)
        _gatewayUrl = State(initialValue: profile.gatewayUrl)
        _backendId = State(initialValue: profile.backendId)
        _token = State(initialValue: profile.token)
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
                let resolved = settingsManager.aiSettings.resolved(for: profile.id)
                AiServiceInfoRow(label: "LLM", value: llmSummary(resolved.llm))
                AiServiceInfoRow(label: "ASR", value: asrSummary(resolved.asr))
                AiServiceInfoRow(label: "TTS", value: ttsSummary(resolved.tts))
                AIServiceNavigationLink(settingsManager: settingsManager, colors: colors)
            }
        }
        .navigationTitle("Agent 配置")
        .navigationBarTitleDisplayMode(.inline)
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

    private func saveAllConfigurationAndDismiss() {
        var updated = profile
        updated.displayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.gatewayUrl = gatewayUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.backendId = backendId.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.updatedAt = Date()
        onSave(updated)
        dismiss()
    }

    private func llmSummary(_ choice: AiServiceChoice) -> String {
        switch choice.mode {
        case "byok": return "BYOK \(providerLabel(choice)) · \(choice.model.isEmpty ? "gpt-4o-mini" : choice.model)"
        case "agent": return "Agent 后端"
        default: return "Router · \(choice.profileId.isEmpty ? "default" : choice.profileId)"
        }
    }

    private func asrSummary(_ choice: AiServiceChoice) -> String {
        switch choice.mode {
        case "byok": return "BYOK \(providerLabel(choice)) · \(choice.model.isEmpty ? "whisper-1" : choice.model)"
        case "backend": return "Agent 后端"
        default: return "Router · \(choice.profileId.isEmpty ? "默认" : choice.profileId)"
        }
    }

    private func ttsSummary(_ choice: AiServiceChoice) -> String {
        switch choice.mode {
        case "router":
            return "Router TTS"
        case "byok":
            return "\(providerLabel(choice)) · \(choice.voiceId.isEmpty ? MiniMaxVoiceCatalog.defaultVoiceId : choice.voiceId)"
        default:
            return "系统 TTS"
        }
    }

    private func providerLabel(_ choice: AiServiceChoice) -> String {
        let displayName = choice.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !displayName.isEmpty { return displayName }
        let providerId = choice.providerId.trimmingCharacters(in: .whitespacesAndNewlines)
        return providerId.isEmpty ? "BYOK" : providerId
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
