import SwiftUI
import Combine
import UIKit

@main
struct OpenClawRemoteApp: App {
    @UIApplicationDelegateAdaptor(BosonRemoteControlAppDelegate.self) private var appDelegate

    @StateObject private var settingsManager: SettingsManager
    @StateObject private var wsManager: WebSocketManager
    @StateObject private var headsetController: HeadsetConversationController
    @StateObject private var audioRecorder = AudioRecorder()
    @StateObject private var messageSpeechController = MessageSpeechController()

    @State private var isDark = false
    @State private var showSettings = false
    @State private var showQRScanner = false

    init() {
        let settings = SettingsManager()
        _settingsManager = StateObject(wrappedValue: settings)
        let baseDeviceId = getOrCreateDeviceId(settingsManager: settings)
        let activeProfile = settings.selectedProfile
        let manager = WebSocketManager(
            deviceId: baseDeviceId,
            deviceLabel: settings.config.deviceLabel.isEmpty ? "我的设备" : settings.config.deviceLabel,
            token: activeProfile.token
        )
        manager.syncProfiles(settings.profiles)
        _wsManager = StateObject(wrappedValue: manager)
        _headsetController = StateObject(wrappedValue: HeadsetConversationController(
            wsManager: manager,
            settingsManager: settings
        ))
    }

    private var colors: MochiColors {
        isDark ? .dark : .light
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if showQRScanner {
                    QRScannerScreenView(
                        onQRCodeScanned: { scannedText in
                            showQRScanner = false
                            handleQRParsed(scannedText)
                        },
                        onClose: { showQRScanner = false }
                    )
                } else if showSettings {
                    SettingsScreenView(
                        wsManager: wsManager,
                        settingsManager: settingsManager,
                        isDark: isDark,
                        colors: colors,
                        onToggleTheme: { isDark.toggle() },
                        onRequestPair: { backendId in
                            applySelectedProfile()
                            wsManager.requestPair(backendId: backendId)
                            showSettings = false
                        },
                        onUnpair: {
                            wsManager.unpair()
                        },
                        onBack: { showSettings = false },
                        onNavigateToQRScanner: { showQRScanner = true },
                        onSelectProfile: { profileId in
                            settingsManager.selectProfile(profileId)
                            applySelectedProfile()
                        }
                    )
                } else {
                    MainScreenView(
                        wsManager: wsManager,
                        settingsManager: settingsManager,
                        audioRecorder: audioRecorder,
                        headsetController: headsetController,
                        messageSpeechController: messageSpeechController,
                        isDark: isDark,
                        colors: colors,
                        onToggleTheme: { isDark.toggle() },
                        onNavigateToSettings: { showSettings = true },
                        onSelectProfile: { profileId in
                            settingsManager.selectProfile(profileId)
                            applySelectedProfile()
                        }
                    )
                }
            }
            .preferredColorScheme(isDark ? .dark : .light)
            .onReceive(wsManager.messageChannel) { event in
                handleWebSocketEvent(event)
            }
            .onAppear {
                let isSystemDark = UITraitCollection.current.userInterfaceStyle == .dark
                isDark = isSystemDark
                applySelectedProfile()
                headsetController.start()
            }
        }
    }

    private func handleQRParsed(_ scannedText: String) {
        let result = parseQRPack(scannedText)
        switch result {
        case .success(let gatewayUrl, let backendId, let token, let platform, let label):
            if let error = settingsManager.profileAcceptError(gatewayUrl: gatewayUrl, backendId: backendId) {
                wsManager.addLocalMessage(error, senderId: "assistant")
                return
            }
            guard let profile = settingsManager.upsertProfile(
                gatewayUrl: gatewayUrl,
                backendId: backendId,
                token: token,
                platform: platform,
                label: label
            ) else {
                wsManager.addLocalMessage("无法新增 Agent", senderId: "assistant")
                return
            }
            wsManager.syncProfiles(settingsManager.profiles)
            wsManager.applyProfile(profile, deviceLabel: settingsManager.config.deviceLabel)
            wsManager.rememberBackendForPairing(backendId)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                wsManager.requestPair(backendId: backendId)
            }
        case .error:
            break
        }
    }

    private func handleWebSocketEvent(_ event: WsMessageEvent) {
        switch event {
        case .registered(_):
            break
        case .paired(let profileId, let backendId, let backendLabel):
            settingsManager.updatePairedBackend(backendId, backendLabel, profileId: profileId)
        case .unpaired(let profileId):
            settingsManager.updatePairedBackend(nil, nil, profileId: profileId)
        case .newMessage(_, _), .error(_, _):
            break
        }
    }

    private func applySelectedProfile() {
        wsManager.syncProfiles(settingsManager.profiles)
        wsManager.applyProfile(settingsManager.selectedProfile, deviceLabel: settingsManager.config.deviceLabel)
    }
}

final class BosonRemoteControlAppDelegate: UIResponder, UIApplicationDelegate {
    func application(
        _: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        return true
    }
}

private func getOrCreateDeviceId(settingsManager: SettingsManager) -> String {
    if !settingsManager.baseDeviceId.isEmpty {
        return settingsManager.baseDeviceId
    }
    let id = "device_\(UUID().uuidString.prefix(8))"
    settingsManager.updateDeviceId(id)
    return id
}
