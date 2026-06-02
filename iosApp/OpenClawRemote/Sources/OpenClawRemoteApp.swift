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
    @StateObject private var messageSpeechController: MessageSpeechController
    @StateObject private var scheduledTaskStore = ScheduledTaskStore()
    @StateObject private var agentTaskService: AgentTaskService
    @StateObject private var recordingStore: RecordingStore
    @StateObject private var headsetSettingsStore = HeadsetSettingsStore()

    @State private var isDark = false
    @State private var authNotice: String? = nil
    @State private var walletNotice: String? = nil
    @State private var tokenRefreshTask: Task<Void, Never>? = nil
    @State private var assistantSpeechTrigger = AssistantSpeechTrigger()

    init() {
        let settings = SettingsManager()
        _settingsManager = StateObject(wrappedValue: settings)
        let manager = WebSocketManager(
            deviceLabel: settings.config.deviceLabel.isEmpty ? "我的设备" : settings.config.deviceLabel,
            accessToken: settings.config.accessToken
        )
        manager.syncProfiles(settings.profiles)
        _wsManager = StateObject(wrappedValue: manager)
        let taskService = AgentTaskService()
        taskService.bind(to: manager)
        _agentTaskService = StateObject(wrappedValue: taskService)
        let recordings = RecordingStore()
        _recordingStore = StateObject(wrappedValue: recordings)
        let speechController = MessageSpeechController(
            initialSoundPlaybackEnabled: settings.soundPlaybackEnabled,
            persistSoundPlaybackEnabled: { enabled in
                settings.updateSoundPlaybackEnabled(enabled)
            }
        )
        speechController.syncConfiguration(settings.config)
        _messageSpeechController = StateObject(wrappedValue: speechController)
        _headsetController = StateObject(wrappedValue: HeadsetConversationController(
            wsManager: manager,
            settingsManager: settings,
            recordingStore: recordings,
            soundPlaybackController: speechController
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
                        onAuthenticated: { session, gatewayUrl, terminalLabel, loginMode, phoneNumber in
                            applyAuthSession(session, gatewayUrl: gatewayUrl, terminalLabel: terminalLabel, loginMode: loginMode, phoneNumber: phoneNumber)
                        },
                        onNoticeShown: {
                            authNotice = nil
                        }
                    )
                } else {
                    RootTabView(
                        wsManager: wsManager,
                        settingsManager: settingsManager,
                        audioRecorder: audioRecorder,
                        headsetController: headsetController,
                        messageSpeechController: messageSpeechController,
                        scheduledTaskStore: scheduledTaskStore,
                        agentTaskService: agentTaskService,
                        recordingStore: recordingStore,
                        headsetSettingsStore: headsetSettingsStore,
                        isDark: isDark,
                        colors: colors,
                        onToggleTheme: { isDark.toggle() },
                        onSelectProfile: { profileId in
                            settingsManager.selectProfile(profileId)
                            applySelectedProfile()
                        },
                        onRequestPair: { backendId in
                            applySelectedProfile()
                            wsManager.requestPair(backendId: backendId)
                        },
                        onQRCodeScanned: { scannedText in
                            handleQRParsed(scannedText)
                        },
                        onSwitchAccount: {
                            clearAuthSession(message: "请登录新账号")
                        },
                        onLogout: {
                            clearAuthSession(message: "已退出登录")
                        },
                        walletNotice: $walletNotice
                    )
                }
            }
            .preferredColorScheme(isDark ? .dark : .light)
            .onReceive(wsManager.messageChannel) { event in
                handleWebSocketEvent(event)
            }
            .onReceive(settingsManager.$configPublished) { config in
                scheduleTokenRefresh(for: config)
                messageSpeechController.syncConfiguration(config)
            }
            .onReceive(settingsManager.$soundPlaybackEnabled) { enabled in
                messageSpeechController.syncSoundPlaybackEnabled(enabled)
            }
            .onAppear {
                let isSystemDark = UITraitCollection.current.userInterfaceStyle == .dark
                isDark = isSystemDark
                scheduleTokenRefresh(for: settingsManager.configPublished)
                if !settingsManager.configPublished.accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Task {
                        if await refreshAuthSessionIfNeeded(force: false) {
                            applySelectedProfile()
                        }
                    }
                }
                headsetController.start()
            }
        }
    }

    private func handleQRParsed(_ scannedText: String) {
        guard !settingsManager.configPublished.accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            authNotice = "请先登录账号，再扫码配对"
            return
        }
        Task {
            guard await refreshAuthSessionIfNeeded(force: false) else { return }
            await MainActor.run {
                processQRParsed(scannedText)
            }
        }
    }

    private func processQRParsed(_ scannedText: String) {
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
            let authGatewayUrl = settingsManager.config.gatewayUrl
            let accessToken = settingsManager.config.accessToken
            Task {
                do {
                    _ = try await GatewayAuthClient.upsertAccountAgent(
                        gatewayUrl: authGatewayUrl,
                        accessToken: accessToken,
                        profile: profile.toGatewayAccountAgentProfile()
                    )
                } catch {
                    await MainActor.run {
                        wsManager.addLocalMessage("Agent 配置同步失败，请稍后重试", senderId: "assistant")
                    }
                    return
                }
                await MainActor.run {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        wsManager.requestPair(backendId: backendId)
                    }
                }
            }
        case .error:
            break
        }
    }

    private func handleWebSocketEvent(_ event: WsMessageEvent) {
        switch event {
        case .registered(_):
            restoreLongRecordingJobs()
        case .paired(let profileId, let backendId, let backendLabel):
            settingsManager.updatePairedBackend(backendId, backendLabel, profileId: profileId)
        case .unpaired(let profileId):
            settingsManager.updatePairedBackend(nil, nil, profileId: profileId)
        case .sessionPreempted(let replacementTerminalLabel):
            let suffix = replacementTerminalLabel
                .flatMap { $0.isEmpty ? nil : "：\($0)" } ?? ""
            clearAuthSession(message: "账号已在另一台设备登录\(suffix)")
        case .error(let code, let message):
            if code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == "PAYMENT_REQUIRED" {
                walletNotice = message.isEmpty ? "余额不足，请开通套餐或充值余额" : message
                return
            }
            switch authRecoveryAction(forWebSocketErrorCode: code) {
            case .refreshSession:
                Task {
                    if await refreshAuthSessionIfNeeded(force: true) {
                        await MainActor.run {
                            applySelectedProfile()
                        }
                    }
                }
            case .requireLogin:
                clearAuthSession(message: "登录状态已过期，请重新登录")
            case .none:
                break
            }
        case .newMessage(let profileId, _):
            let replies = assistantSpeechTrigger.onMessagesChanged(wsManager.messages)
            if !replies.isEmpty, !headsetController.isAwaitingOrPlayingReply {
                messageSpeechController.enqueueAssistantReplies(
                    texts: replies.map(\.content),
                    config: settingsManager.config(forProfileId: profileId)
                )
            }
        case .taskListResponse,
             .taskCreateResponse,
             .taskUpdateResponse,
             .taskDeleteResponse,
             .approvalHistoryResponse:
            break
        case .asrResult(let payload):
            if payload.success, let text = payload.text {
                recordingStore.updateAsrText(clientMessageId: payload.clientMessageId, text: text)
            } else if let error = payload.error {
                recordingStore.updateAsrFailure(clientMessageId: payload.clientMessageId, error: error)
            }
        case .recordingEvent(let payload):
            recordingStore.appendEvent(payload)
        }
    }

    private func restoreLongRecordingJobs() {
        let candidates = recordingStore.items.filter { item in
            (item.processingStatus == .queued || item.processingStatus == .processing)
                && item.asrJobId?.isEmpty == false
        }
        for recording in candidates {
            guard let jobId = recording.asrJobId else { continue }
            wsManager.fetchLongRecordingAsrJob(jobId: jobId) { payload in
                guard let payload else { return }
                let recordingId = payload.recordingId ?? recording.id
                recordingStore.updateAsrJob(
                    recordingId: recordingId,
                    jobId: payload.jobId,
                    uploadProgress: payload.uploadProgress,
                    asrProgress: payload.asrProgress
                )
                if payload.status == "failed",
                   let error = payload.error,
                   let clientMessageId = payload.clientMessageId ?? recording.clientMessageId {
                    recordingStore.updateAsrFailure(clientMessageId: clientMessageId, error: error)
                }
            }
        }
    }

    private func applyAuthSession(
        _ session: GatewayAuthSessionResponse,
        gatewayUrl: String,
        terminalLabel: String,
        loginMode: String,
        phoneNumber: String
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
                asrProfileId: current.asrProfileId,
                ttsEngine: current.ttsEngine,
                minimaxApiKey: current.minimaxApiKey,
                minimaxVoiceId: current.minimaxVoiceId,
                lastLoginMode: loginMode,
                lastPhoneNumber: phoneNumber
            )
        )
        authNotice = nil
        applySelectedProfile()
        Task {
            await syncAccountAgentsAfterLogin(gatewayUrl: gatewayUrl, accessToken: session.accessToken)
        }
    }

    private func clearAuthSession(message: String) {
        tokenRefreshTask?.cancel()
        tokenRefreshTask = nil
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
                asrProfileId: current.asrProfileId,
                ttsEngine: current.ttsEngine,
                minimaxApiKey: current.minimaxApiKey,
                minimaxVoiceId: current.minimaxVoiceId,
                lastLoginMode: current.lastLoginMode,
                lastPhoneNumber: current.lastPhoneNumber
            )
        )
    }

    private func syncAccountAgentsAfterLogin(gatewayUrl: String, accessToken: String) async {
        do {
            let remoteProfiles = try await GatewayAuthClient.listAccountAgents(
                gatewayUrl: gatewayUrl,
                accessToken: accessToken
            )
            if !remoteProfiles.isEmpty {
                await MainActor.run {
                    settingsManager.replaceAccountProfiles(remoteProfiles)
                    applySelectedProfile()
                }
                return
            }
            let localProfiles = await MainActor.run {
                settingsManager.profiles.filter { !$0.backendId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            }
            for profile in localProfiles {
                _ = try? await GatewayAuthClient.upsertAccountAgent(
                    gatewayUrl: gatewayUrl,
                    accessToken: accessToken,
                    profile: profile.toGatewayAccountAgentProfile()
                )
            }
        } catch {
            await MainActor.run {
                authNotice = "Agent 配置同步失败，已保留本地配置"
            }
        }
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
            _ = await refreshAuthSessionIfNeeded(force: true)
        }
    }

    private func refreshAuthSessionIfNeeded(force: Bool) async -> Bool {
        let config = settingsManager.configPublished
        guard !config.accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            await MainActor.run {
                clearAuthSession(message: "请先登录账号")
            }
            return false
        }
        guard !config.refreshToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            await MainActor.run {
                clearAuthSession(message: "登录状态已过期，请重新登录")
            }
            return false
        }
        guard force || shouldRefreshAccessToken(accessExpiresAt: config.accessExpiresAt) else {
            return true
        }

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
                        asrProfileId: current.asrProfileId,
                        ttsEngine: current.ttsEngine,
                        minimaxApiKey: current.minimaxApiKey,
                        minimaxVoiceId: current.minimaxVoiceId
                    )
                )
                authNotice = nil
            }
            return true
        } catch {
            if refreshFailureRequiresLogin(error.localizedDescription) {
                await MainActor.run {
                    clearAuthSession(message: "登录状态已过期，请重新登录")
                }
            }
            return false
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

final class BosonRemoteControlAppDelegate: UIResponder, UIApplicationDelegate {
    func application(
        _: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        return true
    }
}

private extension AgentProfile {
    func toGatewayAccountAgentProfile() -> GatewayAccountAgentProfile {
        GatewayAccountAgentProfile(
            agentProfileId: id,
            platform: platform.rawValue,
            displayName: resolvedDisplayName,
            gatewayUrl: gatewayUrl,
            backendId: backendId,
            backendLabel: backendLabel ?? resolvedDisplayName,
            isPaired: isPaired,
            asrMode: asrMode == "backend" ? "backend" : "router",
            sortOrder: sortIndex,
            pinned: isPinned
        )
    }
}
