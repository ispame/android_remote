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
    @State private var authNotice: String? = nil
    @State private var tokenRefreshTask: Task<Void, Never>? = nil

    init() {
        let settings = SettingsManager()
        _settingsManager = StateObject(wrappedValue: settings)
        let activeProfile = settings.selectedProfile
        let manager = WebSocketManager(
            deviceLabel: settings.config.deviceLabel.isEmpty ? "我的设备" : settings.config.deviceLabel,
            accessToken: settings.config.accessToken
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
                if settingsManager.configPublished.accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    AuthScreenView(
                        config: settingsManager.configPublished,
                        colors: colors,
                        notice: authNotice,
                        onAuthenticated: { session, gatewayUrl, terminalLabel in
                            applyAuthSession(session, gatewayUrl: gatewayUrl, terminalLabel: terminalLabel)
                        },
                        onNoticeShown: {
                            authNotice = nil
                        }
                    )
                } else if showQRScanner {
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
                        onNavigateToQRScanner: {
                            if !settingsManager.configPublished.accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                showQRScanner = true
                            }
                        },
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
            .onReceive(settingsManager.$configPublished) { config in
                scheduleTokenRefresh(for: config)
                if config.accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    showQRScanner = false
                    showSettings = false
                }
            }
            .onAppear {
                let isSystemDark = UITraitCollection.current.userInterfaceStyle == .dark
                isDark = isSystemDark
                applySelectedProfile()
                scheduleTokenRefresh(for: settingsManager.configPublished)
                headsetController.start()
            }
        }
    }

    private func handleQRParsed(_ scannedText: String) {
        guard !settingsManager.configPublished.accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            authNotice = "请先登录账号，再扫码配对"
            return
        }
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
            wsManager.applyProfile(
                profile,
                deviceLabel: settingsManager.config.deviceLabel,
                accessToken: settingsManager.config.accessToken
            )
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
        case .sessionPreempted(let replacementTerminalLabel):
            let suffix = replacementTerminalLabel
                .flatMap { $0.isEmpty ? nil : "：\($0)" } ?? ""
            clearAuthSession(message: "账号已在另一台设备登录\(suffix)")
        case .error(let code, _):
            if isTerminalAuthError(code) {
                clearAuthSession(message: "登录状态已过期，请重新登录")
            }
        case .newMessage(_, _):
            break
        }
    }

    private func applyAuthSession(
        _ session: GatewayAuthSessionResponse,
        gatewayUrl: String,
        terminalLabel: String
    ) {
        let current = settingsManager.configPublished
        settingsManager.updateConfig(
            GatewayConfig(
                gatewayUrl: gatewayUrl,
                accountId: session.accountId,
                accessToken: session.accessToken,
                refreshToken: session.refreshToken,
                accessExpiresAt: session.accessExpiresAt,
                refreshExpiresAt: session.refreshExpiresAt,
                deviceLabel: terminalLabel.isEmpty ? "我的设备" : terminalLabel,
                token: current.token,
                pairedBackendId: current.pairedBackendId,
                pairedBackendLabel: current.pairedBackendLabel,
                asrMode: current.asrMode,
                asrProfileId: current.asrProfileId
            )
        )
        authNotice = nil
        applySelectedProfile()
    }

    private func clearAuthSession(message: String) {
        tokenRefreshTask?.cancel()
        tokenRefreshTask = nil
        showQRScanner = false
        showSettings = false
        authNotice = message
        wsManager.disconnect()
        let current = settingsManager.configPublished
        settingsManager.updateConfig(
            GatewayConfig(
                gatewayUrl: current.gatewayUrl,
                accountId: "",
                accessToken: "",
                refreshToken: "",
                accessExpiresAt: "",
                refreshExpiresAt: "",
                deviceLabel: current.deviceLabel,
                token: current.token,
                pairedBackendId: current.pairedBackendId,
                pairedBackendLabel: current.pairedBackendLabel,
                asrMode: current.asrMode,
                asrProfileId: current.asrProfileId
            )
        )
    }

    private func scheduleTokenRefresh(for config: GatewayConfig) {
        tokenRefreshTask?.cancel()
        guard !config.accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !config.refreshToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            tokenRefreshTask = nil
            return
        }
        let delay = tokenRefreshDelayNanoseconds(accessExpiresAt: config.accessExpiresAt)
        tokenRefreshTask = Task {
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
            do {
                let session = try await GatewayAuthClient.refresh(
                    gatewayUrl: config.gatewayUrl,
                    refreshToken: config.refreshToken
                )
                await MainActor.run {
                    let current = settingsManager.configPublished
                    settingsManager.updateConfig(
                        GatewayConfig(
                            gatewayUrl: current.gatewayUrl,
                            accountId: session.accountId,
                            accessToken: session.accessToken,
                            refreshToken: session.refreshToken,
                            accessExpiresAt: session.accessExpiresAt,
                            refreshExpiresAt: session.refreshExpiresAt,
                            deviceLabel: current.deviceLabel,
                            token: current.token,
                            pairedBackendId: current.pairedBackendId,
                            pairedBackendLabel: current.pairedBackendLabel,
                            asrMode: current.asrMode,
                            asrProfileId: current.asrProfileId
                        )
                    )
                }
            } catch {
                await MainActor.run {
                    clearAuthSession(message: "会话已过期，请重新登录")
                }
            }
        }
    }

    private func applySelectedProfile() {
        wsManager.syncProfiles(settingsManager.profiles)
        wsManager.applyProfile(
            settingsManager.selectedProfile,
            deviceLabel: settingsManager.config.deviceLabel,
            accessToken: settingsManager.config.accessToken
        )
    }
}

private func isTerminalAuthError(_ code: String) -> Bool {
    let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    return normalized == "INVALID_ACCESS_TOKEN" ||
        normalized == "EXPIRED_ACCESS_TOKEN" ||
        normalized == "ACCESS_TOKEN_EXPIRED" ||
        normalized == "ACCESS_TOKEN_REVOKED"
}

private func tokenRefreshDelayNanoseconds(accessExpiresAt: String) -> UInt64 {
    let fallbackSeconds: TimeInterval = 5 * 60
    guard let expiresAt = parseIsoDate(accessExpiresAt) else {
        return UInt64(fallbackSeconds * 1_000_000_000)
    }
    let refreshAt = expiresAt.addingTimeInterval(-2 * 60)
    let seconds = max(refreshAt.timeIntervalSinceNow, 10)
    return UInt64(seconds * 1_000_000_000)
}

private func parseIsoDate(_ value: String) -> Date? {
    guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
    let withFractional = ISO8601DateFormatter()
    withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = withFractional.date(from: value) {
        return date
    }
    return ISO8601DateFormatter().date(from: value)
}

final class BosonRemoteControlAppDelegate: UIResponder, UIApplicationDelegate {
    func application(
        _: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        return true
    }
}
