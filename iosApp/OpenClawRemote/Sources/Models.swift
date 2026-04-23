import Foundation

enum ConnectionState {
    case disconnected
    case connecting
    case connected
    case registered
    case paired
}

enum PairingState {
    case unpaired
    case pending
    case paired
}

struct ChatMessage: Identifiable {
    let id = UUID()
    let content: String
    let timestamp: String
    let senderId: String

    var isUser: Bool { senderId == "user" }
}

struct GatewayConfig {
    var gatewayUrl: String
    var deviceId: String
    var deviceLabel: String
    var token: String
    var pairedBackendId: String?
    var pairedBackendLabel: String?

    init(
        gatewayUrl: String = "wss://boson-tech.top/ws",
        deviceId: String = "",
        deviceLabel: String = "",
        token: String = "",
        pairedBackendId: String? = nil,
        pairedBackendLabel: String? = nil
    ) {
        self.gatewayUrl = gatewayUrl
        self.deviceId = deviceId
        self.deviceLabel = deviceLabel
        self.token = token
        self.pairedBackendId = pairedBackendId
        self.pairedBackendLabel = pairedBackendLabel
    }
}

enum QRParseResult {
    case success(gatewayUrl: String, backendId: String, token: String)
    case error(message: String)
}

func parseQRPack(_ scannedText: String) -> QRParseResult {
    if scannedText.hasPrefix("openclaw://connect") {
        let body = scannedText.replacingOccurrences(of: "openclaw://connect?", with: "")
        let parts = body.split(separator: "&").map { String($0) }
        var gateway = ""
        var agentId = ""
        var token = ""
        for part in parts {
            let keyValue = part.split(separator: "=")
            if keyValue.count == 2 {
                let key = String(keyValue[0])
                let value = String(keyValue[1]).removingPercentEncoding ?? String(keyValue[1])
                switch key {
                case "gateway": gateway = value
                case "agentId": agentId = value
                case "token": token = value
                default: break
                }
            }
        }
        if gateway.isEmpty || agentId.isEmpty {
            return .error(message: "缺少 gateway 或 agentId 参数")
        }
        return .success(gatewayUrl: gateway, backendId: agentId, token: token)
    }

    let trimmed = scannedText.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.hasPrefix("{") {
        if let data = trimmed.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let gateway = json["gateway"] as? String,
           let agentId = (json["agentId"] as? String) ?? (json["backendId"] as? String),
           !gateway.isEmpty && !agentId.isEmpty {
            let token = json["token"] as? String ?? ""
            return .success(gatewayUrl: gateway, backendId: agentId, token: token)
        }
        return .error(message: "JSON 解析失败")
    }

    return .error(message: "不支持的二维码格式")
}