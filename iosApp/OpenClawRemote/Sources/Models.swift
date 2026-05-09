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

enum AgentAvailabilityStatus {
    case unconfigured
    case unpaired
    case pairing
    case available
    case connecting
    case offline

    var label: String {
        switch self {
        case .unconfigured: return "未配置"
        case .unpaired: return "未配"
        case .pairing: return "配对中"
        case .available: return "可用"
        case .connecting: return "连接中"
        case .offline: return "离线"
        }
    }
}

struct ChatMessage: Identifiable {
    let id: UUID
    let content: String
    let timestamp: String
    let rawTimestamp: String?
    let senderId: String
    let status: MessageStatus?
    let seq: Int?
    let clientMessageId: String?

    var isUser: Bool { senderId == "user" }

    init(id: UUID = UUID(), content: String, timestamp: String, rawTimestamp: String? = nil, senderId: String, status: MessageStatus? = nil, seq: Int? = nil, clientMessageId: String? = nil) {
        self.id = id
        self.content = content
        self.timestamp = timestamp
        self.rawTimestamp = rawTimestamp
        self.senderId = senderId
        self.status = status
        self.seq = seq
        self.clientMessageId = clientMessageId
    }
}

enum MessageStatus: String, Codable {
    case sending = "SENDING"
    case delivered = "DELIVERED"
    case failed = "FAILED"
}

struct HistoryMessagePayload {
    let content: String
    let role: String
    let timestamp: String

    var chatMessage: ChatMessage {
        let normalized = role.lowercased()
        let senderId = normalized == "user" || normalized == "human" ? "user" : "assistant"
        return ChatMessage(content: content, timestamp: Self.displayTimestamp(timestamp), rawTimestamp: timestamp, senderId: senderId)
    }

    private static func displayTimestamp(_ raw: String) -> String {
        let iso = ISO8601DateFormatter()
        if let date = iso.date(from: raw) {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            return formatter.string(from: date)
        }
        return raw
    }
}

enum AgentPlatform: String, Codable, CaseIterable, Identifiable {
    case openclaw
    case hermes
    case custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .openclaw: return "OpenClaw"
        case .hermes: return "Hermes"
        case .custom: return "Custom"
        }
    }

    var defaultDisplayName: String {
        switch self {
        case .openclaw: return "OpenClaw Agent"
        case .hermes: return "Hermes BosonRelay"
        case .custom: return "Agent"
        }
    }

    var supportsAudio: Bool {
        true
    }

    var iconName: String {
        switch self {
        case .openclaw: return "pawprint.fill"
        case .hermes: return "sparkles"
        case .custom: return "antenna.radiowaves.left.and.right"
        }
    }
}

struct AgentProfile: Identifiable, Codable, Equatable {
    var id: String
    var appClientId: String
    var platform: AgentPlatform
    var displayName: String
    var gatewayUrl: String
    var backendId: String
    var backendLabel: String?
    var token: String
    var isPaired: Bool
    var asrMode: String
    var asrProfileId: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String = UUID().uuidString,
        appClientId: String,
        platform: AgentPlatform = .openclaw,
        displayName: String = "",
        gatewayUrl: String = "wss://boson-tech.top/ws",
        backendId: String,
        backendLabel: String? = nil,
        token: String = "",
        isPaired: Bool = false,
        asrMode: String = "router",
        asrProfileId: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.appClientId = appClientId
        self.platform = platform
        self.displayName = displayName
        self.gatewayUrl = gatewayUrl
        self.backendId = backendId
        self.backendLabel = backendLabel
        self.token = token
        self.isPaired = isPaired
        self.asrMode = asrMode
        self.asrProfileId = asrProfileId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var resolvedDisplayName: String {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        if let backendLabel, !backendLabel.isEmpty { return backendLabel }
        return platform.defaultDisplayName
    }

    var uniqueBackendKey: String {
        "\(Self.normalizedGatewayKey(gatewayUrl))|\(backendId)"
    }

    static func normalizedGatewayKey(_ gatewayUrl: String) -> String {
        gatewayUrl
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}

struct GatewayConfig {
    var gatewayUrl: String
    var deviceId: String
    var deviceLabel: String
    var token: String
    var pairedBackendId: String?
    var pairedBackendLabel: String?
    var asrMode: String
    var asrProfileId: String

    init(
        gatewayUrl: String = "wss://boson-tech.top/ws",
        deviceId: String = "",
        deviceLabel: String = "",
        token: String = "",
        pairedBackendId: String? = nil,
        pairedBackendLabel: String? = nil,
        asrMode: String = "router",
        asrProfileId: String = ""
    ) {
        self.gatewayUrl = gatewayUrl
        self.deviceId = deviceId
        self.deviceLabel = deviceLabel
        self.token = token
        self.pairedBackendId = pairedBackendId
        self.pairedBackendLabel = pairedBackendLabel
        self.asrMode = asrMode
        self.asrProfileId = asrProfileId
    }
}

struct AsrProviderProfile: Identifiable, Equatable {
    let id: String
    let provider: String
    let providerLabel: String
    let model: String
    let modelLabel: String
}

enum QRParseResult {
    case success(gatewayUrl: String, backendId: String, token: String, platform: AgentPlatform, label: String?)
    case error(message: String)
}

func parseQRPack(_ scannedText: String) -> QRParseResult {
    if scannedText.hasPrefix("openclaw://connect") {
        guard let components = URLComponents(string: scannedText) else {
            return .error(message: "二维码 URL 解析失败")
        }
        var query: [String: String] = [:]
        for item in components.queryItems ?? [] {
            query[item.name] = item.value ?? ""
        }
        let gateway = query["gateway"] ?? ""
        let backendId = query["backendId"] ?? query["agentId"] ?? ""
        let token = query["token"] ?? ""
        let platform = AgentPlatform(rawValue: (query["platform"] ?? "").lowercased()) ?? .openclaw
        let label = query["label"]
        if gateway.isEmpty || backendId.isEmpty {
            return .error(message: "缺少 gateway 或 backendId 参数")
        }
        return .success(gatewayUrl: gateway, backendId: backendId, token: token, platform: platform, label: label)
    }

    let trimmed = scannedText.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.hasPrefix("{") {
        if let data = trimmed.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let gateway = json["gateway"] as? String,
           let agentId = (json["agentId"] as? String) ?? (json["backendId"] as? String),
           !gateway.isEmpty && !agentId.isEmpty {
            let token = json["token"] as? String ?? ""
            let platformValue = (json["platform"] as? String ?? "").lowercased()
            let platform = AgentPlatform(rawValue: platformValue) ?? .openclaw
            let label = (json["label"] as? String) ?? (json["backendLabel"] as? String)
            return .success(gatewayUrl: gateway, backendId: agentId, token: token, platform: platform, label: label)
        }
        return .error(message: "JSON 解析失败")
    }

    return .error(message: "不支持的二维码格式")
}
