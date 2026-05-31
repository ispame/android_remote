import Foundation
import Combine

private struct ProfileRuntimeState {
    var registeredBackendId: String?
    var preferredBackendId: String?
    var preferredBackendLabel: String?
    var pairingState: PairingState = .unpaired
    var messages: [ChatMessage] = []
    var historyLoading = false
    var historyError: String?
    var historyHasMore = false
    var historyLoaded = false
    var loadedHistoryKeys = Set<String>()
    var oldestHistoryTimestamp: String?
    var lastAutoHistoryRequestAt: Date?
}

private struct PendingAudioContext {
    let profileId: String
    let recordingId: String?
    let recordingPrompt: String?
}

func shouldDropAsrFailureMessage(_ error: String?) -> Bool {
    true
}

final class WebSocketManager: ObservableObject {
    private var webSocketTask: URLSessionWebSocketTask?
    private let session = URLSession(configuration: .default)

    @Published var connectionState: ConnectionState = .disconnected {
        didSet {
            guard oldValue != connectionState else { return }
            refreshKnownStatusActivities()
        }
    }
    @Published var pairingState: PairingState = .unpaired {
        didSet {
            guard oldValue != pairingState, let activeProfileId else { return }
            refreshStatusActivity(profileId: activeProfileId)
        }
    }
    @Published private(set) var messages: [ChatMessage] = []
    @Published private(set) var historyLoading = false
    @Published private(set) var historyError: String?
    @Published private(set) var historyHasMore = false
    @Published private(set) var historyLoaded = false
    @Published private(set) var unreadCounts: [String: Int] = [:]
    @Published private(set) var agentListActivities: [String: AgentListActivity] = [:]

    private let messageSubject = PassthroughSubject<WsMessageEvent, Never>()
    var messageChannel: AnyPublisher<WsMessageEvent, Never> {
        messageSubject.eraseToAnyPublisher()
    }

    private var activeProfileId: String?
    private var activePlatform: AgentPlatform = .openclaw
    private var profileStates: [String: ProfileRuntimeState] = [:]
    private var knownProfiles: [String: AgentProfile] = [:]
    private var profileIdsByBackendId: [String: String] = [:]
    private var pendingHistoryProfileId: String?
    private var pendingAudioContextsByClientMessageId: [String: PendingAudioContext] = [:]

    private var accountId: String?
    private var registeredBackendId: String?
    private var deviceLabel: String
    private var accessToken: String
    private var asrMode = "router"
    private var asrProfileId = ""
    private var preferredBackendId: String?
    private var preferredBackendLabel: String?
    private var currentUrlString: String?
    private var reconnectWorkItem: DispatchWorkItem?
    private var reconnectAttempts = 0
    private var intentionalDisconnect = false
    private var socketGeneration = 0
    private let reconnectBaseDelay: TimeInterval = 2
    private let reconnectMaxDelay: TimeInterval = 30

    private var pendingAcks: [Int: (MessageStatus) -> Void] = [:]
    private var receivedMessageKeys = Set<String>()
    private var receivedMessageKeyOrder: [String] = []
    private var loadedHistoryKeys = Set<String>()
    private var oldestHistoryTimestamp: String?
    private var lastAutoHistoryRequestAt: Date?

    init(deviceLabel: String, accessToken: String) {
        self.deviceLabel = deviceLabel
        self.accessToken = accessToken
    }

    func syncProfiles(_ profiles: [AgentProfile]) {
        let knownIds = Set(profiles.map(\.id))
        knownProfiles = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })
        profileStates = profileStates.filter { knownIds.contains($0.key) }
        unreadCounts = unreadCounts.filter { knownIds.contains($0.key) }
        agentListActivities = agentListActivities.filter { knownIds.contains($0.key) }
        profileIdsByBackendId = [:]

        for profile in profiles {
            if !profile.backendId.isEmpty {
                profileIdsByBackendId[profile.backendId] = profile.id
            }
            if profileStates[profile.id] == nil {
                var state = ProfileRuntimeState()
                if profile.isPaired, !profile.backendId.isEmpty {
                    state.registeredBackendId = profile.backendId
                    state.preferredBackendId = profile.backendId
                    state.preferredBackendLabel = profile.backendLabel ?? profile.resolvedDisplayName
                    state.pairingState = .paired
                }
                profileStates[profile.id] = state
            }
            if unreadCounts[profile.id] == nil {
                unreadCounts[profile.id] = 0
            }
        }
        refreshKnownStatusActivities(markChanges: false)
    }

    func applyProfile(_ profile: AgentProfile, deviceLabel: String, accessToken: String) {
        persistActiveRuntimeState()

        activeProfileId = profile.id
        activePlatform = profile.platform
        if !profile.backendId.isEmpty {
            profileIdsByBackendId[profile.backendId] = profile.id
        }
        updateCredentials(deviceLabel: deviceLabel, accessToken: accessToken)
        updateAsrConfiguration(mode: profile.asrMode, profileId: profile.asrProfileId)
        unreadCounts[profile.id] = 0

        var state = profileStates[profile.id] ?? ProfileRuntimeState()
        state.preferredBackendId = profile.isPaired && !profile.backendId.isEmpty ? profile.backendId : nil
        state.preferredBackendLabel = profile.isPaired ? (profile.backendLabel ?? profile.resolvedDisplayName) : nil
        state.registeredBackendId = profile.isPaired && !profile.backendId.isEmpty ? profile.backendId : nil
        state.pairingState = profile.isPaired && !profile.backendId.isEmpty ? .paired : .unpaired
        profileStates[profile.id] = state
        loadRuntimeState(state)
        guard !self.accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            suspendSocketForMissingAuth()
            return
        }
        connect(to: profile.gatewayUrl)
    }

    func unreadCount(for profileId: String) -> Int {
        unreadCounts[profileId] ?? 0
    }

    func pairingState(for profile: AgentProfile) -> PairingState {
        if profile.id == activeProfileId {
            return pairingState
        }
        return profileStates[profile.id]?.pairingState ?? (profile.isPaired ? .paired : .unpaired)
    }

    func availabilityStatus(for profile: AgentProfile) -> AgentAvailabilityStatus {
        if profile.backendId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .unconfigured
        }

        switch pairingState(for: profile) {
        case .pending:
            return .pairing
        case .unpaired:
            return .unpaired
        case .paired:
            switch connectionState {
            case .registered:
                return .available
            case .connecting, .connected:
                return .connecting
            case .disconnected:
                return .offline
            case .paired:
                return .available
            }
        }
    }

    private func refreshKnownStatusActivities(markChanges: Bool = true) {
        for profile in knownProfiles.values {
            recordStatusActivity(
                profileId: profile.id,
                status: availabilityStatus(for: profile),
                markChange: markChanges
            )
        }
    }

    private func refreshStatusActivity(profileId: String, markChanges: Bool = true) {
        guard let profile = knownProfiles[profileId] else { return }
        recordStatusActivity(
            profileId: profileId,
            status: availabilityStatus(for: profile),
            markChange: markChanges
        )
    }

    private func recordStatusActivity(
        profileId: String,
        status: AgentAvailabilityStatus,
        markChange: Bool,
        at date: Date = Date()
    ) {
        var activity = agentListActivities[profileId] ?? AgentListActivity()
        if activity.lastStatus == nil {
            activity.lastStatus = status
        } else if activity.lastStatus != status {
            activity.lastStatus = status
            if markChange {
                activity.lastStatusChangedAt = date
            }
        }
        setAgentListActivity(activity, profileId: profileId)
    }

    func clearProfileState(profileId: String) {
        profileStates[profileId] = ProfileRuntimeState()
        unreadCounts[profileId] = 0
        setAgentListActivity(AgentListActivity(), profileId: profileId)
        if profileId == activeProfileId {
            loadRuntimeState(ProfileRuntimeState())
        }
        refreshStatusActivity(profileId: profileId, markChanges: false)
    }

    func removeProfileState(profileId: String) {
        profileStates.removeValue(forKey: profileId)
        knownProfiles.removeValue(forKey: profileId)
        unreadCounts.removeValue(forKey: profileId)
        agentListActivities.removeValue(forKey: profileId)
        profileIdsByBackendId = profileIdsByBackendId.filter { $0.value != profileId }
        pendingAudioContextsByClientMessageId = pendingAudioContextsByClientMessageId.filter { $0.value.profileId != profileId }
        if pendingHistoryProfileId == profileId {
            pendingHistoryProfileId = nil
        }
    }

    func connect(to urlString: String) {
        guard !accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            suspendSocketForMissingAuth()
            return
        }
        guard let normalizedUrl = normalizeGatewayUrl(urlString) else {
            connectionState = .disconnected
            return
        }

        if connectionState != .disconnected, currentUrlString == normalizedUrl {
            return
        }

        intentionalDisconnect = false
        reconnectAttempts = 0
        cancelReconnect()
        currentUrlString = normalizedUrl
        if connectionState != .disconnected {
            webSocketTask?.cancel(with: .goingAway, reason: nil)
            webSocketTask = nil
        }
        openSocket(to: normalizedUrl)
    }

    func reconnect(to urlString: String) {
        guard let normalizedUrl = normalizeGatewayUrl(urlString) else { return }
        currentUrlString = normalizedUrl
        intentionalDisconnect = false
        cancelReconnect()
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        openSocket(to: normalizedUrl)
    }

    func updateCredentials(deviceLabel: String, accessToken: String) {
        self.deviceLabel = deviceLabel
        self.accessToken = accessToken
    }

    func restorePairing(backendId: String?, backendLabel: String?) {
        preferredBackendId = backendId
        preferredBackendLabel = backendLabel
        registeredBackendId = backendId
        pairingState = backendId == nil ? .unpaired : .paired
        persistActiveRuntimeState()
    }

    func rememberBackendForPairing(_ backendId: String) {
        preferredBackendId = backendId
        preferredBackendLabel = backendId
        pairingState = .pending
        persistActiveRuntimeState()
        if connectionState == .registered {
            requestPair(backendId: backendId)
        }
    }

    func applyConfiguration(
        gatewayUrl: String,
        deviceLabel: String,
        accessToken: String,
        pairedBackendId: String?,
        pairedBackendLabel: String?,
        asrMode: String = "router",
        asrProfileId: String = ""
    ) {
        updateCredentials(deviceLabel: deviceLabel, accessToken: accessToken)
        updateAsrConfiguration(mode: asrMode, profileId: asrProfileId)
        restorePairing(backendId: pairedBackendId, backendLabel: pairedBackendLabel)
        connect(to: gatewayUrl)
    }

    func updateAsrConfiguration(mode: String, profileId: String) {
        self.asrMode = mode == "backend" ? "backend" : "router"
        self.asrProfileId = self.asrMode == "router" ? profileId : ""
    }

    func disconnect() {
        persistActiveRuntimeState()
        intentionalDisconnect = true
        cancelReconnect()
        socketGeneration += 1
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        connectionState = .disconnected
        registeredBackendId = nil
        preferredBackendId = nil
        preferredBackendLabel = nil
        pairingState = .unpaired
    }

    func requestPair(backendId: String) {
        guard (connectionState == .registered || connectionState == .paired), !backendId.isEmpty else { return }
        preferredBackendId = backendId
        preferredBackendLabel = backendId
        pairingState = .pending
        persistActiveRuntimeState()
        sendJson([
            "type": "pair_request",
            "backend_id": backendId,
            "terminal_label": deviceLabel,
            "app_metadata": [
                "platform": "ios"
            ]
        ])
    }

    func cancelPair() {
        pairingState = .unpaired
        persistActiveRuntimeState()
    }

    func sendText(_ text: String) {
        guard pairingState == .paired, let backendId = registeredBackendId else { return }
        let messageId = "msg_\(UUID().uuidString)"
        addLocalMessageWithStatus(text, senderId: "user", status: .sending, seq: nil)
        sendJson([
            "type": "message",
            "backend_id": backendId,
            "message_id": messageId,
            "content": text,
            "content_type": "text",
            "timestamp": isoTimestamp()
        ])
    }

    func requestRecentHistory(rounds: Int = 15, force: Bool = false) {
        if historyLoading { return }
        if !force && historyLoaded && !historyHasMore { return }
        guard pairingState == .paired, let backendId = registeredBackendId else {
            historyLoading = false
            historyError = "请先配对 \(activePlatform.label)"
            historyHasMore = false
            persistActiveRuntimeState()
            return
        }

        historyLoading = true
        historyError = nil
        pendingHistoryProfileId = activeProfileId
        var frame: [String: Any] = [
            "type": "history_request",
            "backend_id": backendId,
            "session_key": "current",
            "limit": max(1, rounds) * 2
        ]
        if !force, let oldestHistoryTimestamp {
            frame["before_timestamp"] = oldestHistoryTimestamp
        }
        persistActiveRuntimeState()
        sendJson(frame)
    }

    @discardableResult
    func requestTaskList(requestId: String, backendId: String, includeDisabled: Bool) -> Bool {
        guard canSendBackendRequest(backendId) else { return false }
        sendJson([
            "type": "task_list_request",
            "request_id": requestId,
            "backend_id": backendId,
            "include_disabled": includeDisabled
        ])
        return true
    }

    @discardableResult
    func createAgentTask(
        requestId: String,
        backendId: String,
        title: String,
        prompt: String,
        schedule: String?,
        enabled: Bool
    ) -> Bool {
        guard canSendBackendRequest(backendId) else { return false }
        var frame: [String: Any] = [
            "type": "task_create_request",
            "request_id": requestId,
            "backend_id": backendId,
            "title": title,
            "prompt": prompt,
            "enabled": enabled
        ]
        if let schedule, !schedule.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            frame["schedule"] = schedule
        }
        sendJson(frame)
        return true
    }

    @discardableResult
    func updateAgentTask(
        requestId: String,
        backendId: String,
        taskId: String,
        title: String,
        prompt: String,
        schedule: String,
        enabled: Bool
    ) -> Bool {
        guard canSendBackendRequest(backendId) else { return false }
        sendJson([
            "type": "task_update_request",
            "request_id": requestId,
            "backend_id": backendId,
            "task_id": taskId,
            "title": title,
            "prompt": prompt,
            "schedule": schedule,
            "enabled": enabled
        ])
        return true
    }

    @discardableResult
    func deleteAgentTask(requestId: String, backendId: String, taskId: String) -> Bool {
        guard canSendBackendRequest(backendId) else { return false }
        sendJson([
            "type": "task_delete_request",
            "request_id": requestId,
            "backend_id": backendId,
            "task_id": taskId
        ])
        return true
    }

    @discardableResult
    func requestApprovalHistory(requestId: String, backendId: String, limit: Int) -> Bool {
        guard canSendBackendRequest(backendId) else { return false }
        sendJson([
            "type": "approval_history_request",
            "request_id": requestId,
            "backend_id": backendId,
            "limit": limit
        ])
        return true
    }

    func sendAudio(_ data: Data) {
        guard pairingState == .paired, let backendId = registeredBackendId else { return }
        let base64 = data.base64EncodedString()
        let messageId = "msg_\(UUID().uuidString)"
        let clientMessageId = UUID().uuidString
        let asrPayload = AudioAsrPayload.chat(mode: asrMode, profileId: asrProfileId).jsonObject
        let frame: [String: Any] = [
            "type": "message",
            "backend_id": backendId,
            "message_id": messageId,
            "client_message_id": clientMessageId,
            "content": base64,
            "content_type": "audio",
            "timestamp": isoTimestamp(),
            "audio": [
                "format": "wav",
                "codec": "pcm_s16le",
                "sample_rate": 16000,
                "channels": 1
            ],
            "asr": asrPayload
        ]
        addLocalMessageWithStatus("正在识别...", senderId: "user", status: .sending, seq: nil, clientMessageId: clientMessageId)
        if let activeProfileId {
            pendingAudioContextsByClientMessageId[clientMessageId] = PendingAudioContext(
                profileId: activeProfileId,
                recordingId: nil,
                recordingPrompt: nil
            )
        }
        sendJson(frame)
    }

    @discardableResult
    func sendAudio(_ data: Data, profileId: String) -> Bool {
        sendAudioForAsr(data, profileId: profileId) != nil
    }

    @discardableResult
    func sendAudioForAsr(_ data: Data, profileId: String) -> String? {
        sendAudioForAsr(
            data,
            profileId: profileId,
            asrPayload: AudioAsrPayload.chat(mode: asrMode, profileId: asrProfileId).jsonObject
        )
    }

    @discardableResult
    func sendRecordingAudioForAsr(
        _ data: Data,
        profileId: String,
        settings: RecordingSettings,
        source: RecordingInputSource,
        recordingId: String,
        recordingType: RecordingType,
        prompt: String
    ) -> String? {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        return sendAudioForAsr(
            data,
            profileId: profileId,
            asrPayload: AudioAsrPayload.recording(
                settings: settings,
                source: source,
                recordingId: recordingId,
                recordingType: recordingType,
                prompt: trimmedPrompt
            ).jsonObject,
            recordingId: recordingId,
            recordingPrompt: trimmedPrompt.isEmpty ? nil : trimmedPrompt
        )
    }

    @discardableResult
    private func sendAudioForAsr(
        _ data: Data,
        profileId: String,
        asrPayload: [String: Any],
        recordingId: String? = nil,
        recordingPrompt: String? = nil
    ) -> String? {
        let state = profileId == activeProfileId
            ? currentRuntimeStateSnapshot()
            : (profileStates[profileId] ?? ProfileRuntimeState())
        guard state.pairingState == .paired, let backendId = state.registeredBackendId else { return nil }

        let base64 = data.base64EncodedString()
        let messageId = "msg_\(UUID().uuidString)"
        let clientMessageId = UUID().uuidString
        let frame: [String: Any] = [
            "type": "message",
            "backend_id": backendId,
            "message_id": messageId,
            "client_message_id": clientMessageId,
            "content": base64,
            "content_type": "audio",
            "timestamp": isoTimestamp(),
            "audio": [
                "format": "wav",
                "codec": "pcm_s16le",
                "sample_rate": 16000,
                "channels": 1
            ],
            "asr": asrPayload
        ]
        let msg = ChatMessage(
            content: "正在识别...",
            timestamp: timestamp(),
            senderId: "user",
            status: .sending,
            seq: nil,
            clientMessageId: clientMessageId
        )
        appendMessage(msg, profileId: profileId)
        pendingAudioContextsByClientMessageId[clientMessageId] = PendingAudioContext(
            profileId: profileId,
            recordingId: recordingId,
            recordingPrompt: recordingPrompt
        )
        sendJson(frame)
        return clientMessageId
    }

    func unpair() {
        guard let backendId = registeredBackendId, let profileId = activeProfileId else { return }
        unpair(profileId: profileId, backendId: backendId)
    }

    func unpair(profileId: String, backendId: String) {
        guard !backendId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        sendJson([
            "type": "unpair",
            "backend_id": backendId
        ])
        if profileId == activeProfileId {
            registeredBackendId = nil
            preferredBackendId = nil
            preferredBackendLabel = nil
            pairingState = .unpaired
            persistActiveRuntimeState()
        } else {
            var state = profileStates[profileId] ?? ProfileRuntimeState()
            state.registeredBackendId = nil
            state.preferredBackendId = nil
            state.preferredBackendLabel = nil
            state.pairingState = .unpaired
            profileStates[profileId] = state
            refreshStatusActivity(profileId: profileId)
        }
        profileIdsByBackendId.removeValue(forKey: backendId)
        messageSubject.send(.unpaired(profileId: profileId))
    }

    private func canSendBackendRequest(_ backendId: String) -> Bool {
        let normalizedBackendId = backendId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedBackendId.isEmpty else { return false }
        switch connectionState {
        case .registered, .paired:
            return true
        case .connecting, .connected, .disconnected:
            return false
        }
    }

    private func normalizeGatewayUrl(_ urlString: String) -> String? {
        var urlStr = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if urlStr.isEmpty { return nil }
        if !urlStr.hasPrefix("ws://") && !urlStr.hasPrefix("wss://") {
            urlStr = "wss://" + urlStr
        }
        if !urlStr.hasSuffix("/ws") {
            urlStr = urlStr.hasSuffix("/") ? urlStr + "ws" : urlStr + "/ws"
        }
        return URL(string: urlStr) == nil ? nil : urlStr
    }

    private func openSocket(to urlString: String) {
        guard !intentionalDisconnect, let url = URL(string: urlString) else {
            connectionState = .disconnected
            return
        }

        socketGeneration += 1
        let generation = socketGeneration
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = session.webSocketTask(with: url)
        connectionState = .connecting
        webSocketTask?.resume()
        connectionState = .connected
        sendRegister()
        receiveMessage(generation: generation)
    }

    private func cancelReconnect() {
        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil
    }

    private func handleTransientDisconnect() {
        guard !intentionalDisconnect else { return }
        webSocketTask = nil
        connectionState = .connecting
        scheduleReconnect()
    }

    private func suspendSocketForMissingAuth() {
        intentionalDisconnect = true
        cancelReconnect()
        socketGeneration += 1
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        connectionState = .disconnected
    }

    private func scheduleReconnect() {
        guard let urlString = currentUrlString, !intentionalDisconnect else { return }
        cancelReconnect()

        let delay = min(reconnectMaxDelay, reconnectBaseDelay * pow(2, Double(reconnectAttempts)))
        reconnectAttempts += 1
        let item = DispatchWorkItem { [weak self] in
            self?.openSocket(to: urlString)
        }
        reconnectWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func sendRegister() {
        sendJson([
            "type": "app_register",
            "access_token": accessToken,
            "terminal_label": deviceLabel,
            "platform": "ios",
            "app_version": "2.0.0-native"
        ])
    }

    private func sendJson(_ dict: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let text = String(data: data, encoding: .utf8) else { return }
        webSocketTask?.send(.string(text)) { _ in }
    }

    private func sendAck(_ messageId: String) {
        sendJson([
            "type": "message_ack",
            "message_id": messageId
        ])
    }

    private func deliveryAckId(from json: [String: Any]) -> String? {
        if let seq = json["seq"] as? Int {
            return String(seq)
        }
        if let seq = json["seq"] as? NSNumber {
            return seq.stringValue
        }
        guard let messageId = json["message_id"] as? String, !messageId.isEmpty else {
            return nil
        }
        return messageId
    }

    private func receivedMessageKey(from json: [String: Any]) -> String? {
        if let messageId = json["message_id"] as? String, !messageId.isEmpty {
            return "message_id:\(messageId)"
        }
        if let seq = json["seq"] as? Int {
            return "seq:\(seq)"
        }
        if let seq = json["seq"] as? NSNumber {
            return "seq:\(seq.stringValue)"
        }
        return nil
    }

    private func rememberReceivedMessageKey(_ key: String) -> Bool {
        if receivedMessageKeys.contains(key) {
            return false
        }
        receivedMessageKeys.insert(key)
        receivedMessageKeyOrder.append(key)
        while receivedMessageKeyOrder.count > 500 {
            let removed = receivedMessageKeyOrder.removeFirst()
            receivedMessageKeys.remove(removed)
        }
        return true
    }

    private func receiveMessage(generation: Int) {
        webSocketTask?.receive { [weak self] result in
            guard let self = self, generation == self.socketGeneration else { return }
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self.handleMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self.handleMessage(text)
                    }
                @unknown default:
                    break
                }
                self.receiveMessage(generation: generation)
            case .failure:
                DispatchQueue.main.async {
                    guard generation == self.socketGeneration else { return }
                    self.handleTransientDisconnect()
                }
            }
        }
    }

    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            switch type {
            case "app_registered", "registered":
                let success = json["success"] as? Bool ?? false
                if success {
                    self.accountId = json["account_id"] as? String ?? self.accountId
                    self.connectionState = .registered
                    self.reconnectAttempts = 0
                    self.cancelReconnect()
                    let pairedBackends = (json["paired_backends"] as? [[String: Any]] ?? [])
                        .compactMap { $0["backend_id"] as? String }
                    if !pairedBackends.isEmpty {
                        self.preferredBackendId = (json["selected_backend_id"] as? String) ?? pairedBackends.first
                    }
                    self.messageSubject.send(.registered(self.accountId ?? ""))
                    if pairedBackends.isEmpty, let backendId = self.preferredBackendId ?? self.registeredBackendId {
                        self.requestPair(backendId: backendId)
                    }
                }

            case "session_preempted":
                self.intentionalDisconnect = true
                self.cancelReconnect()
                self.connectionState = .disconnected
                let replacement = json["replacement_terminal_label"] as? String
                if let replacement, !replacement.isEmpty {
                    self.addMessage("当前账号已在另一台终端接管：\(replacement)", senderId: "assistant")
                } else {
                    self.addMessage("当前账号已在另一台终端接管", senderId: "assistant")
                }
                self.messageSubject.send(.sessionPreempted(replacementTerminalLabel: replacement))
                self.webSocketTask?.cancel(with: .normalClosure, reason: nil)
                self.webSocketTask = nil

            case "pair_response":
                self.handlePairResponse(json)

            case "message":
                self.handleInboundMessage(json)

            case "asr_result":
                self.handleAsrResult(json)

            case "recording_event":
                if let payload = RecordingEventPayload(json: json) {
                    self.messageSubject.send(.recordingEvent(payload))
                }

            case "history_response":
                let backendId = json["backend_id"] as? String
                let responseProfileId = backendId.flatMap { self.profileId(forBackendId: $0) }
                    ?? self.pendingHistoryProfileId
                    ?? self.activeProfileId
                self.handleHistoryResponse(json, profileId: responseProfileId)

            case "task_list_response":
                self.messageSubject.send(.taskListResponse(TaskListResponsePayload(json: json)))

            case "task_create_response":
                self.messageSubject.send(.taskCreateResponse(TaskMutationResponsePayload(json: json)))

            case "task_update_response":
                self.messageSubject.send(.taskUpdateResponse(TaskMutationResponsePayload(json: json)))

            case "task_delete_response":
                self.messageSubject.send(.taskDeleteResponse(TaskMutationResponsePayload(json: json)))

            case "approval_history_response":
                self.messageSubject.send(.approvalHistoryResponse(ApprovalHistoryResponsePayload(json: json)))

            case "message_ack", "ack":
                break

            case "message_delivery_failed", "delivery_failed":
                let reason = json["reason"] as? String ?? "unknown"
                self.addMessage("消息发送失败: \(reason)", senderId: "assistant")

            case "ping":
                self.sendJson(["type": "pong"])

            case "pong":
                break

            case "unpaired":
                self.handleUnpaired(json)

            case "error":
                let code = json["code"] as? String ?? "unknown"
                let msg = json["message"] as? String ?? "未知错误"
                let authRecoveryAction = authRecoveryAction(forWebSocketErrorCode: code)
                if authRecoveryAction != .none {
                    let task = self.webSocketTask
                    self.intentionalDisconnect = true
                    self.cancelReconnect()
                    self.webSocketTask = nil
                    self.connectionState = .disconnected
                    self.messageSubject.send(.error(code: code, message: msg))
                    task?.cancel(with: .goingAway, reason: nil)
                    return
                }
                self.addMessage("错误 (\(code)): \(msg)", senderId: "assistant")
                self.messageSubject.send(.error(code: code, message: msg))

            default:
                break
            }
        }
    }

    private func handlePairResponse(_ json: [String: Any]) {
        let approve = (json["approved"] as? Bool) ?? (json["approve"] as? Bool) ?? false
        let backendId = json["backend_id"] as? String ?? ""
        let backendLabel = json["backend_label"] as? String ?? backendId
        let profileId = profileId(forBackendId: backendId) ?? activeProfileId

        guard let profileId else { return }
        if approve {
            if profileId == activeProfileId {
                registeredBackendId = backendId
                preferredBackendId = backendId
                preferredBackendLabel = backendLabel
                pairingState = .paired
                persistActiveRuntimeState()
                requestAutoHistorySync()
            } else {
                var state = profileStates[profileId] ?? ProfileRuntimeState()
                state.registeredBackendId = backendId
                state.preferredBackendId = backendId
                state.preferredBackendLabel = backendLabel
                state.pairingState = .paired
                profileStates[profileId] = state
                refreshStatusActivity(profileId: profileId)
            }
            profileIdsByBackendId[backendId] = profileId
            messageSubject.send(.paired(profileId: profileId, backendId: backendId, backendLabel: backendLabel))
        } else {
            if profileId == activeProfileId {
                pairingState = .unpaired
                persistActiveRuntimeState()
            } else {
                var state = profileStates[profileId] ?? ProfileRuntimeState()
                state.pairingState = .unpaired
                profileStates[profileId] = state
                refreshStatusActivity(profileId: profileId)
            }
            appendMessage("配对请求被拒绝", senderId: "assistant", profileId: profileId)
        }
    }

    private func handleInboundMessage(_ json: [String: Any]) {
        if let ackId = deliveryAckId(from: json) {
            sendAck(ackId)
        }
        if let key = receivedMessageKey(from: json), !rememberReceivedMessageKey(key) {
            return
        }
        guard let content = displayableBackendContent(json["content"] as? String ?? "") else { return }
        let backendId = (json["backend_id"] as? String) ?? (json["from"] as? String) ?? registeredBackendId ?? ""
        let profileId = profileId(forBackendId: backendId) ?? activeProfileId
        let message = HistoryMessagePayload.chatMessage(
            content: content,
            role: "assistant",
            item: json,
            fallbackTimestamp: timestamp()
        )
        appendMessage(message, profileId: profileId)
    }

    private func handleUnpaired(_ json: [String: Any]) {
        let targetId = (json["backend_id"] as? String) ?? (json["target_id"] as? String) ?? ""
        guard let profileId = profileId(forBackendId: targetId) ?? activeProfileId else { return }
        if profileId == activeProfileId {
            registeredBackendId = nil
            preferredBackendId = nil
            preferredBackendLabel = nil
            pairingState = .unpaired
            persistActiveRuntimeState()
        } else {
            var state = profileStates[profileId] ?? ProfileRuntimeState()
            state.registeredBackendId = nil
            state.preferredBackendId = nil
            state.preferredBackendLabel = nil
            state.pairingState = .unpaired
            profileStates[profileId] = state
            refreshStatusActivity(profileId: profileId)
        }
        messageSubject.send(.unpaired(profileId: profileId))
        appendMessage("已解除配对", senderId: "assistant", profileId: profileId)
    }

    private func requestAutoHistorySync() {
        guard pairingState == .paired else { return }
        let now = Date()
        if let lastAutoHistoryRequestAt, now.timeIntervalSince(lastAutoHistoryRequestAt) < 3 {
            return
        }
        lastAutoHistoryRequestAt = now
        persistActiveRuntimeState()
        requestRecentHistory(rounds: 15, force: true)
    }

    private func handleHistoryResponse(_ json: [String: Any], profileId: String?) {
        guard let profileId else { return }
        if pendingHistoryProfileId == nil || pendingHistoryProfileId == profileId {
            pendingHistoryProfileId = nil
        }
        var state = profileId == activeProfileId ? currentRuntimeStateSnapshot() : (profileStates[profileId] ?? ProfileRuntimeState())
        state.historyLoading = false
        let error = json["error"] as? String
        if let error, !error.isEmpty {
            state.historyError = error
            state.historyHasMore = false
            saveRuntimeState(state, profileId: profileId)
            return
        }

        let items = json["messages"] as? [[String: Any]] ?? []
        let parsed = items.compactMap { item -> ChatMessage? in
            guard let content = item["content"] as? String else { return nil }
            let role = item["role"] as? String ?? "assistant"
            let normalizedRole = role.lowercased()
            let displayContent: String
            if normalizedRole == "user" || normalizedRole == "human" {
                guard !self.shouldHideSystemNoise(content) else { return nil }
                displayContent = content
            } else {
                guard let sanitized = self.displayableBackendContent(content) else { return nil }
                displayContent = sanitized
            }
            return HistoryMessagePayload.chatMessage(content: displayContent, role: role, item: item)
        }

        if parsed.isEmpty {
            state.historyError = state.historyLoaded ? "已显示全部历史对话" : "还没有可读取的历史"
            state.historyHasMore = false
            state.historyLoaded = true
            saveRuntimeState(state, profileId: profileId)
            return
        }

        let existingKeys = Set(state.messages.map(messageHistoryKey))
        let newMessages = parsed.filter { message in
            let key = messageHistoryKey(message)
            return !existingKeys.contains(key) && !state.loadedHistoryKeys.contains(key)
        }
        state.loadedHistoryKeys.formUnion(parsed.map(messageHistoryKey))
        state.oldestHistoryTimestamp = (state.messages + parsed)
            .compactMap { $0.rawTimestamp }
            .min { lhs, rhs in
                let lhsTime = HistoryMessagePayload.date(from: lhs)?.timeIntervalSince1970 ?? 0
                let rhsTime = HistoryMessagePayload.date(from: rhs)?.timeIntervalSince1970 ?? 0
                return lhsTime < rhsTime
            }
        if !newMessages.isEmpty {
            state.messages = newMessages + state.messages
        }
        for message in parsed {
            updateMessageActivity(profileId: profileId, message: message, fallbackDate: .distantPast)
        }
        state.historyHasMore = json["has_more"] as? Bool ?? false
        state.historyLoaded = true
        state.historyError = nil
        saveRuntimeState(state, profileId: profileId)
    }

    private func handleAsrResult(_ json: [String: Any]) {
        let clientMessageId = json["client_message_id"] as? String
        let success = json["success"] as? Bool ?? false
        let text = json["text"] as? String
        let error = json["error"] as? String
        guard let clientMessageId else { return }
        if let payload = ASRResultEventPayload(json: json) {
            messageSubject.send(.asrResult(payload))
        }
        let audioContext = pendingAudioContextsByClientMessageId.removeValue(forKey: clientMessageId)
        let profileId = audioContext?.profileId ?? activeProfileId
        guard let profileId else { return }
        var state = profileId == activeProfileId ? currentRuntimeStateSnapshot() : (profileStates[profileId] ?? ProfileRuntimeState())
        guard let idx = state.messages.firstIndex(where: { $0.clientMessageId == clientMessageId }) else { return }
        if !success {
            logAsrFailure(profileId: profileId, clientMessageId: clientMessageId, error: error)
            if shouldDropAsrFailureMessage(error) {
                state.messages = state.messages.filter { $0.clientMessageId != clientMessageId }
                saveRuntimeState(state, profileId: profileId)
            }
            return
        }
        let old = state.messages[idx]
        var updatedMessages = state.messages
        let transcript = text ?? ""
        let displayContent = audioContext?.recordingPrompt.map {
            RecordingChatContent.format(prompt: $0, transcript: transcript)
        } ?? transcript
        updatedMessages[idx] = ChatMessage(
            id: old.id,
            content: displayContent,
            timestamp: old.timestamp,
            rawTimestamp: old.rawTimestamp,
            senderId: old.senderId,
            trace: old.trace,
            status: .delivered,
            seq: old.seq,
            clientMessageId: old.clientMessageId
        )
        state.messages = updatedMessages
        updateMessageActivity(profileId: profileId, message: updatedMessages[idx], forcePreview: true)
        saveRuntimeState(state, profileId: profileId)
    }

    private func logAsrFailure(profileId: String, clientMessageId: String, error: String?) {
        let normalizedError = error?.trimmingCharacters(in: .whitespacesAndNewlines)
        print(
            "OpenClawRemote asr failed " +
            "profileId=\(profileId.isEmpty ? "-" : profileId) " +
            "clientMessageId=\(clientMessageId.isEmpty ? "-" : clientMessageId) " +
            "error=\((normalizedError?.isEmpty == false) ? normalizedError! : "unknown")"
        )
    }

    private func sanitizeAssistantContent(_ content: String) -> String {
        let pattern = #"^\s*\[\[reply_to(?:_current| current)\]\]\s*"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return content.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let range = NSRange(content.startIndex..., in: content)
        let sanitized = regex.stringByReplacingMatches(in: content, options: [], range: range, withTemplate: "")
        return sanitized.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func displayableBackendContent(_ content: String) -> String? {
        let sanitized = sanitizeAssistantContent(content)
        return shouldHideSystemNoise(sanitized) ? nil : sanitized
    }

    private func shouldHideSystemNoise(_ content: String) -> Bool {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "HEARTBEAT_OK" { return true }
        if trimmed.hasPrefix("System (untrusted):") { return true }

        let heartbeatPrompts = [
            "Read HEARTBEAT.md if it exists",
            "reply HEARTBEAT_OK",
            "HEARTBEAT.md",
            "Do not infer or repeat oldtasks"
        ]
        let containsHeartbeatPrompt = heartbeatPrompts.contains { trimmed.localizedCaseInsensitiveContains($0) }
        if containsHeartbeatPrompt && (
            trimmed.hasPrefix("Read HEARTBEAT.md")
                || trimmed.hasPrefix("Exec failed")
                || trimmed.localizedCaseInsensitiveContains("workspace/HEARTBEAT.md")
                || trimmed.localizedCaseInsensitiveContains("Current time:")
        ) {
            return true
        }
        return false
    }

    private func messageHistoryKey(_ message: ChatMessage) -> String {
        "\(message.senderId)|\(message.rawTimestamp ?? message.timestamp)|\(message.content)"
    }

    private func setAgentListActivity(_ activity: AgentListActivity, profileId: String) {
        var activities = agentListActivities
        activities[profileId] = activity
        agentListActivities = activities
    }

    private func updateMessageActivity(
        profileId: String,
        message: ChatMessage,
        fallbackDate: Date = Date(),
        forcePreview: Bool = false
    ) {
        guard let preview = messagePreview(for: message.content) else { return }
        let messageDate = message.rawTimestamp
            .flatMap { HistoryMessagePayload.date(from: $0) } ?? fallbackDate
        var activity = agentListActivities[profileId] ?? AgentListActivity()
        if forcePreview || activity.latestMessageAt == nil || messageDate >= activity.latestMessageAt! {
            activity.latestMessagePreview = preview
            activity.latestMessageAt = messageDate
            setAgentListActivity(activity, profileId: profileId)
        }
    }

    private func messagePreview(for content: String) -> String? {
        let preview = content
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return preview.isEmpty ? nil : preview
    }

    @discardableResult
    private func addLocalMessageWithStatus(_ content: String, senderId: String, status: MessageStatus, seq: Int?, clientMessageId: String? = nil) -> ChatMessage {
        let msg = ChatMessage(content: content, timestamp: timestamp(), senderId: senderId, status: status, seq: seq, clientMessageId: clientMessageId)
        appendMessage(msg, profileId: activeProfileId)
        return msg
    }

    func addLocalMessage(_ content: String, senderId: String) {
        addMessage(content, senderId: senderId)
    }

    private func addMessage(_ content: String, senderId: String) {
        appendMessage(content, senderId: senderId, profileId: activeProfileId)
    }

    private func appendMessage(_ content: String, senderId: String, profileId: String?) {
        let msg = ChatMessage(content: content, timestamp: timestamp(), senderId: senderId, status: nil, seq: nil)
        appendMessage(msg, profileId: profileId)
    }

    private func appendMessage(_ message: ChatMessage, profileId: String?) {
        guard let profileId else {
            messages = messages + [message]
            return
        }
        if profileId == activeProfileId {
            messages = messages + [message]
            persistActiveRuntimeState()
        } else {
            var state = profileStates[profileId] ?? ProfileRuntimeState()
            state.messages = state.messages + [message]
            profileStates[profileId] = state
            if !message.isUser {
                unreadCounts[profileId, default: 0] += 1
            }
        }
        updateMessageActivity(profileId: profileId, message: message)
        messageSubject.send(.newMessage(profileId: profileId, message))
    }

    private func profileId(forBackendId backendId: String) -> String? {
        if let profileId = profileIdsByBackendId[backendId] {
            return profileId
        }
        if backendId == registeredBackendId {
            return activeProfileId
        }
        return nil
    }

    private func persistActiveRuntimeState() {
        guard let activeProfileId else { return }
        profileStates[activeProfileId] = currentRuntimeStateSnapshot()
    }

    private func currentRuntimeStateSnapshot() -> ProfileRuntimeState {
        ProfileRuntimeState(
            registeredBackendId: registeredBackendId,
            preferredBackendId: preferredBackendId,
            preferredBackendLabel: preferredBackendLabel,
            pairingState: pairingState,
            messages: messages,
            historyLoading: historyLoading,
            historyError: historyError,
            historyHasMore: historyHasMore,
            historyLoaded: historyLoaded,
            loadedHistoryKeys: loadedHistoryKeys,
            oldestHistoryTimestamp: oldestHistoryTimestamp,
            lastAutoHistoryRequestAt: lastAutoHistoryRequestAt
        )
    }

    private func saveRuntimeState(_ state: ProfileRuntimeState, profileId: String) {
        profileStates[profileId] = state
        if profileId == activeProfileId {
            loadRuntimeState(state)
        }
    }

    private func loadRuntimeState(_ state: ProfileRuntimeState) {
        registeredBackendId = state.registeredBackendId
        preferredBackendId = state.preferredBackendId
        preferredBackendLabel = state.preferredBackendLabel
        pairingState = state.pairingState
        messages = state.messages
        historyLoading = state.historyLoading
        historyError = state.historyError
        historyHasMore = state.historyHasMore
        historyLoaded = state.historyLoaded
        loadedHistoryKeys = state.loadedHistoryKeys
        oldestHistoryTimestamp = state.oldestHistoryTimestamp
        lastAutoHistoryRequestAt = state.lastAutoHistoryRequestAt
    }

    private func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: Date())
    }

    private func isoTimestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: Date())
    }

}

extension WebSocketManager: AgentTaskRequestClient {}

enum WsMessageEvent {
    case registered(String)
    case paired(profileId: String, backendId: String, backendLabel: String)
    case unpaired(profileId: String)
    case newMessage(profileId: String, ChatMessage)
    case taskListResponse(TaskListResponsePayload)
    case taskCreateResponse(TaskMutationResponsePayload)
    case taskUpdateResponse(TaskMutationResponsePayload)
    case taskDeleteResponse(TaskMutationResponsePayload)
    case approvalHistoryResponse(ApprovalHistoryResponsePayload)
    case asrResult(ASRResultEventPayload)
    case recordingEvent(RecordingEventPayload)
    case sessionPreempted(replacementTerminalLabel: String?)
    case error(code: String, message: String)
}
