import SwiftUI

struct TopBarView: View {
    let connectionState: ConnectionState
    let pairingState: PairingState
    let pairedBackendLabel: String?
    let isDark: Bool
    let colors: MochiColors
    let onToggleTheme: () -> Void
    let onNavigateToHistory: () -> Void
    let onNavigateToSettings: () -> Void

    private var statusColor: Color {
        if pairingState == .paired { return colors.onlineGreen }
        if connectionState == .registered || connectionState == .connected || connectionState == .connecting {
            return colors.accent
        }
        return colors.recordingRed
    }

    private var statusText: String {
        if pairingState == .paired {
            return "已配对" + (pairedBackendLabel.map { " · \($0)" } ?? "")
        }
        switch connectionState {
        case .registered: return "已连接，请扫码"
        case .connected, .connecting: return "连接中..."
        default: return "未连接"
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            // App title
            Text("OpenClaw Remote")
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(colors.textSecondary)

            // Status indicator
            Text("• \(statusText)")
                .font(.system(size: 11, weight: .regular))
                .foregroundColor(statusColor)

            Spacer()

            Button(action: onNavigateToHistory) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 20))
                    .foregroundColor(colors.icon)
                    .frame(width: 32, height: 32)
            }

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
    let onNavigateToHistory: () -> Void
    let onNavigateToSettings: () -> Void

    @State private var inputMode: InputMode = .voice

    var body: some View {
        VStack(spacing: 0) {
            TopBarView(
                connectionState: wsManager.connectionState,
                pairingState: wsManager.pairingState,
                pairedBackendLabel: settingsManager.config.pairedBackendLabel,
                isDark: isDark,
                colors: colors,
                onToggleTheme: onToggleTheme,
                onNavigateToHistory: onNavigateToHistory,
                onNavigateToSettings: onNavigateToSettings
            )

            Divider().background(colors.divider)

            GeometryReader { geometry in
                ZStack {
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            ForEach(wsManager.messages) { message in
                                MessageBubbleView(
                                    message: message,
                                    colors: colors
                                )
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 16)
                    }

                    if wsManager.pairingState != .paired {
                        VStack(spacing: 8) {
                            Text("请先扫码配对 OpenClaw")
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

            InputAreaView(
                inputMode: $inputMode,
                isRecording: audioRecorder.isRecording,
                isPaired: wsManager.pairingState == .paired,
                colors: colors,
                onSendText: { text in
                    if wsManager.pairingState != .paired {
                        wsManager.addLocalMessage("请先配对 OpenClaw", senderId: "assistant")
                        return
                    }
                    wsManager.sendText(text)
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
    }
}

struct HistoryScreenView: View {
    @ObservedObject var wsManager: WebSocketManager
    let colors: MochiColors
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(colors.icon)
                        .frame(width: 32, height: 32)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("历史对话")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(colors.textPrimary)
                    Text("最近 10 轮 Agent 上下文")
                        .font(.system(size: 11))
                        .foregroundColor(colors.textSecondary)
                }

                Spacer()

                Button {
                    wsManager.requestRecentHistory(rounds: 10)
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(colors.icon)
                        .frame(width: 32, height: 32)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(colors.surface)

            Divider().background(colors.divider)

            Group {
                if wsManager.historyLoading {
                    ProgressView()
                        .tint(colors.primary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = wsManager.historyError {
                    VStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 28))
                            .foregroundColor(colors.recordingRed)
                        Text(error)
                            .font(.system(size: 14))
                            .foregroundColor(colors.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if wsManager.historyMessages.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "clock")
                            .font(.system(size: 30))
                            .foregroundColor(colors.textSecondary)
                        Text("还没有可读取的历史")
                            .font(.system(size: 14))
                            .foregroundColor(colors.textSecondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            ForEach(wsManager.historyMessages) { message in
                                MessageBubbleView(message: message, colors: colors)
                            }

                            if wsManager.historyHasMore {
                                Text("已显示最近 10 轮")
                                    .font(.system(size: 11))
                                    .foregroundColor(colors.textSecondary)
                                    .padding(.top, 4)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 16)
                    }
                }
            }
        }
        .background(colors.background)
        .onAppear {
            wsManager.requestRecentHistory(rounds: 10)
        }
    }
}
