import SwiftUI

struct TopBarView: View {
    let connectionState: ConnectionState
    let selectedProfile: AgentProfile
    let profiles: [AgentProfile]
    let profileStatuses: [String: AgentAvailabilityStatus]
    let unreadCounts: [String: Int]
    let isDark: Bool
    let colors: MochiColors
    let onToggleTheme: () -> Void
    let onNavigateToSettings: () -> Void
    let onSelectProfile: (String) -> Void

    private func status(for profile: AgentProfile) -> AgentAvailabilityStatus {
        profileStatuses[profile.id] ?? .unpaired
    }

    private func statusColor(_ status: AgentAvailabilityStatus) -> Color {
        switch status {
        case .available: return colors.onlineGreen
        case .pairing, .connecting: return colors.accent
        case .unconfigured, .unpaired: return colors.textSecondary
        case .offline: return colors.recordingRed
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            if profiles.count >= 2 {
                HStack(spacing: 4) {
                    ForEach(Array(profiles.prefix(SettingsManager.maxAgentProfiles))) { profile in
                        let itemStatus = status(for: profile)
                        Button {
                            onSelectProfile(profile.id)
                        } label: {
                            HStack(spacing: 4) {
                                Text("\(profile.resolvedDisplayName)(\(itemStatus.label))")
                                    .font(.system(size: 11, weight: profile.id == selectedProfile.id ? .semibold : .regular))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.72)
                                if profile.id != selectedProfile.id && (unreadCounts[profile.id] ?? 0) > 0 {
                                    Circle()
                                        .fill(colors.recordingRed)
                                        .frame(width: 6, height: 6)
                                }
                            }
                            .foregroundColor(profile.id == selectedProfile.id ? colors.onPrimary : statusColor(itemStatus))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 6)
                            .background(profile.id == selectedProfile.id ? colors.primary : colors.inputBg)
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .layoutPriority(1)
            } else {
                let itemStatus = status(for: selectedProfile)
                HStack(spacing: 5) {
                    Image(systemName: selectedProfile.platform.iconName)
                        .font(.system(size: 12, weight: .medium))
                    Text("\(selectedProfile.resolvedDisplayName)(\(itemStatus.label))")
                        .font(.system(size: 13, weight: .regular))
                        .lineLimit(1)
                }
                .foregroundColor(statusColor(itemStatus))
                .layoutPriority(1)
            }

            Spacer()

            // Theme toggle — matches Android's 32dp IconButton with CircleShape background
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

            // Settings button — matches Android's IconButton with 32dp tap target
            Button(action: onNavigateToSettings) {
                Image(systemName: "gearshape.fill")
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

struct MainScreenView: View {
    @ObservedObject var wsManager: WebSocketManager
    @ObservedObject var settingsManager: SettingsManager
    @ObservedObject var audioRecorder: AudioRecorder
    let isDark: Bool
    let colors: MochiColors
    let onToggleTheme: () -> Void
    let onNavigateToSettings: () -> Void
    let onSelectProfile: (String) -> Void

    @State private var inputMode: InputMode = .voice
    @State private var isNearChatBottom = true
    @State private var isSelectingMessages = false
    @State private var selectedMessageIds = Set<UUID>()
    @State private var quotedMessageSummary: String?
    private let bottomAnchorId = "chat-bottom-anchor"

    private var selectedMessages: [ChatMessage] {
        wsManager.messages.filter { selectedMessageIds.contains($0.id) }
    }

    private var selectedProfile: AgentProfile {
        settingsManager.selectedProfile
    }

    private var isAudioEnabled: Bool {
        selectedProfile.platform.supportsAudio
    }

    var body: some View {
        VStack(spacing: 0) {
            TopBarView(
                connectionState: wsManager.connectionState,
                selectedProfile: selectedProfile,
                profiles: settingsManager.profiles,
                profileStatuses: Dictionary(uniqueKeysWithValues: settingsManager.profiles.map { ($0.id, wsManager.availabilityStatus(for: $0)) }),
                unreadCounts: wsManager.unreadCounts,
                isDark: isDark,
                colors: colors,
                onToggleTheme: onToggleTheme,
                onNavigateToSettings: onNavigateToSettings,
                onSelectProfile: onSelectProfile
            )

            Divider().background(colors.divider)

            GeometryReader { geometry in
                ZStack {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 16) {
                                HistoryInlineStatusView(wsManager: wsManager, colors: colors)

                                ForEach(wsManager.messages) { message in
                                    MessageBubbleView(
                                        message: message,
                                        colors: colors,
                                        isSelectionMode: isSelectingMessages,
                                        isSelected: selectedMessageIds.contains(message.id),
                                        onTap: {
                                            if isSelectingMessages {
                                                toggleMessageSelection(message)
                                            }
                                        },
                                        onCopy: {
                                            copyMessages([message])
                                        },
                                        onQuote: {
                                            quotedMessageSummary = quoteSummary(for: message.content)
                                            inputMode = .text
                                        },
                                        onSelect: {
                                            isSelectingMessages = true
                                            selectedMessageIds = [message.id]
                                        },
                                        onApprovalCommand: { command in
                                            sendApprovalCommand(command)
                                        }
                                    )
                                }

                                Color.clear
                                    .frame(height: 1)
                                    .id(bottomAnchorId)
                                    .background(
                                        GeometryReader { bottomGeometry in
                                            Color.clear.preference(
                                                key: ChatBottomPositionPreferenceKey.self,
                                                value: bottomGeometry.frame(in: .named("chatScroll")).maxY
                                            )
                                        }
                                    )
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 16)
                        }
                        .coordinateSpace(name: "chatScroll")
                        .onPreferenceChange(ChatBottomPositionPreferenceKey.self) { bottomY in
                            isNearChatBottom = bottomY - geometry.size.height <= 120
                        }
                        .onChange(of: wsManager.messages.last?.id) { _ in
                            guard let lastMessage = wsManager.messages.last else { return }
                            if isNearChatBottom || lastMessage.isUser {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    proxy.scrollTo(bottomAnchorId, anchor: .bottom)
                                }
                            }
                        }
                        .refreshable {
                            wsManager.requestRecentHistory()
                        }
                    }

                    if wsManager.pairingState != .paired {
                        VStack(spacing: 8) {
                            Text("请先扫码配对 \(selectedProfile.platform.label)")
                                .font(.system(size: 16, weight: .regular))
                                .foregroundColor(colors.textSecondary)
                            Button("去设置") {
                                onNavigateToSettings()
                            }
                            .font(.system(size: 14, weight: .medium))
                        }
                    }
                }
            }

            if isSelectingMessages {
                MessageSelectionToolbar(
                    selectedCount: selectedMessageIds.count,
                    colors: colors,
                    onCopy: {
                        copyMessages(selectedMessages)
                        clearMessageSelection()
                    },
                    onCancel: clearMessageSelection
                )
            }

            InputAreaView(
                inputMode: $inputMode,
                isRecording: audioRecorder.isRecording,
                isPaired: wsManager.pairingState == .paired,
                isAudioEnabled: isAudioEnabled,
                colors: colors,
                quotedMessageSummary: quotedMessageSummary,
                onSendText: { text in
                    if wsManager.pairingState != .paired {
                        wsManager.addLocalMessage("请先配对 \(selectedProfile.platform.label)", senderId: "assistant")
                        return
                    }
                    let outgoingText = quotedMessageSummary.map { "> \($0)\n\n\(text)" } ?? text
                    wsManager.sendText(outgoingText)
                    quotedMessageSummary = nil
                },
                onCancelQuote: {
                    quotedMessageSummary = nil
                },
                onMicPress: {
                    if !audioRecorder.isRecording {
                        audioRecorder.startRecording()
                    }
                },
                onMicRelease: { cancelled in
                    if audioRecorder.isRecording {
                        audioRecorder.stopRecording { data in
                            if !cancelled {
                                wsManager.sendAudio(data)
                            }
                        }
                    }
                },
                audioRecorder: audioRecorder
            )
        }
        .background(colors.background)
        .onChange(of: settingsManager.selectedProfileId) { _ in
            clearMessageSelection()
            quotedMessageSummary = nil
            if !settingsManager.selectedProfile.platform.supportsAudio {
                inputMode = .text
            }
        }
    }

    private func toggleMessageSelection(_ message: ChatMessage) {
        if selectedMessageIds.contains(message.id) {
            selectedMessageIds.remove(message.id)
        } else {
            selectedMessageIds.insert(message.id)
        }
        if selectedMessageIds.isEmpty {
            isSelectingMessages = false
        }
    }

    private func clearMessageSelection() {
        isSelectingMessages = false
        selectedMessageIds.removeAll()
    }

    private func copyMessages(_ messages: [ChatMessage]) {
        UIPasteboard.general.string = messages
            .map { $0.content }
            .joined(separator: "\n\n")
    }

    private func sendApprovalCommand(_ command: String) {
        guard wsManager.pairingState == .paired else {
            wsManager.addLocalMessage("请先配对 \(selectedProfile.platform.label)", senderId: "assistant")
            return
        }
        wsManager.sendText(command)
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

private struct ChatBottomPositionPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct MessageSelectionToolbar: View {
    let selectedCount: Int
    let colors: MochiColors
    let onCopy: () -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text("已选 \(selectedCount) 条")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(colors.textSecondary)

            Spacer()

            Button(action: onCopy) {
                Label("复制", systemImage: "doc.on.doc")
                    .font(.system(size: 14, weight: .medium))
            }
            .disabled(selectedCount == 0)

            Button(action: onCancel) {
                Label("取消", systemImage: "xmark")
                    .font(.system(size: 14, weight: .medium))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(colors.surface)
        .overlay(Divider().background(colors.divider), alignment: .top)
    }
}

struct HistoryInlineStatusView: View {
    @ObservedObject var wsManager: WebSocketManager
    let colors: MochiColors

    var body: some View {
        Group {
            if wsManager.historyLoading {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.75)
                        .tint(colors.primary)
                    Text("正在加载更早的历史")
                        .font(.system(size: 12))
                        .foregroundColor(colors.textSecondary)
                }
                .frame(maxWidth: .infinity)
            } else if let error = wsManager.historyError {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundColor(colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            } else if wsManager.historyLoaded && !wsManager.historyHasMore {
                Text("已显示全部历史对话")
                    .font(.system(size: 11))
                    .foregroundColor(colors.textSecondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}
