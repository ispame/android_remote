import SwiftUI

struct TopBarView: View {
    let connectionState: ConnectionState
    let pairingState: PairingState
    let pairedBackendLabel: String?
    let isDark: Bool
    let colors: MochiColors
    let onToggleTheme: () -> Void
    let onNavigateToSettings: () -> Void

    var statusColor: Color {
        if pairingState == .paired { return colors.onlineGreen }
        if connectionState == .registered || connectionState == .connected || connectionState == .connecting {
            return colors.accent
        }
        return colors.recordingRed
    }

    var statusText: String {
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
            Text("OpenClaw Remote")
                .font(.system(size: 13))
                .foregroundColor(colors.textSecondary)

            Text("• \(statusText)")
                .font(.system(size: 11))
                .foregroundColor(statusColor)

            Spacer()

            Button(action: onToggleTheme) {
                Image(systemName: isDark ? "sun.max.fill" : "moon.fill")
                    .font(.system(size: 20))
                    .foregroundColor(isDark ? Color(hex: "E8A87C") : Color(hex: "B85C38"))
            }
            .frame(width: 32, height: 32)

            Button(action: onNavigateToSettings) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 20))
                    .foregroundColor(colors.icon)
            }
            .frame(width: 32, height: 32)
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
                                .font(.system(size: 16))
                                .foregroundColor(colors.textSecondary)
                            Button("去设置") {
                                onNavigateToSettings()
                            }
                            .font(.system(size: 14))
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
                    wsManager.addLocalMessage(text, senderId: "user")
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

    private func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: Date())
    }
}