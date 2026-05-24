import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

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

struct HeadsetStatusStripView: View {
    @ObservedObject var headsetController: HeadsetConversationController
    let colors: MochiColors

    private var connectionLabel: String {
        switch headsetController.connectionState {
        case .idle:
            return "耳机待机"
        case .scanning:
            return "查找 A9Ultra"
        case .connecting(let name):
            return "连接 \(name)"
        case .connected(let name):
            return "找到 \(name)，校验中"
        case .ready(let name):
            return "\(name) 已就绪"
        case .unsupportedProduct(let productId):
            return "非 A9Ultra: 0x\(String(productId, radix: 16))"
        case .bluetoothUnavailable(let message):
            return message
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "headphones")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(colors.primary)
            Text(connectionLabel)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(colors.textSecondary)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(headsetController.headsetStatusLabel)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(colors.primary)
                .lineLimit(1)
            Button {
                headsetController.debugRestartHeadset()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(colors.primary)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("重连耳机")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(colors.inputBg)
    }
}

#if DEBUG
private struct HeadsetDebugPanelView: View {
    @ObservedObject var headsetController: HeadsetConversationController
    @ObservedObject var bleManager: A9UltraBLEManager
    let colors: MochiColors

    private var connectionLabel: String {
        switch headsetController.connectionState {
        case .idle:
            return "待机"
        case .scanning:
            return "扫描"
        case .connecting(let name):
            return "连接 \(name)"
        case .connected(let name):
            return "\(name) 校验中"
        case .ready(let name):
            return "\(name) 已就绪"
        case .unsupportedProduct(let productId):
            return "非目标 0x\(String(productId, radix: 16))"
        case .bluetoothUnavailable(let message):
            return message
        }
    }

    private var debugFields: [String] {
        let info = bleManager.debugInfo
        return [
            "状态 \(connectionLabel) / \(headsetController.sessionState.label)",
            "PID \(info.productIdText)",
            "W \(info.hasWriteCharacteristic ? "1" : "0")",
            "N \(info.hasNotifyCharacteristic ? "1" : "0")",
            "Frame \(info.lastFrameText)",
            "Chunk \(info.audioChunkCount)",
            "Probe \(headsetController.isDebugRecordingProbeActive ? "on" : "off")"
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 6)], spacing: 6) {
                HeadsetDebugButton(title: "重连", colors: colors) {
                    headsetController.debugRestartHeadset()
                }
                HeadsetDebugButton(title: "重试校验", colors: colors) {
                    headsetController.debugRetryHandshake()
                }
                HeadsetDebugButton(title: "强制就绪", colors: colors) {
                    headsetController.debugForceReady()
                }
                HeadsetDebugButton(title: "录音测试", colors: colors) {
                    headsetController.debugStartRecordingProbe()
                }
                HeadsetDebugButton(title: "停止录音", colors: colors, isDestructive: true) {
                    headsetController.debugStopRecordingProbe()
                }
            }

            Text(debugFields.joined(separator: " | "))
                .font(.system(size: 10, weight: .regular))
                .foregroundColor(colors.textSecondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            if let lastError = bleManager.debugInfo.lastError, !lastError.isEmpty {
                Text("错误 \(lastError)")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundColor(colors.recordingRed)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !bleManager.debugLogLines.isEmpty {
                Text(bleManager.debugLogLines.suffix(10).joined(separator: "\n"))
                    .font(.system(size: 9, weight: .regular, design: .monospaced))
                    .foregroundColor(colors.textSecondary)
                    .lineLimit(10)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
                    .background(colors.inputBg)
                    .cornerRadius(6)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(colors.surface)
    }
}

private struct HeadsetDebugButton: View {
    let title: String
    let colors: MochiColors
    var isDestructive = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(isDestructive ? colors.recordingRed : colors.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(isDestructive ? colors.recordingRed.opacity(0.10) : colors.inputBg)
                .cornerRadius(7)
        }
        .buttonStyle(.plain)
    }
}
#endif

struct MainScreenView: View {
    @ObservedObject var wsManager: WebSocketManager
    @ObservedObject var settingsManager: SettingsManager
    @ObservedObject var audioRecorder: AudioRecorder
    @ObservedObject var headsetController: HeadsetConversationController
    @ObservedObject var messageSpeechController: MessageSpeechController
    let isDark: Bool
    let colors: MochiColors
    let onToggleTheme: () -> Void
    let onNavigateToSettings: () -> Void
    let onSelectProfile: (String) -> Void
    var showsTopBar = true
    var showsHeadsetStrip = true

    @State private var inputMode: InputMode = .voice
    @State private var isNearChatBottom = true
    @State private var isSelectingMessages = false
    @State private var selectedMessageIds = Set<UUID>()
    @State private var quotedMessageSummary: String?
    @State private var inspectedApprovalRequest: ApprovalRequest?
    @State private var handledApprovalMessageIds = Set<UUID>()
    @State private var fullscreenTable: MarkdownTable?
    @State private var tableSharePayload: TableSharePayload?
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
            if showsTopBar {
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
            }

            if showsHeadsetStrip {
                HeadsetStatusStripView(headsetController: headsetController, colors: colors)

                Divider().background(colors.divider)
            }

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
                                        onSpeak: {
                                            messageSpeechController.speak(message.content)
                                        },
                                        onApprovalCommand: { command in
                                            guard !handledApprovalMessageIds.contains(message.id),
                                                  sendApprovalCommand(command) else {
                                                return
                                            }
                                            let result = markApprovalHandledIfAllowed(
                                                handledIds: handledApprovalMessageIds,
                                                messageId: message.id
                                            )
                                            if result.allowed {
                                                handledApprovalMessageIds = result.handledIds
                                            }
                                        },
                                        isApprovalHandled: handledApprovalMessageIds.contains(message.id),
                                        onInspectApprovalCode: { request in
                                            inspectedApprovalRequest = request
                                        },
                                        onCopyTable: { table in
                                            copyTable(table)
                                        },
                                        onDownloadTable: { table in
                                            downloadTable(table)
                                        },
                                        onFullscreenTable: { table in
                                            fullscreenTable = table
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
        .fullScreenCover(item: $inspectedApprovalRequest) { request in
            ApprovalCodeInspectorView(request: request, colors: colors)
        }
        .fullScreenCover(item: $fullscreenTable) { table in
            FullscreenMarkdownTableView(
                table: table,
                colors: colors,
                onCopy: {
                    copyTable(table)
                },
                onDownload: {
                    downloadTable(table)
                }
            )
        }
        .sheet(item: $tableSharePayload) { payload in
            ActivityView(activityItems: payload.items)
        }
        .onChange(of: settingsManager.selectedProfileId) { _ in
            clearMessageSelection()
            quotedMessageSummary = nil
            handledApprovalMessageIds.removeAll()
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

    private func copyTable(_ table: MarkdownTable) {
        UIPasteboard.general.string = table.markdownSource
    }

    private func downloadTable(_ table: MarkdownTable) {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(tableExportFileName())
        do {
            try table.csvSource.write(to: fileURL, atomically: true, encoding: .utf8)
            tableSharePayload = TableSharePayload(items: [fileURL])
        } catch {
            UIPasteboard.general.string = table.csvSource
        }
    }

    private func tableExportFileName(date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "openclaw-table-\(formatter.string(from: date)).csv"
    }

    private func sendApprovalCommand(_ command: String) -> Bool {
        guard wsManager.pairingState == .paired else {
            wsManager.addLocalMessage("请先配对 \(selectedProfile.platform.label)", senderId: "assistant")
            return false
        }
        wsManager.sendText(command)
        return true
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

private struct TableSharePayload: Identifiable {
    let id = UUID()
    let items: [Any]
}

private struct ApprovalCodeInspectorView: View {
    let request: ApprovalRequest
    let colors: MochiColors
    @Environment(\.dismiss) private var dismiss

    private var lines: [String] {
        if request.codeLines.isEmpty, !request.command.isEmpty {
            return [request.command]
        }
        return request.codeLines
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if lines.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 32, weight: .semibold))
                            .foregroundColor(colors.textSecondary)
                        Text("没有解析到代码")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(colors.textSecondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(colors.background)
                } else {
                    ScrollView([.vertical, .horizontal], showsIndicators: true) {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                                CodeLineRow(
                                    lineNumber: index + 1,
                                    line: line,
                                    colors: colors,
                                    isAlternating: index.isMultiple(of: 2)
                                )
                            }
                        }
                        .padding(16)
                    }
                    .background(colors.background)
                }
            }
            .navigationTitle("\(max(lines.count, 0)) 行代码")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("关闭") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        UIPasteboard.general.string = request.command
                    } label: {
                        Label("复制全部", systemImage: "doc.on.doc")
                    }
                    .disabled(request.command.isEmpty)
                }
            }
        }
        .navigationViewStyle(.stack)
    }
}

private struct CodeLineRow: View {
    let lineNumber: Int
    let line: String
    let colors: MochiColors
    let isAlternating: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(lineNumber)")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(colors.textSecondary)
                .frame(width: 42, alignment: .trailing)

            Text(line.isEmpty ? " " : line)
                .font(.system(size: 13, weight: .regular, design: .monospaced))
                .foregroundColor(colors.textPrimary)
                .textSelection(.enabled)
                .fixedSize(horizontal: true, vertical: false)

            Spacer(minLength: 16)

            Button {
                UIPasteboard.general.string = line
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(colors.textSecondary)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("复制第 \(lineNumber) 行")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(isAlternating ? colors.surface.opacity(0.78) : colors.inputBg.opacity(0.58))
        .contextMenu {
            Button {
                UIPasteboard.general.string = line
            } label: {
                Label("复制本行", systemImage: "doc.on.doc")
            }
        }
    }
}

private struct FullscreenMarkdownTableView: View {
    let table: MarkdownTable
    let colors: MochiColors
    let onCopy: () -> Void
    let onDownload: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ScrollView([.horizontal, .vertical], showsIndicators: true) {
                MarkdownTableGrid(
                    table: table,
                    colors: colors,
                    textColor: colors.textPrimary
                )
                .padding(16)
            }
            .background(colors.background)
            .navigationTitle("表格")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("关闭") {
                        dismiss()
                    }
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button(action: onCopy) {
                        Label("复制", systemImage: "doc.on.doc")
                    }
                    Button(action: onDownload) {
                        Label("下载", systemImage: "square.and.arrow.down")
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
    }
}

#if canImport(UIKit)
private struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif

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
