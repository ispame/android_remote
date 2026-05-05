import Foundation
import Combine

final class WebSocketManager: ObservableObject {
    private var webSocketTask: URLSessionWebSocketTask?
    private let session = URLSession(configuration: .default)
    private let scope = DispatchQueue.global(qos: .userInitiated)

    @Published var connectionState: ConnectionState = .disconnected
    @Published var pairingState: PairingState = .unpaired
    @Published private(set) var messages: [ChatMessage] = []
    @Published private(set) var historyLoading = false
    @Published private(set) var historyError: String?
    @Published private(set) var historyHasMore = false
    @Published private(set) var historyLoaded = false

    private let messageSubject = PassthroughSubject<WsMessageEvent, Never>()
    var messageChannel: AnyPublisher<WsMessageEvent, Never> {
        messageSubject.eraseToAnyPublisher()
    }

    private var registeredBackendId: String?
    private let deviceId: String
    private var deviceLabel: String
    private var token: String
    private var preferredBackendId: String?
    private var preferredBackendLabel: String?
    private var currentUrlString: String?
    private var reconnectWorkItem: DispatchWorkItem?
    private var reconnectAttempts = 0
    private var intentionalDisconnect = false
    private var socketGeneration = 0
    private var isRestoringPairing = false
    private let reconnectBaseDelay: TimeInterval = 2
    private let reconnectMaxDelay: TimeInterval = 30

    /// Pending ack callbacks keyed by seq assigned by the Router.
    private var pendingAcks: [Int: (MessageStatus) -> Void] = [:]
    private var seqCounter = 0
    private var receivedMessageSeqs = Set<Int>()
    private var loadedHistoryKeys = Set<String>()
    private var oldestHistoryTimestamp: String?

    init(deviceId: String, deviceLabel: String, token: String) {
        self.deviceId = deviceId
        self.deviceLabel = deviceLabel
        self.token = token
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
    }

    func rememberBackendForPairing(_ backendId: String) {
        preferredBackendId = backendId
        preferredBackendLabel = backendId
        pairingState = .pending
        if connectionState == .registered {
            requestPair(backendId: backendId)
        }
    }

    func applyConfiguration(
        gatewayUrl: String,
        deviceLabel: String,
        token: String,
        pairedBackendId: String?,
        pairedBackendLabel: String?
    ) {
        updateCredentials(deviceLabel: deviceLabel, token: token)
        restorePairing(backendId: pairedBackendId, backendLabel: pairedBackendLabel)
        reconnect(to: gatewayUrl)
    }

    func disconnect() {
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
        guard connectionState == .registered else { return }
        preferredBackendId = backendId
        preferredBackendLabel = backendId
        pairingState = .pending
        let frame: [String: Any] = [
            "type": "pair_request",
            "target_backend_id": backendId
        ]
        sendJson(frame)
    }

    func cancelPair() {
        pairingState = .unpaired
    }

    func sendText(_ text: String) {
        guard pairingState == .paired, let backendId = registeredBackendId else { return }
        let frame: [String: Any] = [
            "type": "message",
            "to": backendId,
            "content": text
        ]
        // Emit a "sending" placeholder so UI can show pending state
        _ = addLocalMessageWithStatus(text, senderId: "user", status: .sending, seq: nil)
        sendJson(frame)
    }

    func requestRecentHistory(rounds: Int = 15) {
        if historyLoading { return }
        if historyLoaded && !historyHasMore { return }
        guard pairingState == .paired else {
            historyLoading = false
            historyError = "请先配对 OpenClaw"
            historyHasMore = false
            return
        }

        historyLoading = true
        historyError = nil
        var frame: [String: Any] = [
            "type": "history_request",
            "app_id": deviceId,
            "session_key": "current",
            "limit": max(1, rounds) * 2
        ]
        if let oldestHistoryTimestamp {
            frame["before_timestamp"] = oldestHistoryTimestamp
        }
        sendJson(frame)
    }

    func sendAudio(_ data: Data) {
        guard pairingState == .paired, let backendId = registeredBackendId else { return }
        let base64 = data.base64EncodedString()
        let frame: [String: Any] = [
            "type": "message",
            "to": backendId,
            "content": base64,
            "content_type": "audio"
        ]
        sendJson(frame)
    }

    func unpair() {
        guard let backendId = registeredBackendId else { return }
        let frame: [String: Any] = [
            "type": "unpair",
            "target_id": backendId
        ]
        sendJson(frame)
        registeredBackendId = nil
        preferredBackendId = nil
        preferredBackendLabel = nil
        pairingState = .unpaired
        messageSubject.send(WsMessageEvent.unpaired)
    }

    private func normalizeGatewayUrl(_ urlString: String) -> String? {
        var urlStr = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if urlStr.isEmpty {
            return nil
        }
        if !urlStr.hasPrefix("ws://") && !urlStr.hasPrefix("wss://") {
            urlStr = "wss://" + urlStr
        }
        if !urlStr.hasSuffix("/ws") {
            if urlStr.hasSuffix("/") {
                urlStr = urlStr + "ws"
            } else {
                urlStr = urlStr + "/ws"
            }
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

    /// Send an ack frame in response to a received message.
    private func sendAck(_ seq: Int) {
        let frame: [String: Any] = [
            "type": "ack",
            "seq": seq
        ]
        sendJson(frame)
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
                    self.messageSubject.send(WsMessageEvent.registered(self.deviceId))
                    if let backendId = self.preferredBackendId ?? self.registeredBackendId {
                        self.isRestoringPairing = true
                        self.requestPair(backendId: backendId)
                    }
                }

            case "pair_response":
                let approve = json["approve"] as? Bool ?? false
                let backendId = json["backend_id"] as? String ?? ""
                let backendLabel = json["backend_label"] as? String ?? backendId
                if approve {
                    self.registeredBackendId = backendId
                    self.preferredBackendId = backendId
                    self.preferredBackendLabel = backendLabel
                    self.pairingState = .paired
                    self.messageSubject.send(WsMessageEvent.paired(backendId, backendLabel))
                    self.isRestoringPairing = false
                } else {
                    self.pairingState = .unpaired
                    self.addMessage("配对请求被拒绝", senderId: "assistant")
                }

            case "message":
                let content = json["content"] as? String ?? ""
                let seq = json["seq"] as? Int
                // Immediately ack so the sender (plugin) gets delivery confirmation
                if let seq = seq {
                    self.sendAck(seq)
                    if self.receivedMessageSeqs.contains(seq) {
                        return
                    }
                    self.rememberReceivedSeq(seq)
                }
                self.addMessage(content, senderId: "assistant")

            case "history_response":
                self.handleHistoryResponse(json)

            case "ack":
                // Router forwarded ack from plugin — we don't track per-message state at app level
                break

            case "delivery_failed":
                let seq = json["seq"] as? Int
                let reason = json["reason"] as? String ?? "unknown"
                if let seq = seq {
                    self.pendingAcks.removeValue(forKey: seq)
                }
                self.addMessage("消息发送失败: \(reason)", senderId: "assistant")

            case "ping":
                self.sendJson(["type": "pong"])

            case "pong":
                break

            case "unpaired":
                let targetId = json["target_id"] as? String ?? ""
                if targetId == self.registeredBackendId {
                    self.registeredBackendId = nil
                    self.preferredBackendId = nil
                    self.preferredBackendLabel = nil
                    self.pairingState = .unpaired
                    self.messageSubject.send(WsMessageEvent.unpaired)
                    self.addMessage("已解除配对", senderId: "assistant")
                }

            case "error":
                let code = json["code"] as? String ?? "unknown"
                let msg = json["message"] as? String ?? "未知错误"
                self.addMessage("错误 (\(code)): \(msg)", senderId: "assistant")

            default:
                break
            }
        }
    }

    private func rememberReceivedSeq(_ seq: Int) {
        receivedMessageSeqs.insert(seq)
        if receivedMessageSeqs.count > 500 {
            receivedMessageSeqs.remove(receivedMessageSeqs.min() ?? seq)
        }
    }

    private func handleHistoryResponse(_ json: [String: Any]) {
        historyLoading = false
        let error = json["error"] as? String
        if let error = error, !error.isEmpty {
            historyError = error
            historyHasMore = false
            return
        }

        let items = json["messages"] as? [[String: Any]] ?? []
        let parsed = items.compactMap { item -> ChatMessage? in
            guard let content = item["content"] as? String else { return nil }
            let role = item["role"] as? String ?? "assistant"
            let timestamp = item["timestamp"] as? String ?? self.timestamp()
            return HistoryMessagePayload(content: content, role: role, timestamp: timestamp).chatMessage
        }

        if parsed.isEmpty {
            historyError = historyLoaded ? "已显示全部历史对话" : "还没有可读取的历史"
            historyHasMore = false
            historyLoaded = true
            return
        }

        let existingKeys = Set(messages.map(messageHistoryKey))
        let newMessages = parsed.filter { message in
            let key = messageHistoryKey(message)
            return !existingKeys.contains(key) && !loadedHistoryKeys.contains(key)
        }
        loadedHistoryKeys.formUnion(parsed.map(messageHistoryKey))
        oldestHistoryTimestamp = (messages + parsed)
            .compactMap { $0.rawTimestamp }
            .min { lhs, rhs in
                let lhsTime = ISO8601DateFormatter().date(from: lhs)?.timeIntervalSince1970 ?? 0
                let rhsTime = ISO8601DateFormatter().date(from: rhs)?.timeIntervalSince1970 ?? 0
                return lhsTime < rhsTime
            }
        if !newMessages.isEmpty {
            messages.insert(contentsOf: newMessages, at: 0)
        }
        historyHasMore = json["has_more"] as? Bool ?? false
        historyLoaded = true
        historyError = nil
    }

    private func messageHistoryKey(_ message: ChatMessage) -> String {
        "\(message.senderId)|\(message.rawTimestamp ?? message.timestamp)|\(message.content)"
    }

    @discardableResult
    private func addLocalMessageWithStatus(_ content: String, senderId: String, status: MessageStatus, seq: Int?) -> ChatMessage {
        let ts = timestamp()
        let msg = ChatMessage(content: content, timestamp: ts, senderId: senderId, status: status, seq: seq)
        messages.append(msg)
        return msg
    }

    func addLocalMessage(_ content: String, senderId: String) {
        let ts = timestamp()
        let msg = ChatMessage(content: content, timestamp: ts, senderId: senderId, status: nil, seq: nil)
        messages.append(msg)
    }

    private func addMessage(_ content: String, senderId: String) {
        let ts = timestamp()
        let msg = ChatMessage(content: content, timestamp: ts, senderId: senderId, status: nil, seq: nil)
        messages.append(msg)
    }

    private func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: Date())
    }
}

enum WsMessageEvent {
    case registered(String)
    case paired(String, String)
    case unpaired
    case newMessage(ChatMessage)
    case error(code: String, message: String)
}
