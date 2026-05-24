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

    static func chatMessage(
        content: String,
        role: String,
        item: [String: Any],
        fallbackTimestamp: String = ""
    ) -> ChatMessage {
        let rawTimestamp = timestamp(from: item) ?? fallbackTimestamp.trimmingCharacters(in: .whitespacesAndNewlines)
        return HistoryMessagePayload(content: content, role: role, timestamp: rawTimestamp).chatMessage
    }

    static func timestamp(from item: [String: Any]) -> String? {
        for key in ["timestamp", "created_at", "createdAt", "sent_at", "sentAt", "message_time", "messageTime", "time"] {
            if let value = normalizedTimestampValue(item[key]) {
                return value
            }
        }
        return nil
    }

    private static func normalizedTimestampValue(_ value: Any?) -> String? {
        if let value = value as? String {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return nil }
            if let numeric = Double(trimmed), let timestamp = isoTimestamp(fromEpoch: numeric) {
                return timestamp
            }
            return trimmed
        }

        if let value = value as? NSNumber {
            return isoTimestamp(fromEpoch: value.doubleValue)
        }

        if let value = value as? Date {
            return isoFormatter.string(from: value)
        }

        if let value = value as? [String: Any] {
            for key in ["$date", "date", "value", "iso"] {
                if let timestamp = normalizedTimestampValue(value[key]) {
                    return timestamp
                }
            }
        }

        return nil
    }

    private static func isoTimestamp(fromEpoch value: Double) -> String? {
        guard value > 100_000_000 else { return nil }
        let seconds = value > 1_000_000_000_000 ? value / 1000 : value
        return isoFormatter.string(from: Date(timeIntervalSince1970: seconds))
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let isoFormatterWithoutFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    var chatMessage: ChatMessage {
        let normalized = role.lowercased()
        let senderId = normalized == "user" || normalized == "human" ? "user" : "assistant"
        return ChatMessage(content: content, timestamp: Self.displayTimestamp(timestamp), rawTimestamp: timestamp, senderId: senderId)
    }

    static func date(from raw: String) -> Date? {
        isoFormatter.date(from: raw) ?? isoFormatterWithoutFractionalSeconds.date(from: raw)
    }

    private static func displayTimestamp(_ raw: String) -> String {
        if let date = date(from: raw) {
            let formatter = DateFormatter()
            formatter.dateFormat = Calendar.current.isDateInToday(date) ? "HH:mm" : "MM月dd日 HH:mm"
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
    var isPinned: Bool
    var sortIndex: Int

    init(
        id: String = UUID().uuidString,
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
        updatedAt: Date = Date(),
        isPinned: Bool = false,
        sortIndex: Int = 0
    ) {
        self.id = id
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
        self.isPinned = isPinned
        self.sortIndex = sortIndex
    }

    enum CodingKeys: String, CodingKey {
        case id
        case platform
        case displayName
        case gatewayUrl
        case backendId
        case backendLabel
        case token
        case isPaired
        case asrMode
        case asrProfileId
        case createdAt
        case updatedAt
        case isPinned
        case sortIndex
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        platform = try container.decodeIfPresent(AgentPlatform.self, forKey: .platform) ?? .openclaw
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName) ?? ""
        gatewayUrl = try container.decodeIfPresent(String.self, forKey: .gatewayUrl) ?? "wss://boson-tech.top/ws"
        backendId = try container.decodeIfPresent(String.self, forKey: .backendId) ?? ""
        backendLabel = try container.decodeIfPresent(String.self, forKey: .backendLabel)
        token = try container.decodeIfPresent(String.self, forKey: .token) ?? ""
        isPaired = try container.decodeIfPresent(Bool.self, forKey: .isPaired) ?? false
        asrMode = try container.decodeIfPresent(String.self, forKey: .asrMode) ?? "router"
        asrProfileId = try container.decodeIfPresent(String.self, forKey: .asrProfileId) ?? ""
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        sortIndex = try container.decodeIfPresent(Int.self, forKey: .sortIndex) ?? 0
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

extension Array where Element == AgentProfile {
    func sortedForAgentList() -> [AgentProfile] {
        sorted { left, right in
            if left.isPinned != right.isPinned {
                return left.isPinned && !right.isPinned
            }
            if left.isPinned, right.isPinned, left.sortIndex != right.sortIndex {
                return left.sortIndex < right.sortIndex
            }
            if left.updatedAt != right.updatedAt {
                return left.updatedAt > right.updatedAt
            }
            return left.resolvedDisplayName.localizedCaseInsensitiveCompare(right.resolvedDisplayName) == .orderedAscending
        }
    }
}

struct GatewayConfig {
    var gatewayUrl: String
    var accountId: String
    var accessToken: String
    var refreshToken: String
    var accessExpiresAt: String
    var refreshExpiresAt: String
    var deviceLabel: String
    var token: String
    var pairedBackendId: String?
    var pairedBackendLabel: String?
    var asrMode: String
    var asrProfileId: String

    init(
        gatewayUrl: String = "wss://boson-tech.top/ws",
        accountId: String = "",
        accessToken: String = "",
        refreshToken: String = "",
        accessExpiresAt: String = "",
        refreshExpiresAt: String = "",
        deviceLabel: String = "",
        token: String = "",
        pairedBackendId: String? = nil,
        pairedBackendLabel: String? = nil,
        asrMode: String = "router",
        asrProfileId: String = ""
    ) {
        self.gatewayUrl = gatewayUrl
        self.accountId = accountId
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.accessExpiresAt = accessExpiresAt
        self.refreshExpiresAt = refreshExpiresAt
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
