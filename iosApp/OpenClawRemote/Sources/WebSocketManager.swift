import Foundation
import Combine

final class WebSocketManager: ObservableObject {
    private var webSocketTask: URLSessionWebSocketTask?
    private let session = URLSession(configuration: .default)
    private let scope = DispatchQueue.global(qos: .userInitiated)

    @Published var connectionState: ConnectionState = .disconnected
    @Published var pairingState: PairingState = .unpaired
    @Published private(set) var messages: [ChatMessage] = []

    private let messageSubject = PassthroughSubject<WsMessageEvent, Never>()
    var messageChannel: AnyPublisher<WsMessageEvent, Never> {
        messageSubject.eraseToAnyPublisher()
    }

    private var registeredBackendId: String?
    private let deviceId: String
    private let deviceLabel: String
    private let token: String

    init(deviceId: String, deviceLabel: String, token: String) {
        self.deviceId = deviceId
        self.deviceLabel = deviceLabel
        self.token = token
    }

    func connect(to urlString: String) {
        guard connectionState == .disconnected else { return }
        connectionState = .connecting

        // Normalize URL: ensure ws/wss scheme, append /ws if needed
        var urlStr = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if urlStr.isEmpty {
            connectionState = .disconnected
            return
        }
        // Ensure scheme
        if !urlStr.hasPrefix("ws://") && !urlStr.hasPrefix("wss://") {
            urlStr = "wss://" + urlStr
        }
        // Append /ws path if not present
        if !urlStr.hasSuffix("/ws") {
            if urlStr.hasSuffix("/") {
                urlStr = urlStr + "ws"
            } else {
                urlStr = urlStr + "/ws"
            }
        }

        guard let url = URL(string: urlStr) else {
            connectionState = .disconnected
            return
        }

        // Validate scheme (URLSession throws NSException for invalid schemes)
        guard url.scheme == "ws" || url.scheme == "wss" else {
            connectionState = .disconnected
            return
        }

        // Note: webSocketTask throws NSException (not Swift Error) for invalid schemes.
        // Scheme is validated above, so no try-catch needed here.
        webSocketTask = session.webSocketTask(with: url)
        webSocketTask?.resume()
        connectionState = .connected
        sendRegister()
        receiveMessage()
    }

    func reconnect(to urlString: String) {
        disconnect()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.connect(to: urlString)
        }
    }

    func disconnect() {
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        connectionState = .disconnected
        pairingState = .unpaired
    }

    func requestPair(backendId: String) {
        guard connectionState == .registered else { return }
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
        pairingState = .unpaired
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

    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self?.handleMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self?.handleMessage(text)
                    }
                @unknown default:
                    break
                }
                self?.receiveMessage()
            case .failure:
                DispatchQueue.main.async {
                    self?.connectionState = .disconnected
                    self?.pairingState = .unpaired
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
                    self.messageSubject.send(WsMessageEvent.registered(self.deviceId))
                }

            case "pair_response":
                let approve = json["approve"] as? Bool ?? false
                let backendId = json["backend_id"] as? String ?? ""
                let backendLabel = json["backend_label"] as? String ?? backendId
                if approve {
                    self.registeredBackendId = backendId
                    self.pairingState = .paired
                    self.messageSubject.send(WsMessageEvent.paired(backendId, backendLabel))
                    self.addMessage("已成功配对 OpenClaw: \(backendLabel)", senderId: "assistant")
                } else {
                    self.pairingState = .unpaired
                    self.addMessage("配对请求被拒绝", senderId: "assistant")
                }

            case "message":
                let content = json["content"] as? String ?? ""
                self.addMessage(content, senderId: "assistant")

            case "pong":
                break

            case "unpaired":
                let targetId = json["target_id"] as? String ?? ""
                if targetId == self.registeredBackendId {
                    self.registeredBackendId = nil
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

    func addLocalMessage(_ content: String, senderId: String) {
        let ts = timestamp()
        let msg = ChatMessage(content: content, timestamp: ts, senderId: senderId)
        messages.append(msg)
    }

    private func addMessage(_ content: String, senderId: String) {
        let ts = timestamp()
        let msg = ChatMessage(content: content, timestamp: ts, senderId: senderId)
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