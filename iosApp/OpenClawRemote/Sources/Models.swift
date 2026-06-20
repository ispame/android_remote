import Foundation

enum ConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case registered
    case paired
}

enum PairingState: Equatable {
    case unpaired
    case pending
    case paired
}

enum AgentAvailabilityStatus: Equatable {
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
    let trace: [MessageTraceItem]
    let status: MessageStatus?
    let seq: Int?
    let clientMessageId: String?

    var isUser: Bool { senderId == "user" }

    init(
        id: UUID = UUID(),
        content: String,
        timestamp: String,
        rawTimestamp: String? = nil,
        senderId: String,
        trace: [MessageTraceItem] = [],
        status: MessageStatus? = nil,
        seq: Int? = nil,
        clientMessageId: String? = nil
    ) {
        self.id = id
        self.content = content
        self.timestamp = timestamp
        self.rawTimestamp = rawTimestamp
        self.senderId = senderId
        self.trace = trace
        self.status = status
        self.seq = seq
        self.clientMessageId = clientMessageId
    }
}

enum MessageTraceKind: String {
    case reasoning
    case toolCall = "tool_call"
    case toolResult = "tool_result"
    case system
    case other

    init(rawHistoryValue: String) {
        self = MessageTraceKind(rawValue: rawHistoryValue) ?? .other
    }

    var label: String {
        switch self {
        case .reasoning: return "推理"
        case .toolCall: return "工具调用"
        case .toolResult: return "工具结果"
        case .system: return "系统"
        case .other: return "过程"
        }
    }

    var systemImage: String {
        switch self {
        case .reasoning: return "brain.head.profile"
        case .toolCall: return "hammer"
        case .toolResult: return "terminal"
        case .system: return "gearshape"
        case .other: return "ellipsis.curlybraces"
        }
    }
}

struct MessageTraceItem: Identifiable {
    let id: String
    let kind: MessageTraceKind
    let title: String
    let content: String
    let timestamp: String?

    var preview: String {
        let compact = content
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if compact.count <= 120 { return compact }
        return String(compact.prefix(120)) + "..."
    }
}

struct RecordingChatContent: Equatable {
    static let marker = "[[boson_recording]]"
    static let promptLabel = "录音 Prompt："
    static let transcriptLabel = "录音文本："

    var prompt: String
    var transcript: String

    static func format(prompt: String, transcript: String) -> String {
        [
            marker,
            promptLabel,
            prompt.trimmingCharacters(in: .whitespacesAndNewlines),
            "",
            transcriptLabel,
            transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        ].joined(separator: "\n")
    }

    static func parse(_ content: String) -> RecordingChatContent? {
        guard content.hasPrefix(marker) else { return nil }
        let body = String(content.dropFirst(marker.count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let transcriptRange = body.range(of: transcriptLabel) else { return nil }
        let promptPart = body[..<transcriptRange.lowerBound]
            .replacingOccurrences(of: promptLabel, with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let transcriptPart = body[transcriptRange.upperBound...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return RecordingChatContent(prompt: promptPart, transcript: transcriptPart)
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
    let trace: [MessageTraceItem]

    init(content: String, role: String, timestamp: String, trace: [MessageTraceItem] = []) {
        self.content = content
        self.role = role
        self.timestamp = timestamp
        self.trace = trace
    }

    static func chatMessage(
        content: String,
        role: String,
        item: [String: Any],
        fallbackTimestamp: String = ""
    ) -> ChatMessage {
        let rawTimestamp = timestamp(from: item) ?? fallbackTimestamp.trimmingCharacters(in: .whitespacesAndNewlines)
        return HistoryMessagePayload(
            content: content,
            role: role,
            timestamp: rawTimestamp,
            trace: traceItems(from: item["trace"])
        ).chatMessage
    }

    static func traceItems(from value: Any?) -> [MessageTraceItem] {
        guard let rawItems = value as? [[String: Any]] else { return [] }
        return rawItems.enumerated().compactMap { index, item in
            let content = stringValue(item["content"])
            guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            let kind = MessageTraceKind(rawHistoryValue: stringValue(item["kind"]))
            let title = stringValue(item["title"]).trimmingCharacters(in: .whitespacesAndNewlines)
            let traceId = stringValue(item["trace_id"]).trimmingCharacters(in: .whitespacesAndNewlines)
            return MessageTraceItem(
                id: traceId.isEmpty ? "trace-\(index)" : traceId,
                kind: kind,
                title: title.isEmpty ? kind.label : title,
                content: content,
                timestamp: timestamp(from: item)
            )
        }
    }

    private static func stringValue(_ value: Any?) -> String {
        if let value = value as? String { return value }
        if let value = value as? NSNumber { return value.stringValue }
        guard let value else { return "" }
        if JSONSerialization.isValidJSONObject(value),
           let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted]),
           let text = String(data: data, encoding: .utf8) {
            return text
        }
        return String(describing: value)
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
        return ChatMessage(
            content: content,
            timestamp: Self.displayTimestamp(timestamp),
            rawTimestamp: timestamp,
            senderId: senderId,
            trace: trace
        )
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
    case codex
    case custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .openclaw: return "OpenClaw"
        case .hermes: return "Hermes"
        case .codex: return "Codex"
        case .custom: return "Custom"
        }
    }

    var defaultDisplayName: String {
        switch self {
        case .openclaw: return "OpenClaw Agent"
        case .hermes: return "Hermes BosonRelay"
        case .codex: return "Codex"
        case .custom: return "Agent"
        }
    }

    var supportsAudio: Bool {
        switch self {
        case .codex: return false
        case .openclaw, .hermes, .custom: return true
        }
    }

    var iconName: String {
        switch self {
        case .openclaw: return "pawprint.fill"
        case .hermes: return "sparkles"
        case .codex: return "circle.hexagongrid.fill"
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
    var ttsEngine: String
    var minimaxApiKey: String
    var minimaxVoiceId: String
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
        ttsEngine: String = "system",
        minimaxApiKey: String = "",
        minimaxVoiceId: String = "male-qn-qingse",
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
        self.ttsEngine = ttsEngine
        self.minimaxApiKey = minimaxApiKey
        self.minimaxVoiceId = minimaxVoiceId
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
        case ttsEngine
        case minimaxApiKey
        case minimaxVoiceId
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
        ttsEngine = try container.decodeIfPresent(String.self, forKey: .ttsEngine) ?? "system"
        minimaxApiKey = try container.decodeIfPresent(String.self, forKey: .minimaxApiKey) ?? ""
        minimaxVoiceId = try container.decodeIfPresent(String.self, forKey: .minimaxVoiceId) ?? "male-qn-qingse"
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

struct AgentListActivity: Equatable {
    var latestMessagePreview: String?
    var latestMessageAt: Date?
    var lastStatus: AgentAvailabilityStatus?
    var lastStatusChangedAt: Date?

    init(
        latestMessagePreview: String? = nil,
        latestMessageAt: Date? = nil,
        lastStatus: AgentAvailabilityStatus? = nil,
        lastStatusChangedAt: Date? = nil
    ) {
        self.latestMessagePreview = latestMessagePreview
        self.latestMessageAt = latestMessageAt
        self.lastStatus = lastStatus
        self.lastStatusChangedAt = lastStatusChangedAt
    }

    var latestActivityAt: Date? {
        switch (latestMessageAt, lastStatusChangedAt) {
        case (.some(let messageAt), .some(let statusAt)):
            return max(messageAt, statusAt)
        case (.some(let messageAt), nil):
            return messageAt
        case (nil, .some(let statusAt)):
            return statusAt
        case (nil, nil):
            return nil
        }
    }
}

extension Array where Element == AgentProfile {
    func sortedForAgentList() -> [AgentProfile] {
        sortedForAgentListInternal(unreadCounts: nil, activities: nil)
    }

    func sortedForAgentList(
        unreadCounts: [String: Int],
        activities: [String: AgentListActivity]
    ) -> [AgentProfile] {
        sortedForAgentListInternal(unreadCounts: unreadCounts, activities: activities)
    }

    private func sortedForAgentListInternal(
        unreadCounts: [String: Int]?,
        activities: [String: AgentListActivity]?
    ) -> [AgentProfile] {
        sorted { left, right in
            if left.isPinned != right.isPinned {
                return left.isPinned && !right.isPinned
            }
            if left.isPinned, right.isPinned, left.sortIndex != right.sortIndex {
                return left.sortIndex < right.sortIndex
            }

            if !left.isPinned, !right.isPinned, let unreadCounts {
                let leftUnread = (unreadCounts[left.id] ?? 0) > 0
                let rightUnread = (unreadCounts[right.id] ?? 0) > 0
                if leftUnread != rightUnread {
                    return leftUnread && !rightUnread
                }
            }

            if !left.isPinned, !right.isPinned, let activities {
                let leftActivity = activities[left.id]?.latestActivityAt
                let rightActivity = activities[right.id]?.latestActivityAt
                switch (leftActivity, rightActivity) {
                case (.some(let leftDate), .some(let rightDate)) where leftDate != rightDate:
                    return leftDate > rightDate
                case (.some, nil):
                    return true
                case (nil, .some):
                    return false
                default:
                    break
                }
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
    var ttsEngine: String
    var minimaxApiKey: String
    var minimaxVoiceId: String
    var lastLoginMode: String
    var lastPhoneNumber: String

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
        asrProfileId: String = "",
        ttsEngine: String = "system",
        minimaxApiKey: String = "",
        minimaxVoiceId: String = "male-qn-qingse",
        lastLoginMode: String = "",
        lastPhoneNumber: String = ""
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
        self.ttsEngine = ttsEngine
        self.minimaxApiKey = minimaxApiKey
        self.minimaxVoiceId = minimaxVoiceId
        self.lastLoginMode = lastLoginMode
        self.lastPhoneNumber = lastPhoneNumber
    }
}

struct AiServiceChoice: Codable, Equatable {
    var mode: String
    var profileId: String
    var providerId: String
    var voiceId: String
    var baseUrl: String
    var model: String
    var credentialId: String
    var displayName: String

    init(
        mode: String,
        profileId: String = "",
        providerId: String = "",
        voiceId: String = "",
        baseUrl: String = "",
        model: String = "",
        credentialId: String = "",
        displayName: String = ""
    ) {
        self.mode = mode
        self.profileId = profileId
        self.providerId = providerId
        self.voiceId = voiceId
        self.baseUrl = baseUrl
        self.model = model
        self.credentialId = credentialId
        self.displayName = displayName
    }

    enum CodingKeys: String, CodingKey {
        case mode
        case profileId
        case providerId
        case voiceId
        case baseUrl
        case model
        case credentialId
        case displayName
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mode = try container.decodeIfPresent(String.self, forKey: .mode) ?? ""
        profileId = try container.decodeIfPresent(String.self, forKey: .profileId) ?? ""
        providerId = try container.decodeIfPresent(String.self, forKey: .providerId) ?? ""
        voiceId = try container.decodeIfPresent(String.self, forKey: .voiceId) ?? ""
        baseUrl = try container.decodeIfPresent(String.self, forKey: .baseUrl) ?? ""
        model = try container.decodeIfPresent(String.self, forKey: .model) ?? ""
        credentialId = try container.decodeIfPresent(String.self, forKey: .credentialId) ?? ""
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName) ?? ""
    }
}

struct AiByokProviderTemplate: Codable, Equatable, Identifiable {
    var id: String
    var label: String
    var keyScope: String
    var baseUrlDefault: String
    var modelDefault: String
    var credentialId: String
    var apiStyle: String
    var capabilities: [String]
    var adapter: String

    init(
        id: String,
        label: String,
        keyScope: String = "local",
        baseUrlDefault: String,
        modelDefault: String,
        credentialId: String,
        apiStyle: String = "openai-compatible",
        capabilities: [String],
        adapter: String
    ) {
        self.id = id
        self.label = label
        self.keyScope = keyScope
        self.baseUrlDefault = baseUrlDefault
        self.modelDefault = modelDefault
        self.credentialId = credentialId
        self.apiStyle = apiStyle
        self.capabilities = capabilities
        self.adapter = adapter
    }

    enum CodingKeys: String, CodingKey {
        case id
        case label
        case keyScope
        case baseUrlDefault
        case modelDefault
        case credentialId
        case apiStyle
        case capabilities
        case adapter
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
        label = try container.decodeIfPresent(String.self, forKey: .label) ?? id
        keyScope = try container.decodeIfPresent(String.self, forKey: .keyScope) ?? "local"
        baseUrlDefault = try container.decodeIfPresent(String.self, forKey: .baseUrlDefault) ?? ""
        modelDefault = try container.decodeIfPresent(String.self, forKey: .modelDefault) ?? ""
        credentialId = try container.decodeIfPresent(String.self, forKey: .credentialId) ?? ""
        apiStyle = try container.decodeIfPresent(String.self, forKey: .apiStyle) ?? "openai-compatible"
        capabilities = try container.decodeIfPresent([String].self, forKey: .capabilities) ?? []
        adapter = try container.decodeIfPresent(String.self, forKey: .adapter) ?? apiStyle
    }
}

enum AiProviderCatalog {
    static let llmByokProviders: [AiByokProviderTemplate] = [
        AiByokProviderTemplate(
            id: "openai-compatible",
            label: "OpenAI-compatible",
            baseUrlDefault: "https://api.openai.com/v1",
            modelDefault: "gpt-4o-mini",
            credentialId: localLlmOpenAICompatibleCredentialId,
            capabilities: ["llm"],
            adapter: "openai-compatible-chat"
        ),
        AiByokProviderTemplate(
            id: "minimax",
            label: "MiniMax",
            baseUrlDefault: "https://api.minimaxi.com/v1",
            modelDefault: "MiniMax-M2.7",
            credentialId: localLlmMiniMaxCredentialId,
            capabilities: ["llm"],
            adapter: "openai-compatible-chat"
        ),
        AiByokProviderTemplate(
            id: "kimi",
            label: "Kimi",
            baseUrlDefault: "https://api.moonshot.ai/v1",
            modelDefault: "moonshot-v1-8k",
            credentialId: localLlmKimiCredentialId,
            capabilities: ["llm"],
            adapter: "openai-compatible-chat"
        ),
        AiByokProviderTemplate(
            id: "claude",
            label: "Claude",
            baseUrlDefault: "https://api.anthropic.com/v1",
            modelDefault: "claude-sonnet-4-20250514",
            credentialId: localLlmClaudeCredentialId,
            apiStyle: "anthropic",
            capabilities: ["llm"],
            adapter: "anthropic-messages"
        ),
        AiByokProviderTemplate(
            id: "doubao",
            label: "豆包",
            baseUrlDefault: "https://ark.cn-beijing.volces.com/api/v3",
            modelDefault: "doubao-seed-2-0-lite-260215",
            credentialId: localLlmDoubaoCredentialId,
            capabilities: ["llm"],
            adapter: "openai-compatible-chat"
        )
    ]

    static let asrByokProviders: [AiByokProviderTemplate] = [
        AiByokProviderTemplate(
            id: "openai-compatible",
            label: "Whisper-compatible",
            baseUrlDefault: "https://api.openai.com/v1",
            modelDefault: "whisper-1",
            credentialId: localAsrOpenAICompatibleCredentialId,
            apiStyle: "openai-whisper",
            capabilities: ["asr"],
            adapter: "openai-whisper"
        ),
        AiByokProviderTemplate(
            id: "volcengine",
            label: "豆包火山云 ASR",
            baseUrlDefault: "wss://openspeech.bytedance.com/api/v3/sauc/bigmodel",
            modelDefault: "volc.bigasr.sauc.duration",
            credentialId: localAsrVolcengineCredentialId,
            apiStyle: "volcengine-bigmodel-asr",
            capabilities: ["asr"],
            adapter: "volcengine-asr"
        )
    ]

    static let ttsByokProviders: [AiByokProviderTemplate] = [
        AiByokProviderTemplate(
            id: "minimax",
            label: "MiniMax",
            baseUrlDefault: "https://api.minimaxi.com/v1",
            modelDefault: "speech-2.8-hd",
            credentialId: localMiniMaxCredentialId,
            apiStyle: "minimax-tts",
            capabilities: ["tts"],
            adapter: "minimax-tts"
        )
    ]

    static func llmProvider(id: String) -> AiByokProviderTemplate? {
        provider(in: llmByokProviders, id: id)
    }

    static func asrProvider(id: String) -> AiByokProviderTemplate? {
        provider(in: asrByokProviders, id: id)
    }

    static func ttsProvider(id: String) -> AiByokProviderTemplate? {
        provider(in: ttsByokProviders, id: id)
    }

    static func preferredProvider(
        in providers: [AiByokProviderTemplate],
        currentProviderId: String,
        hasCredential: (String) -> Bool
    ) -> AiByokProviderTemplate {
        if let providerWithKey = providers.first(where: { provider in
            let credentialId = provider.credentialId.trimmingCharacters(in: .whitespacesAndNewlines)
            return !credentialId.isEmpty && hasCredential(credentialId)
        }) {
            return providerWithKey
        }
        return provider(in: providers, id: currentProviderId) ?? providers[0]
    }

    static func choice(
        mode: String,
        provider: AiByokProviderTemplate,
        profileId: String = "",
        voiceId: String = ""
    ) -> AiServiceChoice {
        AiServiceChoice(
            mode: mode,
            profileId: mode == "router" ? profileId : "",
            providerId: provider.id,
            voiceId: voiceId,
            baseUrl: provider.baseUrlDefault,
            model: provider.modelDefault,
            credentialId: provider.credentialId,
            displayName: provider.label
        )
    }

    private static func provider(in providers: [AiByokProviderTemplate], id: String) -> AiByokProviderTemplate? {
        let normalized = id.trimmingCharacters(in: .whitespacesAndNewlines)
        return providers.first { $0.id == normalized } ?? providers.first
    }
}

struct AiServiceDefaults: Codable, Equatable {
    var llm = AiServiceChoice(
        mode: "router",
        profileId: "default",
        providerId: "router",
        displayName: "Router LLM"
    )
    var asr = AiServiceChoice(
        mode: "router",
        providerId: "router",
        displayName: "Router ASR"
    )
    var tts = AiServiceChoice(
        mode: "system",
        providerId: "system",
        voiceId: "male-qn-qingse",
        displayName: "系统 TTS"
    )

    enum CodingKeys: String, CodingKey {
        case llm
        case asr
        case tts
    }

    init(
        llm: AiServiceChoice = AiServiceDefaults.defaultLlm,
        asr: AiServiceChoice = AiServiceDefaults.defaultAsr,
        tts: AiServiceChoice = AiServiceDefaults.defaultTts
    ) {
        self.llm = llm
        self.asr = asr
        self.tts = tts
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        llm = try container.decodeIfPresent(AiServiceChoice.self, forKey: .llm) ?? Self.defaultLlm
        asr = try container.decodeIfPresent(AiServiceChoice.self, forKey: .asr) ?? Self.defaultAsr
        tts = try container.decodeIfPresent(AiServiceChoice.self, forKey: .tts) ?? Self.defaultTts
    }

    private static let defaultLlm = AiServiceChoice(
        mode: "router",
        profileId: "default",
        providerId: "router",
        displayName: "Router LLM"
    )
    private static let defaultAsr = AiServiceChoice(
        mode: "router",
        providerId: "router",
        displayName: "Router ASR"
    )
    private static let defaultTts = AiServiceChoice(
        mode: "system",
        providerId: "system",
        voiceId: "male-qn-qingse",
        displayName: "系统 TTS"
    )
}

struct AiAgentOverride: Codable, Equatable {
    var inherit = true
    var llm: AiServiceChoice?
    var asr: AiServiceChoice?
    var tts: AiServiceChoice?

    enum CodingKeys: String, CodingKey {
        case inherit
        case llm
        case asr
        case tts
    }

    init(
        inherit: Bool = true,
        llm: AiServiceChoice? = nil,
        asr: AiServiceChoice? = nil,
        tts: AiServiceChoice? = nil
    ) {
        self.inherit = inherit
        self.llm = llm
        self.asr = asr
        self.tts = tts
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        inherit = try container.decodeIfPresent(Bool.self, forKey: .inherit) ?? true
        llm = try container.decodeIfPresent(AiServiceChoice.self, forKey: .llm)
        asr = try container.decodeIfPresent(AiServiceChoice.self, forKey: .asr)
        tts = try container.decodeIfPresent(AiServiceChoice.self, forKey: .tts)
    }
}

struct AiServiceConfig: Codable, Equatable, Identifiable {
    var id: String
    var capability: String
    var mode: String
    var profileId: String
    var providerId: String
    var voiceId: String
    var baseUrl: String
    var model: String
    var credentialId: String
    var displayName: String
    var enabled: Bool
    var status: String

    init(
        id: String,
        capability: String,
        mode: String,
        profileId: String = "",
        providerId: String = "",
        voiceId: String = "",
        baseUrl: String = "",
        model: String = "",
        credentialId: String = "",
        displayName: String = "",
        enabled: Bool = true,
        status: String = "available"
    ) {
        self.id = id
        self.capability = capability
        self.mode = mode
        self.profileId = profileId
        self.providerId = providerId
        self.voiceId = voiceId
        self.baseUrl = baseUrl
        self.model = model
        self.credentialId = credentialId
        self.displayName = displayName
        self.enabled = enabled
        self.status = status
    }

    enum CodingKeys: String, CodingKey {
        case id
        case capability
        case mode
        case profileId
        case providerId
        case voiceId
        case baseUrl
        case model
        case credentialId
        case displayName
        case enabled
        case status
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
        capability = try container.decodeIfPresent(String.self, forKey: .capability) ?? "llm"
        mode = try container.decodeIfPresent(String.self, forKey: .mode) ?? ""
        profileId = try container.decodeIfPresent(String.self, forKey: .profileId) ?? ""
        providerId = try container.decodeIfPresent(String.self, forKey: .providerId) ?? ""
        voiceId = try container.decodeIfPresent(String.self, forKey: .voiceId) ?? ""
        baseUrl = try container.decodeIfPresent(String.self, forKey: .baseUrl) ?? ""
        model = try container.decodeIfPresent(String.self, forKey: .model) ?? ""
        credentialId = try container.decodeIfPresent(String.self, forKey: .credentialId) ?? ""
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName) ?? ""
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? "available"
    }
}

struct AiServiceConfigLibrary: Codable, Equatable {
    var llm: [AiServiceConfig] = []
    var asr: [AiServiceConfig] = []
    var tts: [AiServiceConfig] = []

    var isEmpty: Bool { llm.isEmpty && asr.isEmpty && tts.isEmpty }

    init(
        llm: [AiServiceConfig] = [],
        asr: [AiServiceConfig] = [],
        tts: [AiServiceConfig] = []
    ) {
        self.llm = llm
        self.asr = asr
        self.tts = tts
    }

    enum CodingKeys: String, CodingKey {
        case llm
        case asr
        case tts
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        llm = try container.decodeIfPresent([AiServiceConfig].self, forKey: .llm) ?? []
        asr = try container.decodeIfPresent([AiServiceConfig].self, forKey: .asr) ?? []
        tts = try container.decodeIfPresent([AiServiceConfig].self, forKey: .tts) ?? []
    }
}

struct AiProviderChatSelection: Codable, Equatable {
    var llmConfigId = ""
}

struct AiRecordingSelection: Codable, Equatable {
    var asrConfigId = ""
}

struct AiPlaybackSelection: Codable, Equatable {
    var ttsConfigId = ""
}

struct AiSceneAgentOverride: Codable, Equatable {
    var inherit = true
    var llmConfigId = ""
    var asrConfigId = ""
    var ttsConfigId = ""
}

struct AiSceneSelections: Codable, Equatable {
    var providerChat = AiProviderChatSelection()
    var recording = AiRecordingSelection()
    var playback = AiPlaybackSelection()
    var agentOverrides: [String: AiSceneAgentOverride] = [:]

    enum CodingKeys: String, CodingKey {
        case providerChat
        case recording
        case playback
        case agentOverrides
    }

    init(
        providerChat: AiProviderChatSelection = AiProviderChatSelection(),
        recording: AiRecordingSelection = AiRecordingSelection(),
        playback: AiPlaybackSelection = AiPlaybackSelection(),
        agentOverrides: [String: AiSceneAgentOverride] = [:]
    ) {
        self.providerChat = providerChat
        self.recording = recording
        self.playback = playback
        self.agentOverrides = agentOverrides
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        providerChat = try container.decodeIfPresent(AiProviderChatSelection.self, forKey: .providerChat) ?? AiProviderChatSelection()
        recording = try container.decodeIfPresent(AiRecordingSelection.self, forKey: .recording) ?? AiRecordingSelection()
        playback = try container.decodeIfPresent(AiPlaybackSelection.self, forKey: .playback) ?? AiPlaybackSelection()
        agentOverrides = try container.decodeIfPresent([String: AiSceneAgentOverride].self, forKey: .agentOverrides) ?? [:]
    }
}

struct AiServiceSettings: Codable, Equatable {
    var version = 2
    var serviceConfigs = AiServiceConfigLibrary()
    var sceneSelections = AiSceneSelections()
    var defaults = AiServiceDefaults()
    var agentOverrides: [String: AiAgentOverride] = [:]

    enum CodingKeys: String, CodingKey {
        case version
        case serviceConfigs
        case sceneSelections
        case defaults
        case agentOverrides
    }

    init(
        version: Int = 2,
        serviceConfigs: AiServiceConfigLibrary = AiServiceConfigLibrary(),
        sceneSelections: AiSceneSelections = AiSceneSelections(),
        defaults: AiServiceDefaults = AiServiceDefaults(),
        agentOverrides: [String: AiAgentOverride] = [:]
    ) {
        self.init(
            rawVersion: version,
            rawServiceConfigs: serviceConfigs,
            rawSceneSelections: sceneSelections,
            rawDefaults: defaults,
            rawAgentOverrides: agentOverrides
        )
        self = normalizedRaw()
    }

    private init(
        rawVersion: Int,
        rawServiceConfigs: AiServiceConfigLibrary,
        rawSceneSelections: AiSceneSelections,
        rawDefaults: AiServiceDefaults,
        rawAgentOverrides: [String: AiAgentOverride]
    ) {
        version = rawVersion
        serviceConfigs = rawServiceConfigs
        sceneSelections = rawSceneSelections
        defaults = rawDefaults
        agentOverrides = rawAgentOverrides
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            rawVersion: try container.decodeIfPresent(Int.self, forKey: .version) ?? 2,
            rawServiceConfigs: try container.decodeIfPresent(AiServiceConfigLibrary.self, forKey: .serviceConfigs) ?? AiServiceConfigLibrary(),
            rawSceneSelections: try container.decodeIfPresent(AiSceneSelections.self, forKey: .sceneSelections) ?? AiSceneSelections(),
            rawDefaults: try container.decodeIfPresent(AiServiceDefaults.self, forKey: .defaults) ?? AiServiceDefaults(),
            rawAgentOverrides: try container.decodeIfPresent([String: AiAgentOverride].self, forKey: .agentOverrides) ?? [:]
        )
        self = normalizedRaw()
    }

    func encode(to encoder: Encoder) throws {
        let normalized = normalizedRaw()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(2, forKey: .version)
        try container.encode(normalized.serviceConfigs, forKey: .serviceConfigs)
        try container.encode(normalized.sceneSelections, forKey: .sceneSelections)
        try container.encode(normalized.defaults, forKey: .defaults)
        try container.encode(normalized.agentOverrides, forKey: .agentOverrides)
    }

    func resolved(for profileId: String) -> AiServiceDefaults {
        guard let override = agentOverrides[profileId], !override.inherit else {
            return defaults
        }
        return AiServiceDefaults(
            llm: override.llm ?? defaults.llm,
            asr: override.asr ?? defaults.asr,
            tts: override.tts ?? defaults.tts
        )
    }

    func llmConfigForProviderChat() -> AiServiceConfig? {
        serviceConfigs.llm.config(id: sceneSelections.providerChat.llmConfigId)
            ?? serviceConfigs.llm.firstSelectable
    }

    func asrConfigForRecording() -> AiServiceConfig? {
        serviceConfigs.asr.config(id: sceneSelections.recording.asrConfigId)
            ?? serviceConfigs.asr.firstSelectable
    }

    func ttsConfigForPlayback() -> AiServiceConfig? {
        serviceConfigs.tts.config(id: sceneSelections.playback.ttsConfigId)
            ?? serviceConfigs.tts.firstSelectable
    }

    func upsertingServiceConfig(_ config: AiServiceConfig) -> AiServiceSettings {
        let normalizedConfig = config.normalized(capability: config.capability.normalizedCapability)
        var nextLibrary = serviceConfigs
        switch normalizedConfig.capability {
        case "asr":
            nextLibrary.asr = nextLibrary.asr.upserting(normalizedConfig)
        case "tts":
            nextLibrary.tts = nextLibrary.tts.upserting(normalizedConfig)
        default:
            nextLibrary.llm = nextLibrary.llm.upserting(normalizedConfig)
        }
        return AiServiceSettings(
            version: 2,
            serviceConfigs: nextLibrary,
            sceneSelections: sceneSelections,
            defaults: defaults,
            agentOverrides: agentOverrides
        )
    }

    func updatingSceneSelection(
        providerChatLlmConfigId: String? = nil,
        recordingAsrConfigId: String? = nil,
        playbackTtsConfigId: String? = nil
    ) -> AiServiceSettings {
        AiServiceSettings(
            version: 2,
            serviceConfigs: serviceConfigs,
            sceneSelections: AiSceneSelections(
                providerChat: AiProviderChatSelection(llmConfigId: providerChatLlmConfigId ?? sceneSelections.providerChat.llmConfigId),
                recording: AiRecordingSelection(asrConfigId: recordingAsrConfigId ?? sceneSelections.recording.asrConfigId),
                playback: AiPlaybackSelection(ttsConfigId: playbackTtsConfigId ?? sceneSelections.playback.ttsConfigId),
                agentOverrides: sceneSelections.agentOverrides
            ),
            defaults: defaults,
            agentOverrides: agentOverrides
        )
    }

    private func normalizedRaw() -> AiServiceSettings {
        if serviceConfigs.isEmpty {
            return Self.migrateLegacy(defaults: defaults, agentOverrides: agentOverrides)
        }
        let library = serviceConfigs.normalizedWithCoreConfigs()
        let selections = sceneSelections.normalized(library: library)
        return AiServiceSettings(
            rawVersion: 2,
            rawServiceConfigs: library,
            rawSceneSelections: selections,
            rawDefaults: library.projectDefaults(selections: selections),
            rawAgentOverrides: library.projectAgentOverrides(selections: selections)
        )
    }

    private static func migrateLegacy(
        defaults: AiServiceDefaults,
        agentOverrides: [String: AiAgentOverride]
    ) -> AiServiceSettings {
        var library = MutableAiServiceConfigLibrary()
        let normalizedDefaults = AiServiceDefaults(
            llm: defaults.llm.normalized(fallback: AiServiceDefaults().llm, capability: "llm"),
            asr: defaults.asr.normalized(fallback: AiServiceDefaults().asr, capability: "asr"),
            tts: defaults.tts.normalized(fallback: AiServiceDefaults().tts, capability: "tts")
        )
        let llmConfigId = library.add(capability: "llm", choice: normalizedDefaults.llm)
        let asrConfigId = library.add(capability: "asr", choice: normalizedDefaults.asr)
        let ttsConfigId = library.add(capability: "tts", choice: normalizedDefaults.tts)
        var sceneOverrides: [String: AiSceneAgentOverride] = [:]
        for (profileId, override) in agentOverrides where !profileId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sceneOverrides[profileId] = AiSceneAgentOverride(
                inherit: override.inherit,
                llmConfigId: override.llm.map { library.add(capability: "llm", choice: $0.normalized(fallback: normalizedDefaults.llm, capability: "llm")) } ?? "",
                asrConfigId: override.asr.map { library.add(capability: "asr", choice: $0.normalized(fallback: normalizedDefaults.asr, capability: "asr")) } ?? "",
                ttsConfigId: override.tts.map { library.add(capability: "tts", choice: $0.normalized(fallback: normalizedDefaults.tts, capability: "tts")) } ?? ""
            )
        }
        return AiServiceSettings(
            rawVersion: 2,
            rawServiceConfigs: library.library,
            rawSceneSelections: AiSceneSelections(
                providerChat: AiProviderChatSelection(llmConfigId: llmConfigId),
                recording: AiRecordingSelection(asrConfigId: asrConfigId),
                playback: AiPlaybackSelection(ttsConfigId: ttsConfigId),
                agentOverrides: sceneOverrides
            ),
            rawDefaults: normalizedDefaults,
            rawAgentOverrides: agentOverrides
        ).normalizedRaw()
    }
}

private struct MutableAiServiceConfigLibrary {
    private var llm: [String: AiServiceConfig] = [:]
    private var asr: [String: AiServiceConfig] = [:]
    private var tts: [String: AiServiceConfig] = [:]
    private var llmOrder: [String] = []
    private var asrOrder: [String] = []
    private var ttsOrder: [String] = []

    mutating func add(capability: String, choice: AiServiceChoice) -> String {
        let normalizedCapability = capability.normalizedCapability
        let config = choice.toServiceConfig(capability: normalizedCapability).normalized(capability: normalizedCapability)
        switch normalizedCapability {
        case "asr":
            if asr[config.id] == nil { asrOrder.append(config.id) }
            asr[config.id] = config
        case "tts":
            if tts[config.id] == nil { ttsOrder.append(config.id) }
            tts[config.id] = config
        default:
            if llm[config.id] == nil { llmOrder.append(config.id) }
            llm[config.id] = config
        }
        return config.id
    }

    var library: AiServiceConfigLibrary {
        AiServiceConfigLibrary(
            llm: llmOrder.compactMap { llm[$0] },
            asr: asrOrder.compactMap { asr[$0] },
            tts: ttsOrder.compactMap { tts[$0] }
        )
    }
}

extension AiServiceConfig {
    var isSelectable: Bool {
        enabled && status != "coming_soon" && status != "disabled"
    }

    func toChoice() -> AiServiceChoice {
        switch mode {
        case "router":
            return AiServiceChoice(
                mode: "router",
                profileId: profileId,
                providerId: "router",
                displayName: displayName
            )
        case "backend", "agent":
            return AiServiceChoice(
                mode: "backend",
                providerId: "agent",
                displayName: displayName
            )
        case "system":
            return AiServiceChoice(
                mode: "system",
                providerId: "system",
                voiceId: voiceId,
                displayName: displayName
            )
        default:
            return AiServiceChoice(
                mode: mode,
                profileId: profileId,
                providerId: providerId,
                voiceId: voiceId,
                baseUrl: baseUrl,
                model: model,
                credentialId: credentialId,
                displayName: displayName
            )
        }
    }

    func normalized(capability expectedCapability: String) -> AiServiceConfig {
        let nextCapability = expectedCapability.normalizedCapability
        let nextMode = mode.normalizedMode(capability: nextCapability)
        var nextProviderId = providerId.trimmed
        var nextProfileId = profileId.trimmed
        let nextVoiceId = voiceId.trimmed
        var nextBaseUrl = baseUrl.trimmed.trimmedTrailingSlash
        var nextModel = model.trimmed
        var nextCredentialId = credentialId.trimmed
        var nextEnabled = enabled
        var nextStatus = status.trimmed.isEmpty ? "available" : status.trimmed

        switch nextMode {
        case "router":
            nextProviderId = "router"
            nextBaseUrl = ""
            nextModel = ""
            nextCredentialId = ""
            if nextCapability == "tts" {
                nextEnabled = false
                nextStatus = "coming_soon"
            }
        case "byok":
            nextProviderId = nextProviderId.isEmpty ? nextCapability.defaultByokProviderId : nextProviderId
            nextBaseUrl = normalizeProviderBaseUrl(capability: nextCapability, providerId: nextProviderId, baseUrl: nextBaseUrl)
            nextModel = nextModel.isEmpty ? defaultModel(capability: nextCapability, providerId: nextProviderId) : nextModel
            nextCredentialId = nextCredentialId.isEmpty ? "\(nextCapability):\(nextProviderId)" : nextCredentialId
        case "backend", "agent":
            nextProviderId = "agent"
            nextProfileId = ""
            nextBaseUrl = ""
            nextModel = ""
            nextCredentialId = ""
        case "system":
            nextProviderId = "system"
            nextProfileId = ""
            nextBaseUrl = ""
            nextModel = ""
            nextCredentialId = ""
        default:
            break
        }
        if nextStatus != "coming_soon" && nextStatus != "disabled" {
            nextStatus = nextEnabled ? "available" : "disabled"
        }
        let choice = AiServiceChoice(
            mode: nextMode,
            profileId: nextProfileId,
            providerId: nextProviderId,
            baseUrl: nextBaseUrl,
            model: nextModel,
            credentialId: nextCredentialId
        )
        return AiServiceConfig(
            id: id.trimmed.isEmpty ? configId(capability: nextCapability, choice: choice) : id.trimmed,
            capability: nextCapability,
            mode: nextMode == "agent" ? "backend" : nextMode,
            profileId: nextProfileId,
            providerId: nextProviderId,
            voiceId: nextVoiceId,
            baseUrl: nextBaseUrl,
            model: nextModel,
            credentialId: nextCredentialId,
            displayName: displayName.trimmed.isEmpty ? inferDisplayName(capability: nextCapability, mode: nextMode, providerId: nextProviderId) : displayName.trimmed,
            enabled: nextEnabled,
            status: nextStatus
        )
    }
}

extension AiServiceChoice {
    func toServiceConfig(capability: String, id: String = "") -> AiServiceConfig {
        let normalizedCapability = capability.normalizedCapability
        return AiServiceConfig(
            id: id.isEmpty ? configId(capability: normalizedCapability, choice: self) : id,
            capability: normalizedCapability,
            mode: mode,
            profileId: profileId,
            providerId: providerId,
            voiceId: voiceId,
            baseUrl: baseUrl,
            model: model,
            credentialId: credentialId,
            displayName: displayName
        ).normalized(capability: normalizedCapability)
    }

    fileprivate func normalized(fallback: AiServiceChoice, capability: String) -> AiServiceChoice {
        let nextMode = mode.isEmpty ? fallback.mode : mode
        if nextMode == "router" {
            return AiServiceChoice(
                mode: "router",
                profileId: profileId.isEmpty ? fallback.profileId : profileId,
                providerId: "router",
                displayName: displayName.isEmpty ? fallback.displayName : displayName
            )
        }
        return AiServiceChoice(
            mode: nextMode,
            profileId: profileId,
            providerId: providerId.isEmpty ? fallback.providerId : providerId,
            voiceId: voiceId.isEmpty ? fallback.voiceId : voiceId,
            baseUrl: normalizeProviderBaseUrl(capability: capability, providerId: providerId.isEmpty ? fallback.providerId : providerId, baseUrl: baseUrl.isEmpty ? fallback.baseUrl : baseUrl),
            model: model.isEmpty ? fallback.model : model,
            credentialId: credentialId.isEmpty ? fallback.credentialId : credentialId,
            displayName: displayName.isEmpty ? fallback.displayName : displayName
        )
    }
}

extension AiServiceConfigLibrary {
    fileprivate func normalizedWithCoreConfigs() -> AiServiceConfigLibrary {
        var library = AiServiceConfigLibrary(
            llm: llm.map { $0.normalized(capability: "llm") }.distinctById,
            asr: asr.map { $0.normalized(capability: "asr") }.distinctById,
            tts: tts.map { $0.normalized(capability: "tts") }.distinctById
        )
        if !library.tts.contains(where: { $0.id == "tts-system" }) {
            library.tts.insert(
                AiServiceConfig(
                    id: "tts-system",
                    capability: "tts",
                    mode: "system",
                    providerId: "system",
                    displayName: "系统 TTS"
                ).normalized(capability: "tts"),
                at: 0
            )
        }
        return library
    }

    fileprivate func projectDefaults(selections: AiSceneSelections) -> AiServiceDefaults {
        AiServiceDefaults(
            llm: llm.config(id: selections.providerChat.llmConfigId)?.toChoice() ?? AiServiceDefaults().llm,
            asr: asr.config(id: selections.recording.asrConfigId)?.toChoice() ?? AiServiceDefaults().asr,
            tts: tts.config(id: selections.playback.ttsConfigId)?.toChoice() ?? AiServiceDefaults().tts
        )
    }

    fileprivate func projectAgentOverrides(selections: AiSceneSelections) -> [String: AiAgentOverride] {
        selections.agentOverrides.mapValues { override in
            AiAgentOverride(
                inherit: override.inherit,
                llm: llm.config(id: override.llmConfigId)?.toChoice(),
                asr: asr.config(id: override.asrConfigId)?.toChoice(),
                tts: tts.config(id: override.ttsConfigId)?.toChoice()
            )
        }
    }
}

extension AiSceneSelections {
    fileprivate func normalized(library: AiServiceConfigLibrary) -> AiSceneSelections {
        AiSceneSelections(
            providerChat: AiProviderChatSelection(
                llmConfigId: library.llm.validSelectableId(providerChat.llmConfigId)
                    .ifEmpty(library.llm.firstSelectableId)
            ),
            recording: AiRecordingSelection(
                asrConfigId: library.asr.validSelectableId(recording.asrConfigId)
                    .ifEmpty(library.asr.firstSelectableId)
            ),
            playback: AiPlaybackSelection(
                ttsConfigId: library.tts.validSelectableId(playback.ttsConfigId)
                    .ifEmpty(library.tts.firstSelectableId)
            ),
            agentOverrides: agentOverrides.mapValues { override in
                AiSceneAgentOverride(
                    inherit: override.inherit,
                    llmConfigId: library.llm.validSelectableId(override.llmConfigId),
                    asrConfigId: library.asr.validSelectableId(override.asrConfigId),
                    ttsConfigId: library.tts.validSelectableId(override.ttsConfigId)
                )
            }
        )
    }
}

extension Array where Element == AiServiceConfig {
    fileprivate func config(id: String) -> AiServiceConfig? {
        first { $0.id == id }
    }

    fileprivate var firstSelectable: AiServiceConfig? {
        first { $0.isSelectable }
    }

    fileprivate var firstSelectableId: String {
        firstSelectable?.id ?? first?.id ?? ""
    }

    fileprivate func validSelectableId(_ id: String) -> String {
        contains { $0.id == id && $0.isSelectable } ? id : ""
    }

    fileprivate var distinctById: [AiServiceConfig] {
        var seen = Set<String>()
        var result: [AiServiceConfig] = []
        for config in self where !seen.contains(config.id) {
            seen.insert(config.id)
            result.append(config)
        }
        return result
    }

    fileprivate func upserting(_ config: AiServiceConfig) -> [AiServiceConfig] {
        (filter { $0.id != config.id } + [config]).distinctById
    }
}

private func configId(capability: String, choice: AiServiceChoice) -> String {
    let mode = choice.mode.normalizedMode(capability: capability)
    switch mode {
    case "router":
        return "\(capability)-router-\((choice.profileId.isEmpty ? "default" : choice.profileId).slug)"
    case "byok":
        return "\(capability)-byok-\((choice.providerId.isEmpty ? "custom" : choice.providerId).slug)"
    case "system":
        return "\(capability)-system"
    default:
        return "\(capability)-agent-backend"
    }
}

private func normalizeProviderBaseUrl(capability: String, providerId: String, baseUrl: String) -> String {
    let fallback = baseUrl.isEmpty ? defaultBaseUrl(capability: capability, providerId: providerId) : baseUrl.trimmedTrailingSlash
    if providerId == "minimax", fallback == "https://api.minimax.com/v1" {
        return "https://api.minimaxi.com/v1"
    }
    return fallback
}

private func defaultBaseUrl(capability: String, providerId: String) -> String {
    switch providerId {
    case "minimax":
        return "https://api.minimaxi.com/v1"
    case "kimi":
        return "https://api.moonshot.ai/v1"
    case "claude":
        return "https://api.anthropic.com/v1"
    case "doubao":
        return "https://ark.cn-beijing.volces.com/api/v3"
    case "volcengine":
        return capability == "asr"
            ? "wss://openspeech.bytedance.com/api/v3/sauc/bigmodel"
            : "https://api.openai.com/v1"
    default:
        return "https://api.openai.com/v1"
    }
}

private func defaultModel(capability: String, providerId: String) -> String {
    if capability == "tts", providerId == "minimax" { return "speech-2.8-hd" }
    if capability == "asr", providerId == "volcengine" { return "volc.bigasr.sauc.duration" }
    if capability == "asr" { return "whisper-1" }
    switch providerId {
    case "minimax":
        return "MiniMax-M2.7"
    case "kimi":
        return "moonshot-v1-8k"
    case "claude":
        return "claude-sonnet-4-20250514"
    case "doubao":
        return "doubao-seed-2-0-lite-260215"
    default:
        return "gpt-4o-mini"
    }
}

private func inferDisplayName(capability: String, mode: String, providerId: String) -> String {
    switch mode {
    case "router":
        return capability == "tts" ? "Router TTS" : "Router \(capability.uppercased())"
    case "backend", "agent":
        return "Agent 后端识别"
    case "system":
        return "系统 TTS"
    default:
        return providerId.isEmpty ? "BYOK" : providerId
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedTrailingSlash: String {
        var value = trimmed
        while value.hasSuffix("/") {
            value.removeLast()
        }
        return value
    }

    var normalizedCapability: String {
        switch self {
        case "asr": return "asr"
        case "tts": return "tts"
        default: return "llm"
        }
    }

    func normalizedMode(capability: String) -> String {
        switch self {
        case "router", "byok", "backend", "agent", "system":
            return self
        default:
            return capability == "tts" ? "system" : "router"
        }
    }

    var defaultByokProviderId: String {
        self == "tts" ? "minimax" : "openai-compatible"
    }

    var slug: String {
        let normalized = lowercased()
            .map { character -> Character in
                character.isLetter || character.isNumber ? character : "-"
            }
        let compact = String(normalized)
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
        return compact.isEmpty ? "default" : compact
    }

    func ifEmpty(_ fallback: String) -> String {
        isEmpty ? fallback : self
    }
}

enum RecordingType: String, Codable, CaseIterable, Identifiable {
    case audioOnly = "audio_only"
    case meeting
    case idea
    case custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .audioOnly: return "仅录音"
        case .meeting: return "会议录音"
        case .idea: return "灵感记录"
        case .custom: return "自定义录音"
        }
    }

    var systemImage: String {
        switch self {
        case .audioOnly: return "waveform"
        case .meeting: return "person.3.sequence"
        case .idea: return "lightbulb"
        case .custom: return "slider.horizontal.3"
        }
    }

    var sendsToAgent: Bool {
        self != .audioOnly
    }
}

enum RecordingProcessingStatus: String, Codable, Equatable {
    case savedOnly = "saved_only"
    case queued
    case processing
    case completed
    case failed

    var label: String {
        switch self {
        case .savedOnly: return "仅保存"
        case .queued: return "等待处理"
        case .processing: return "处理中"
        case .completed: return "已完成"
        case .failed: return "处理失败"
        }
    }
}

struct RecordingSettings: Equatable {
    static let defaultPrompt = "以下是录音，根据录音，分析是否有要解决的问题或者要收集的信息，如果有，列出任务执行的计划并按照计划执行；如果有定时任务，置顶定时任务"

    static let meetingPrompt = """
    以下是会议录音。请根据录音整理并执行，正文固定使用以下结构：
    # 会议纪要
    ## 会议核心结论
    ## Agent 可承接的待办
    ## 需要人完成的待办
    ## 已开始执行/产出

    会议纪要需要包含主题、背景、关键讨论、结论、决策与风险。
    请拆分会议待办为两类：
    1. Agent 可以完成的事项，例如数据分析、资料收集、调研报告、文档整理。每个事项必须拆成独立子任务，并优先基于合理假设直接开始执行；缺少业务场景、数据规模、查询场景等信息时，先写明假设并继续推进，不要默认询问用户先做哪一项。
    2. 需要人完成的事项，形成 checklist，尽量提取负责人和截止时间；只有缺少信息导致无法产生任何有效结果时，才向用户提问。
    如果识别到 Loose Index、LLM-Friendly 索引、Lucene 对比等多个 Agent 可做事项，必须拆成多个独立子任务并逐个跟进。
    如果创建了定时任务，请输出 scheduled_task 事件。
    最终请保存一份 Markdown 会议纪要文件，并输出 artifact 事件；后续调研或报告也应分别保存 Markdown 文件并输出 artifact 事件。
    """

    static let ideaPrompt = """
    以下是灵感记录。请把它交给后台 Agent 生成一份研究型灵感报告，而不是只做简短摘要或聊天式回复。
    报告必须保存为 Markdown artifact，并使用以下结构：
    # 灵感研究报告
    ## 摘要
    ## 问题/机会
    ## 核心洞察
    ## 方案
    ## 风险
    ## 行动项

    写作要求：
    1. 不只复述录音，要补充必要背景、推理过程、约束、取舍和可执行路径。
    2. 信息不足时先写明假设，并基于合理假设继续推进，不要默认停下来询问用户。
    3. 行动项要区分 Agent 可继续完成的事项和需要用户确认/执行的事项。
    4. 如果识别到后续提醒、定时任务或子任务，请在报告的行动项中明确标注，不要输出事件块。
    5. 后台会生成 Markdown artifact 和 3-5 句摘要；报告正文必须完整、深入、可直接导出。
    """

    static let recordingEventProtocolPrompt = """
    请在处理录音时，把关键执行过程用结构化事件块输出，系统会自动归档到这条录音。
    事件块必须只输出一次，并且内容必须是一个合法 JSON 数组。禁止输出多个相邻 JSON 对象，禁止使用 {"boson-recording-event": {...}} 包裹格式：
    ```boson-recording-event
    [
      {"kind":"subtask","title":"调研 Loose Index / 轻量化索引技术方案","content":"搜集轻量化索引方案、开源项目、技术论文，输出调研报告","status":"pending","data":{"task_id":"research-loose-index","owner":"agent","next_action":"开始调研并补充文档","needs_user_input":false,"assumptions":["缺少业务场景时，先按手机端本地搜索场景调研"]}},
      {"kind":"artifact","title":"Loose Index 调研报告","content":"research.md","status":"completed","data":{"related_task_id":"research-loose-index","artifact":{"filename":"research.md","mime_type":"text/markdown","encoding":"utf8","content":"# 调研报告\\n\\n文件内容","backend_path":"可选路径"}}}
    ]
    ```
    支持 kind: agent_reply, subtask, scheduled_task, reminder, artifact, error。
    Agent 可承接的事项每一项都必须单独输出 subtask，data.owner="agent"，并在 data.task_id 写稳定短 ID；需要人完成或确认的事项输出 data.owner="user"，只有真正阻塞时才设置 data.needs_user_input=true。
    请优先基于合理假设直接开始执行，把假设写入 data.assumptions；不要默认询问用户先做哪一项。
    保存文档时必须输出 artifact 事件；如果文件是某个 Agent 待办的产物，必须在 data.related_task_id 填对应 subtask 的 data.task_id。data.artifact 格式为 {"filename":"name.md","mime_type":"text/markdown","encoding":"utf8","content":"文件内容","backend_path":"可选路径"}。
    请不要在面向用户的正文里解释这个事件协议。
    """

    var primaryAgentProfileId: String
    var deliverToAgent: Bool
    var prompt: String
    var asrProfileId: String
    var defaultRecordingType: RecordingType
    var customPrompt: String
    var defaultDeliverToAgent: Bool

    init(
        primaryAgentProfileId: String = "",
        deliverToAgent: Bool = true,
        prompt: String = Self.defaultPrompt,
        asrProfileId: String = "",
        defaultRecordingType: RecordingType = .audioOnly,
        customPrompt: String = "",
        defaultDeliverToAgent: Bool = true
    ) {
        self.primaryAgentProfileId = primaryAgentProfileId
        self.deliverToAgent = deliverToAgent
        self.prompt = prompt
        self.asrProfileId = asrProfileId
        self.defaultRecordingType = defaultRecordingType
        self.customPrompt = customPrompt
        self.defaultDeliverToAgent = defaultDeliverToAgent
    }

    func prompt(for type: RecordingType) -> String {
        switch type {
        case .audioOnly:
            return ""
        case .meeting:
            return Self.meetingPrompt
        case .idea:
            return Self.ideaPrompt
        case .custom:
            return customPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    var settingsTypeOptions: [RecordingType] {
        RecordingType.allCases
    }

    var recordingSelectionTypeOptions: [RecordingType] {
        settingsTypeOptions.filter { type in
            type != .custom || !customPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    var defaultSelectionType: RecordingType {
        recordingSelectionTypeOptions.contains(defaultRecordingType)
            ? defaultRecordingType
            : (recordingSelectionTypeOptions.first ?? .audioOnly)
    }
}

struct AudioAsrPayload {
    var jsonObject: [String: Any]

    static func chat(mode: String, profileId: String) -> AudioAsrPayload {
        var payload: [String: Any] = [
            "mode": mode == "backend" ? "backend" : "router"
        ]
        if !profileId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            payload["profile_id"] = profileId
        }
        return AudioAsrPayload(jsonObject: payload)
    }

    static func recording(
        settings: RecordingSettings,
        source: RecordingInputSource,
        recordingId: String? = nil,
        recordingType: RecordingType,
        prompt: String
    ) -> AudioAsrPayload {
        var payload = chat(mode: "router", profileId: settings.asrProfileId).jsonObject
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        payload["intent"] = "recording"
        payload["source"] = source.rawValue
        payload["recording_type"] = recordingType.rawValue
        payload["deliver_to_agent"] = recordingType.sendsToAgent
        if recordingType.sendsToAgent, !trimmedPrompt.isEmpty {
            payload["agent_prompt"] = trimmedPrompt
        }
        if let recordingId, !recordingId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            payload["recording_id"] = recordingId
        }
        return AudioAsrPayload(jsonObject: payload)
    }

    static func recording(settings: RecordingSettings, source: RecordingInputSource, recordingId: String? = nil) -> AudioAsrPayload {
        let type: RecordingType = settings.deliverToAgent ? .custom : .audioOnly
        let prompt = settings.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? RecordingSettings.defaultPrompt : settings.prompt
        return recording(settings: settings, source: source, recordingId: recordingId, recordingType: type, prompt: prompt)
    }
}

struct LongRecordingAsrJobRequest {
    var recordingId: String
    var backendId: String
    var clientMessageId: String
    var recordingType: RecordingType
    var source: RecordingInputSource
    var prompt: String
    var settings: RecordingSettings
    var fileSize: Int
    var sha256: String

    var jsonObject: [String: Any] {
        var json: [String: Any] = [
            "recording_id": recordingId,
            "backend_id": backendId,
            "client_message_id": clientMessageId,
            "recording_type": recordingType.rawValue,
            "source": source.rawValue,
            "file_size": fileSize,
            "sha256": sha256,
            "audio": [
                "format": "wav",
                "codec": "pcm_s16le",
                "sample_rate": 16000,
                "channels": 1
            ],
            "asr": AudioAsrPayload.recording(
                settings: settings,
                source: source,
                recordingId: recordingId,
                recordingType: recordingType,
                prompt: prompt
            ).jsonObject
        ]
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if recordingType.sendsToAgent, !trimmedPrompt.isEmpty {
            json["agent_prompt"] = trimmedPrompt
        }
        return json
    }
}

struct LongRecordingAsrJobStatusPayload: Equatable {
    var jobId: String
    var recordingId: String?
    var clientMessageId: String?
    var status: String
    var phase: String?
    var uploadProgress: Double
    var asrProgress: Double
    var error: String?
    var errorMessage: String?
    var retryable: Bool
    var transcript: String?
    var providerStatusCode: String?
    var providerLogId: String?
    var deliveryStatus: String?
    var deliveryAttempts: Int
    var deliveryError: String?
    var deliveryRetryable: Bool
    var deliveryUpdatedAt: String?
    var deliveredAt: String?

    init?(json: [String: Any]) {
        guard let jobId = json["job_id"] as? String else { return nil }
        self.jobId = jobId
        recordingId = json["recording_id"] as? String
        clientMessageId = json["client_message_id"] as? String
        status = json["status"] as? String ?? ""
        phase = json["phase"] as? String
        if let uploadPercent = Self.doubleValue(json["upload_percent"]) {
            uploadProgress = min(max(uploadPercent / 100, 0), 1)
        } else if let uploadedBytes = Self.doubleValue(json["uploaded_bytes"]),
                  let fileSize = Self.doubleValue(json["file_size"]),
                  fileSize > 0 {
            uploadProgress = min(max(uploadedBytes / fileSize, 0), 1)
        } else {
            uploadProgress = 0
        }
        if let progress = json["asr_progress"] as? [String: Any],
           let percent = Self.doubleValue(progress["percent"]) {
            asrProgress = min(max(percent / 100, 0), 1)
        } else {
            asrProgress = 0
        }
        error = json["error"] as? String
        errorMessage = json["error_message"] as? String
        retryable = json["retryable"] as? Bool ?? false
        transcript = json["transcript"] as? String
        providerStatusCode = json["provider_status_code"] as? String
        providerLogId = json["provider_log_id"] as? String
        deliveryStatus = json["delivery_status"] as? String
        deliveryAttempts = Self.intValue(json["delivery_attempts"]) ?? 0
        deliveryError = json["delivery_error"] as? String
        deliveryRetryable = json["delivery_retryable"] as? Bool ?? false
        deliveryUpdatedAt = json["delivery_updated_at"] as? String
        deliveredAt = json["delivered_at"] as? String
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? String { return Double(value) }
        return nil
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        return nil
    }
}

struct LongRecordingAudioMetadata: Equatable {
    let fileSize: Int
    let durationSeconds: Double
}

enum LongRecordingAudioValidationError: Error, Equatable {
    case tooLarge
    case tooLong
    case unsupportedFormat
    case unreadable

    var message: String {
        switch self {
        case .tooLarge:
            return "录音文件超过 300 MB，无法转写"
        case .tooLong:
            return "录音时长超过 2 小时，无法转写"
        case .unsupportedFormat:
            return "录音格式不受支持，需要 16kHz、16-bit、单声道 PCM WAV"
        case .unreadable:
            return "无法读取录音文件"
        }
    }
}

enum LongRecordingAudioValidator {
    static let maxAudioBytes = 300_000_000
    static let maxDurationSeconds: Double = 7200

    static func validate(fileURL: URL) throws -> LongRecordingAudioMetadata {
        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        } catch {
            throw LongRecordingAudioValidationError.unreadable
        }
        guard let size = attributes[.size] as? NSNumber else {
            throw LongRecordingAudioValidationError.unreadable
        }
        guard size.intValue <= maxAudioBytes else {
            throw LongRecordingAudioValidationError.tooLarge
        }
        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: fileURL)
        } catch {
            throw LongRecordingAudioValidationError.unreadable
        }
        defer { try? handle.close() }
        let header: Data
        do {
            header = try handle.read(upToCount: 1024 * 1024) ?? Data()
        } catch {
            throw LongRecordingAudioValidationError.unreadable
        }
        return try validate(fileSize: size.intValue, wavHeader: header)
    }

    static func validate(fileSize: Int, wavHeader: Data) throws -> LongRecordingAudioMetadata {
        guard fileSize > 0 else { throw LongRecordingAudioValidationError.unreadable }
        guard fileSize <= maxAudioBytes else { throw LongRecordingAudioValidationError.tooLarge }
        guard wavHeader.count >= 44,
              String(data: wavHeader.subdata(in: 0..<4), encoding: .ascii) == "RIFF",
              String(data: wavHeader.subdata(in: 8..<12), encoding: .ascii) == "WAVE" else {
            throw LongRecordingAudioValidationError.unsupportedFormat
        }

        var offset = 12
        var audioFormat: UInt16?
        var channels: UInt16?
        var sampleRate: UInt32?
        var bitsPerSample: UInt16?
        var dataSize: UInt32?
        var dataOffset: Int?
        while offset + 8 <= wavHeader.count {
            let chunkId = String(data: wavHeader.subdata(in: offset..<(offset + 4)), encoding: .ascii)
            let chunkSize = Int(readUInt32LE(wavHeader, offset + 4))
            let chunkStart = offset + 8
            if chunkId == "fmt ", chunkSize >= 16, chunkStart + 16 <= wavHeader.count {
                audioFormat = readUInt16LE(wavHeader, chunkStart)
                channels = readUInt16LE(wavHeader, chunkStart + 2)
                sampleRate = readUInt32LE(wavHeader, chunkStart + 4)
                bitsPerSample = readUInt16LE(wavHeader, chunkStart + 14)
            } else if chunkId == "data" {
                dataSize = UInt32(chunkSize)
                dataOffset = chunkStart
                break
            }
            offset = chunkStart + chunkSize + (chunkSize % 2)
        }
        guard audioFormat == 1,
              channels == 1,
              sampleRate == 16000,
              bitsPerSample == 16,
              let dataSize,
              dataSize > 0,
              let dataOffset,
              Int(dataSize) <= fileSize - dataOffset else {
            throw LongRecordingAudioValidationError.unsupportedFormat
        }
        let bytesPerSecond = Double(sampleRate!) * Double(channels!) * (Double(bitsPerSample!) / 8)
        let duration = Double(dataSize) / bytesPerSecond
        guard duration <= maxDurationSeconds else { throw LongRecordingAudioValidationError.tooLong }
        return LongRecordingAudioMetadata(fileSize: fileSize, durationSeconds: duration)
    }

    private static func readUInt16LE(_ data: Data, _ offset: Int) -> UInt16 {
        UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private static func readUInt32LE(_ data: Data, _ offset: Int) -> UInt32 {
        UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
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
