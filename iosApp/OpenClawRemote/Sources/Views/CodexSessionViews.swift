import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct CodexSessionListScreen: View {
    let profileId: String
    @ObservedObject var wsManager: WebSocketManager
    @ObservedObject var settingsManager: SettingsManager
    @ObservedObject var audioRecorder: AudioRecorder
    let colors: MochiColors
    let onSelectProfile: (String) -> Void

    @State private var groupingMode: CodexSessionGroupingMode = .time
    @State private var showingArchived = false
    @State private var searchText = ""
    @State private var showConfig = false
    @State private var pendingNavigationSession: CodexSessionSummary?
    @State private var handledCreatedSessionId: String?

    private var profile: AgentProfile {
        settingsManager.profiles.first { $0.id == profileId }
            ?? AgentProfile(
                platform: .codex,
                displayName: "Codex",
                gatewayUrl: AgentProfile.canonicalWebSocketGatewayUrl(""),
                backendId: "",
                backendLabel: nil
            )
    }

    private var sessions: [CodexSessionSummary] {
        let loaded = wsManager.codexSessions(profileId: profileId, archived: showingArchived)
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return loaded }
        return loaded.filter { session in
            [
                session.displayTitle,
                session.displayPreview,
                session.displayProjectName,
                session.projectPath,
                session.model ?? ""
            ]
            .joined(separator: " ")
            .lowercased()
            .contains(query)
        }
    }

    private var groups: [CodexSessionGroup] {
        CodexSessionGrouping.groups(for: sessions, mode: groupingMode)
    }

    private var codexEndpointLabel: String {
        let backendLabel = profile.backendLabel?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let backendId = profile.backendId.trimmingCharacters(in: .whitespacesAndNewlines)
        if !backendLabel.isEmpty && backendLabel.lowercased() != "hermes bosonrelay" {
            return backendLabel
        }
        if backendId == "codex-mac-mini" {
            return "Mac-mini.local"
        }
        return backendId.isEmpty ? "Codex" : backendId
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            List {
                if groups.isEmpty {
                    Text(showingArchived ? "没有已归档会话" : "还没有 Codex 会话")
                        .font(.system(size: 14))
                        .foregroundColor(colors.textSecondary)
                } else {
                    ForEach(groups) { group in
                        Section(group.title) {
                            ForEach(group.sessions) { session in
                                NavigationLink {
                                    CodexSessionChatScreen(
                                        profileId: profileId,
                                        session: session,
                                        wsManager: wsManager,
                                        settingsManager: settingsManager,
                                        audioRecorder: audioRecorder,
                                        colors: colors,
                                        onSelectProfile: onSelectProfile
                                    )
                                } label: {
                                    CodexSessionRow(session: session, colors: colors)
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    if showingArchived {
                                        Button {
                                            wsManager.unarchiveCodexSession(profileId: profileId, sessionId: session.sessionId)
                                        } label: {
                                            Label("取消归档", systemImage: "tray.and.arrow.up")
                                        }
                                        .tint(.green)
                                    } else {
                                        Button {
                                            wsManager.archiveCodexSession(profileId: profileId, sessionId: session.sessionId)
                                        } label: {
                                            Label("归档", systemImage: "archivebox")
                                        }
                                        .tint(.orange)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
        }
        .background(colors.background)
        .navigationTitle("Codex")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                menu
            }
        }
        .safeAreaInset(edge: .bottom) {
            bottomControls
        }
        .background(createdSessionNavigationLink)
        .hideTabBarWhileVisible()
        .onAppear {
            onSelectProfile(profileId)
            requestSessionsOrPair()
        }
        .onChange(of: showingArchived) { archived in
            requestSessionsOrPair(archived: archived)
        }
        .onChange(of: wsManager.codexCreatedSessionIdsByProfile[profileId]) { sessionId in
            guard let sessionId,
                  sessionId != handledCreatedSessionId else { return }
            handledCreatedSessionId = sessionId
            pendingNavigationSession = wsManager.codexSessions(profileId: profileId)
                .first { $0.sessionId == sessionId }
                ?? CodexSessionSummary(
                    sessionId: sessionId,
                    title: "新会话",
                    preview: "",
                    lastAssistantPreview: "",
                    projectPath: "",
                    projectName: nil,
                    createdAt: "",
                    updatedAt: "",
                    status: "idle",
                    archived: false,
                    model: nil
                )
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

    private var header: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                StatusDot(color: wsManager.availabilityStatus(for: profile) == .available ? colors.onlineGreen : colors.textSecondary)
                Image(systemName: "laptopcomputer")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(colors.textSecondary)
                Text(codexEndpointLabel)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(colors.textSecondary)
                    .lineLimit(1)
            }
            if let error = wsManager.codexSessionErrorsByProfile[profileId], !error.isEmpty {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundColor(colors.recordingRed)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    private var menu: some View {
        Menu {
            Button {
                groupingMode = .project
            } label: {
                Label("按项目", systemImage: groupingMode == .project ? "checkmark" : "folder")
            }
            Button {
                groupingMode = .time
            } label: {
                Label("按时间顺序排列的列表", systemImage: groupingMode == .time ? "checkmark" : "clock.arrow.circlepath")
            }
            Button {
                showingArchived.toggle()
            } label: {
                Label(showingArchived ? "当前会话" : "已归档会话", systemImage: "archivebox")
            }
            Button {
                showConfig = true
            } label: {
                Label("设置", systemImage: "gearshape")
            }
        } label: {
            Image(systemName: "ellipsis.circle.fill")
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(colors.icon)
        }
        .accessibilityLabel("Codex 会话菜单")
    }

    private var bottomControls: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(colors.textSecondary)
                TextField("搜索聊天记录", text: $searchText)
                    .font(.system(size: 15))
                    .foregroundColor(colors.inputText)
            }
            .padding(.horizontal, 14)
            .frame(height: 48)
            .background(
                RoundedRectangle(cornerRadius: 22)
                    .fill(colors.inputBg)
                    .overlay(
                        RoundedRectangle(cornerRadius: 22)
                            .strokeBorder(colors.inputBorder, lineWidth: 1)
                    )
            )

            Button {
                wsManager.createCodexSession(profileId: profileId)
            } label: {
                Label("聊天", systemImage: "square.and.pencil")
                    .font(.system(size: 15, weight: .semibold))
            }
            .frame(height: 48)
            .padding(.horizontal, 16)
            .background(Capsule().fill(colors.primary))
            .foregroundColor(colors.onPrimary)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(colors.background)
    }

    private var createdSessionNavigationLink: some View {
        NavigationLink(isActive: Binding(
            get: { pendingNavigationSession != nil },
            set: { isActive in
                if !isActive {
                    pendingNavigationSession = nil
                }
            }
        )) {
            if let session = pendingNavigationSession {
                CodexSessionChatScreen(
                    profileId: profileId,
                    session: session,
                    wsManager: wsManager,
                    settingsManager: settingsManager,
                    audioRecorder: audioRecorder,
                    colors: colors,
                    onSelectProfile: onSelectProfile
                )
            } else {
                EmptyView()
            }
        } label: {
            EmptyView()
        }
        .hidden()
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

    private func requestSessionsOrPair(archived: Bool? = nil) {
        let targetArchived = archived ?? showingArchived
        if wsManager.requestCodexSessions(profileId: profileId, archived: targetArchived) {
            return
        }
        let backendId = profile.backendId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !backendId.isEmpty else { return }
        wsManager.requestPair(backendId: backendId)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            _ = wsManager.requestCodexSessions(profileId: profileId, archived: targetArchived)
        }
    }
}

private struct CodexSessionRow: View {
    let session: CodexSessionSummary
    let colors: MochiColors

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(session.displayTitle)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(colors.textPrimary)
                    .lineLimit(1)
                if let model = session.model, !model.isEmpty {
                    Text(model)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(colors.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
            }
            Text(session.displayPreview)
                .font(.system(size: 13))
                .foregroundColor(colors.textSecondary)
                .lineLimit(1)
            HStack(spacing: 6) {
                Image(systemName: "folder")
                    .font(.system(size: 11, weight: .medium))
                Text(session.displayProjectName)
                    .lineLimit(1)
            }
            .font(.system(size: 12))
            .foregroundColor(colors.textSecondary)
        }
        .padding(.vertical, 6)
    }
}

struct CodexSessionChatScreen: View {
    let profileId: String
    let session: CodexSessionSummary
    @ObservedObject var wsManager: WebSocketManager
    @ObservedObject var settingsManager: SettingsManager
    @ObservedObject var audioRecorder: AudioRecorder
    let colors: MochiColors
    let onSelectProfile: (String) -> Void

    @State private var inputMode: InputMode = .text
    @State private var isNearChatBottom = true
    @State private var quotedMessageSummary: String?
    private let bottomAnchorId = "codex-chat-bottom-anchor"

    private var messages: [ChatMessage] {
        wsManager.codexMessages(profileId: profileId, sessionId: session.sessionId)
    }

    private var profile: AgentProfile {
        settingsManager.profiles.first { $0.id == profileId } ?? settingsManager.selectedProfile
    }

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            if messages.isEmpty {
                                VStack(spacing: 10) {
                                    Image(systemName: "circle.hexagongrid.fill")
                                        .font(.system(size: 30, weight: .semibold))
                                        .foregroundColor(colors.textSecondary)
                                    Text("开始 Codex 会话")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(colors.textSecondary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.top, 80)
                            }

                            ForEach(messages) { message in
                                CodexSessionMessageRow(message: message, colors: colors) {
                                    quotedMessageSummary = quoteSummary(for: message.content)
                                    inputMode = .text
                                }
                            }

                            Color.clear
                                .frame(height: 1)
                                .id(bottomAnchorId)
                                .background(
                                    GeometryReader { bottomGeometry in
                                        Color.clear.preference(
                                            key: CodexChatBottomPositionPreferenceKey.self,
                                            value: bottomGeometry.frame(in: .named("codexChatScroll")).maxY
                                        )
                                    }
                                )
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 16)
                    }
                    .coordinateSpace(name: "codexChatScroll")
                    .onPreferenceChange(CodexChatBottomPositionPreferenceKey.self) { bottomY in
                        isNearChatBottom = bottomY - geometry.size.height <= 120
                    }
                    .onChange(of: messages.last?.id) { _ in
                        if isNearChatBottom || messages.last?.isUser == true {
                            withAnimation(.easeOut(duration: 0.2)) {
                                proxy.scrollTo(bottomAnchorId, anchor: .bottom)
                            }
                        }
                    }
                    .onAppear {
                        DispatchQueue.main.async {
                            proxy.scrollTo(bottomAnchorId, anchor: .bottom)
                        }
                    }
                    .refreshable {
                        wsManager.requestCodexHistory(profileId: profileId, sessionId: session.sessionId, force: true)
                    }
                }
            }

            InputAreaView(
                inputMode: $inputMode,
                isRecording: false,
                isPaired: wsManager.availabilityStatus(for: profile) == .available,
                isAudioEnabled: false,
                colors: colors,
                quotedMessageSummary: quotedMessageSummary,
                onSendText: { text in
                    let outgoingText = quotedMessageSummary.map { "> \($0)\n\n\(text)" } ?? text
                    wsManager.sendCodexText(outgoingText, profileId: profileId, sessionId: session.sessionId)
                    quotedMessageSummary = nil
                },
                onCancelQuote: {
                    quotedMessageSummary = nil
                },
                onMicPress: {},
                onMicRelease: { _ in },
                audioRecorder: audioRecorder
            )
        }
        .background(colors.background)
        .navigationTitle(session.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .hideTabBarWhileVisible()
        .onAppear {
            inputMode = .text
            onSelectProfile(profileId)
            wsManager.requestCodexHistory(profileId: profileId, sessionId: session.sessionId)
        }
    }

    private func quoteSummary(for content: String) -> String {
        let compact = content
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        if compact.count <= 300 {
            return compact
        }
        let endIndex = compact.index(compact.startIndex, offsetBy: 300)
        return String(compact[..<endIndex]) + "..."
    }
}

private struct CodexSessionMessageRow: View {
    let message: ChatMessage
    let colors: MochiColors
    let onQuote: () -> Void

    var body: some View {
        MessageBubbleView(
            message: message,
            colors: colors,
            isSelectionMode: false,
            isSelected: false,
            onTap: {},
            onCopy: {
                UIPasteboard.general.string = message.content
            },
            onQuote: onQuote,
            onSelect: {},
            onSpeak: {},
            onApprovalCommand: { _ in },
            isApprovalHandled: false,
            onInspectApprovalCode: { _ in },
            onCopyTable: { table in
                UIPasteboard.general.string = table.markdownSource
            },
            onDownloadTable: { table in
                UIPasteboard.general.string = table.csvSource
            },
            onFullscreenTable: { _ in }
        )
    }
}

private struct CodexChatBottomPositionPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = .zero

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
