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

func shouldDropAsrFailureMessage(_ error: String?) -> Bool {
    true
}

final class WebSocketManager: ObservableObject {
    private var webSocketTask: URLSessionWebSocketTask?
    private let session = URLSession(configuration: .default)

    @Published var connectionState: ConnectionState = .disconnected
    @Published var pairingState: PairingState = .unpaired
    @Published private(set) var messages: [ChatMessage] = []
    @Published private(set) var historyLoading = false
    @Published private(set) var historyError: String?
    @Published private(set) var historyHasMore = false
    @Published private(set) var historyLoaded = false
    @Published private(set) var unreadCounts: [String: Int] = [:]

    private let messageSubject = PassthroughSubject<WsMessageEvent, Never>()
    var messageChannel: AnyPublisher<WsMessageEvent, Never> {
        messageSubject.eraseToAnyPublisher()
    }

    private var activeProfileId: String?
    private var activePlatform: AgentPlatform = .openclaw
    private var profileStates: [String: ProfileRuntimeState] = [:]
    private var profileIdsByBackendId: [String: String] = [:]
    private var pendingHistoryProfileId: String?
    private var pendingAudioProfileIdsByClientMessageId: [String: String] = [:]

    private var registeredBackendId: String?
    private var deviceId: String
    private var deviceLabel: String
    private var token: String
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
    private var receivedMessageSeqs = Set<Int>()
    private var loadedHistoryKeys = Set<String>()
    private var oldestHistoryTimestamp: String?
    private var lastAutoHistoryRequestAt: Date?

    init(deviceId: String, deviceLabel: String, token: String) {
        self.deviceId = deviceId
        self.deviceLabel = deviceLabel
        self.token = token
    }

    func syncProfiles(_ profiles: [AgentProfile]) {
        let knownIds = Set(profiles.map(\.id))
        profileStates = profileStates.filter { knownIds.contains($0.key) }
        unreadCounts = unreadCounts.filter { knownIds.contains($0.key) }
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
    }

    func applyProfile(_ profile: AgentProfile, deviceLabel: String) {
        persistActiveRuntimeState()

        activeProfileId = profile.id
        activePlatform = profile.platform
        if !profile.backendId.isEmpty {
            profileIdsByBackendId[profile.backendId] = profile.id
        }
        updateCredentials(deviceLabel: deviceLabel, token: profile.token)
        updateAsrConfiguration(mode: profile.asrMode, profileId: profile.asrProfileId)
        unreadCounts[profile.id] = 0

        var state = profileStates[profile.id] ?? ProfileRuntimeState()
        state.preferredBackendId = profile.isPaired && !profile.backendId.isEmpty ? profile.backendId : nil
        state.preferredBackendLabel = profile.isPaired ? (profile.backendLabel ?? profile.resolvedDisplayName) : nil
        state.registeredBackendId = profile.isPaired && !profile.backendId.isEmpty ? profile.backendId : nil
        state.pairingState = profile.isPaired && !profile.backendId.isEmpty ? .paired : .unpaired
        profileStates[profile.id] = state
        loadRuntimeState(state)
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

    func clearProfileState(profileId: String) {
        profileStates[profileId] = ProfileRuntimeState()
        unreadCounts[profileId] = 0
        if profileId == activeProfileId {
            loadRuntimeState(ProfileRuntimeState())
        }
    }

    func removeProfileState(profileId: String) {
        profileStates.removeValue(forKey: profileId)
        unreadCounts.removeValue(forKey: profileId)
        profileIdsByBackendId = profileIdsByBackendId.filter { $0.value != profileId }
        pendingAudioProfileIdsByClientMessageId = pendingAudioProfileIdsByClientMessageId.filter { $0.value != profileId }
        if pendingHistoryProfileId == profileId {
            pendingHistoryProfileId = nil
        }
    }

    func connect(to urlString: String) {
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

    func updateCredentials(deviceLabel: String, token: String) {
        self.deviceLabel = deviceLabel
        self.token = token
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
        token: String,
        pairedBackendId: String?,
        pairedBackendLabel: String?,
        asrMode: String = "router",
        asrProfileId: String = ""
    ) {
        updateCredentials(deviceLabel: deviceLabel, token: token)
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
        guard connectionState == .registered, !backendId.isEmpty else { return }
        preferredBackendId = backendId
        preferredBackendLabel = backendId
        pairingState = .pending
        persistActiveRuntimeState()
        sendJson([
            "type": "pair_request",
            "target_backend_id": backendId
        ])
    }

    func cancelPair() {
        pairingState = .unpaired
        persistActiveRuntimeState()
    }

    func sendText(_ text: String) {
        guard pairingState == .paired, let backendId = registeredBackendId else { return }
        addLocalMessageWithStatus(text, senderId: "user", status: .sending, seq: nil)
        sendJson([
            "type": "message",
            "to": backendId,
            "content": text
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
            "app_id": deviceId,
            "target_backend_id": backendId,
            "session_key": "current",
            "limit": max(1, rounds) * 2
        ]
        if !force, let oldestHistoryTimestamp {
            frame["before_timestamp"] = oldestHistoryTimestamp
        }
        persistActiveRuntimeState()
        sendJson(frame)
    }

    func sendAudio(_ data: Data) {
        guard pairingState == .paired, let backendId = registeredBackendId else { return }
        let base64 = data.base64EncodedString()
        let clientMessageId = UUID().uuidString
        let frame: [String: Any] = [
            "type": "message",
            "to": backendId,
            "client_message_id": clientMessageId,
            "content": base64,
            "content_type": "audio",
            "audio": [
                "format": "wav",
                "codec": "pcm_s16le",
                "sample_rate": 16000,
                "channels": 1
            ],
            "asr": [
                "mode": asrMode,
                "profile_id": asrProfileId
            ]
        ]
        addLocalMessageWithStatus("正在识别...", senderId: "user", status: .sending, seq: nil, clientMessageId: clientMessageId)
        if let activeProfileId {
            pendingAudioProfileIdsByClientMessageId[clientMessageId] = activeProfileId
        }
        sendJson(frame)
    }

    @discardableResult
    func sendAudio(_ data: Data, profileId: String) -> Bool {
        let state = profileId == activeProfileId
            ? currentRuntimeStateSnapshot()
            : (profileStates[profileId] ?? ProfileRuntimeState())
        guard state.pairingState == .paired, let backendId = state.registeredBackendId else { return false }

        let base64 = data.base64EncodedString()
        let clientMessageId = UUID().uuidString
        let frame: [String: Any] = [
            "type": "message",
            "to": backendId,
            "client_message_id": clientMessageId,
            "content": base64,
            "content_type": "audio",
            "audio": [
                "format": "wav",
                "codec": "pcm_s16le",
                "sample_rate": 16000,
                "channels": 1
            ],
            "asr": [
                "mode": asrMode,
                "profile_id": asrProfileId
            ]
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
        pendingAudioProfileIdsByClientMessageId[clientMessageId] = profileId
        sendJson(frame)
        return true
    }

    func unpair() {
        guard let backendId = registeredBackendId, let profileId = activeProfileId else { return }
        unpair(profileId: profileId, backendId: backendId)
    }

    func unpair(profileId: String, backendId: String) {
        guard !backendId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        sendJson([
            "type": "unpair",
            "target_id": backendId
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
        }
        profileIdsByBackendId.removeValue(forKey: backendId)
        messageSubject.send(.unpaired(profileId: profileId))
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
        var frame: [String: Any] = [
            "type": "register",
            "client_type": "app",
            "client_id": deviceId,
            "label": deviceLabel
        ]
        if !token.isEmpty {
            frame["token"] = token
        }
        sendJson(frame)
    }

    private func sendJson(_ dict: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let text = String(data: data, encoding: .utf8) else { return }
        webSocketTask?.send(.string(text)) { _ in }
    }

    private func sendAck(_ seq: Int) {
        sendJson([
            "type": "ack",
            "seq": seq
        ])
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
            case "registered":
                let success = json["success"] as? Bool ?? false
                if success {
                    self.connectionState = .registered
                    self.reconnectAttempts = 0
                    self.cancelReconnect()
                    self.messageSubject.send(.registered(self.deviceId))
                    if let backendId = self.preferredBackendId ?? self.registeredBackendId {
                        self.requestPair(backendId: backendId)
                    }
                }

            case "pair_response":
                self.handlePairResponse(json)

            case "message":
                self.handleInboundMessage(json)

            case "asr_result":
                self.handleAsrResult(json)

            case "history_response":
                let backendId = (json["backend_id"] as? String) ?? (json["target_backend_id"] as? String)
                let responseProfileId = backendId.flatMap { self.profileId(forBackendId: $0) }
                    ?? self.pendingHistoryProfileId
                    ?? self.activeProfileId
                self.handleHistoryResponse(json, profileId: responseProfileId)

            case "ack":
                break

            case "delivery_failed":
                let seq = json["seq"] as? Int
                let reason = json["reason"] as? String ?? "unknown"
                if let seq {
                    self.pendingAcks.removeValue(forKey: seq)
                }
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
                self.addMessage("错误 (\(code)): \(msg)", senderId: "assistant")

            default:
                break
            }
        }
    }

    private func handlePairResponse(_ json: [String: Any]) {
        let approve = json["approve"] as? Bool ?? false
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
            }
            profileIdsByBackendId[backendId] = profileId
            messageSubject.send(.paired(profileId: profileId, backendId: backendId, backendLabel: backendLabel))
        } else {
            if profileId == activeProfileId {
                pairingState = .unpaired
                persistActiveRuntimeState()
            }
            appendMessage("配对请求被拒绝", senderId: "assistant", profileId: profileId)
        }
    }

    private func handleInboundMessage(_ json: [String: Any]) {
        guard let content = displayableBackendContent(json["content"] as? String ?? "") else { return }
        let seq = json["seq"] as? Int
        if let seq {
            sendAck(seq)
            if receivedMessageSeqs.contains(seq) { return }
            rememberReceivedSeq(seq)
        }
        let backendId = json["from"] as? String ?? registeredBackendId ?? ""
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
        let targetId = json["target_id"] as? String ?? ""
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

    private func rememberReceivedSeq(_ seq: Int) {
        receivedMessageSeqs.insert(seq)
        if receivedMessageSeqs.count > 500 {
            receivedMessageSeqs.remove(receivedMessageSeqs.min() ?? seq)
        }
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
        let profileId = pendingAudioProfileIdsByClientMessageId.removeValue(forKey: clientMessageId) ?? activeProfileId
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
        updatedMessages[idx] = ChatMessage(
            id: old.id,
            content: text ?? "",
            timestamp: old.timestamp,
            rawTimestamp: old.rawTimestamp,
            senderId: old.senderId,
            status: .delivered,
            seq: old.seq,
            clientMessageId: old.clientMessageId
        )
        state.messages = updatedMessages
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
}

enum WsMessageEvent {
    case registered(String)
    case paired(profileId: String, backendId: String, backendLabel: String)
    case unpaired(profileId: String)
    case newMessage(profileId: String, ChatMessage)
    case error(code: String, message: String)
}
