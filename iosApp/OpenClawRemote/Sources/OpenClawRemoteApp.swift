import SwiftUI

@main
struct OpenClawRemoteApp: App {
    @StateObject private var settingsManager = SettingsManager()
    @StateObject private var wsManager: WebSocketManager
    @StateObject private var audioRecorder = AudioRecorder()

    @State private var isDark = false
    @State private var showSettings = false
    @State private var showQRScanner = false

    init() {
        let settings = SettingsManager()
        let deviceId = getOrCreateDeviceId(settingsManager: settings)
        _wsManager = StateObject(wrappedValue: WebSocketManager(
            deviceId: deviceId,
            deviceLabel: settings.config.deviceLabel.isEmpty ? "我的设备" : settings.config.deviceLabel,
            token: settings.config.token
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
                            wsManager.requestPair(backendId: backendId)
                            showSettings = false
                        },
                        onUnpair: {
                            wsManager.unpair()
                        },
                        onBack: { showSettings = false },
                        onNavigateToQRScanner: { showQRScanner = true }
                    )
                } else {
                    MainScreenView(
                        wsManager: wsManager,
                        settingsManager: settingsManager,
                        audioRecorder: audioRecorder,
                        isDark: isDark,
                        colors: colors,
                        onToggleTheme: { isDark.toggle() },
                        onNavigateToSettings: { showSettings = true }
                    )
                }
            }
            .preferredColorScheme(isDark ? .dark : .light)
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    wsManager.connect(to: settingsManager.config.gatewayUrl)
                }
            }
        }
    }

    private func handleQRParsed(_ scannedText: String) {
        let result = parseQRPack(scannedText)
        switch result {
        case .success(let gatewayUrl, let backendId, let token):
            settingsManager.updateConfig(GatewayConfig(
                gatewayUrl: gatewayUrl,
                deviceId: settingsManager.config.deviceId,
                deviceLabel: settingsManager.config.deviceLabel.isEmpty ? "我的设备" : settingsManager.config.deviceLabel,
                token: token,
                pairedBackendId: nil,
                pairedBackendLabel: nil
            ))
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                wsManager.connect(to: gatewayUrl)
                wsManager.requestPair(backendId: backendId)
            }
        case .error:
            break
        }
    }
}

private func getOrCreateDeviceId(settingsManager: SettingsManager) -> String {
    if !settingsManager.config.deviceId.isEmpty {
        return settingsManager.config.deviceId
    }
    let id = "device_\(UUID().uuidString.prefix(8))"
    settingsManager.updateDeviceId(id)
    return id
}
