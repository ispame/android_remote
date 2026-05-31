import SwiftUI

struct RootTabView: View {
    @ObservedObject var wsManager: WebSocketManager
    @ObservedObject var settingsManager: SettingsManager
    @ObservedObject var audioRecorder: AudioRecorder
    @ObservedObject var headsetController: HeadsetConversationController
    @ObservedObject var messageSpeechController: MessageSpeechController
    @ObservedObject var scheduledTaskStore: ScheduledTaskStore
    @ObservedObject var agentTaskService: AgentTaskService
    @ObservedObject var recordingStore: RecordingStore
    @ObservedObject var headsetSettingsStore: HeadsetSettingsStore
    let isDark: Bool
    let colors: MochiColors
    let onToggleTheme: () -> Void
    let onSelectProfile: (String) -> Void
    let onRequestPair: (String) -> Void
    let onQRCodeScanned: (String) -> Void
    let onSwitchAccount: () -> Void
    let onLogout: () -> Void

    @State private var selectedTab: AppTab = .agents
    @State private var showQRScanner = false

    var body: some View {
        TabView(selection: $selectedTab) {
            CompatibleNavigationStack {
                AgentsTabView(
                    wsManager: wsManager,
                    settingsManager: settingsManager,
                    audioRecorder: audioRecorder,
                    headsetController: headsetController,
                    messageSpeechController: messageSpeechController,
                    isDark: isDark,
                    colors: colors,
                    onToggleTheme: onToggleTheme,
                    onSelectProfile: onSelectProfile,
                    onRequestScan: { showQRScanner = true }
                )
            }
            .tabItem {
                Label("Agent", systemImage: "bubble.left.and.bubble.right.fill")
            }
            .tag(AppTab.agents)

            CompatibleNavigationStack {
                TasksTabView(
                    wsManager: wsManager,
                    settingsManager: settingsManager,
                    audioRecorder: audioRecorder,
                    headsetController: headsetController,
                    scheduledTaskStore: scheduledTaskStore,
                    agentTaskService: agentTaskService,
                    recordingStore: recordingStore,
                    colors: colors
                )
            }
            .tabItem {
                Label("录音", systemImage: "waveform")
            }
            .tag(AppTab.tasks)

            CompatibleNavigationStack {
                HeadsetTabView(
                    headsetController: headsetController,
                    headsetSettingsStore: headsetSettingsStore,
                    colors: colors
                )
            }
            .tabItem {
                Label("耳机", systemImage: "headphones")
            }
            .tag(AppTab.headset)

            CompatibleNavigationStack {
                SimpleSettingsTabView(
                    wsManager: wsManager,
                    settingsManager: settingsManager,
                    isDark: isDark,
                    colors: colors,
                    onToggleTheme: onToggleTheme,
                    onRequestPair: onRequestPair,
                    onSelectProfile: onSelectProfile,
                    onSwitchAccount: onSwitchAccount,
                    onLogout: onLogout
                )
            }
            .tabItem {
                Label("设置", systemImage: "gearshape.fill")
            }
            .tag(AppTab.settings)
        }
        .accentColor(colors.primary)
        .fullScreenCover(isPresented: $showQRScanner) {
            QRScannerScreenView(
                onQRCodeScanned: { value in
                    showQRScanner = false
                    onQRCodeScanned(value)
                },
                onClose: {
                    showQRScanner = false
                }
            )
        }
    }
}

private enum AppTab: Hashable {
    case agents
    case tasks
    case headset
    case settings
}
