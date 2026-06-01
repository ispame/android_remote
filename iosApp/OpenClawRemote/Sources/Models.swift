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
    var uploadProgress: Double
    var asrProgress: Double
    var error: String?

    init?(json: [String: Any]) {
        guard let jobId = json["job_id"] as? String else { return nil }
        self.jobId = jobId
        recordingId = json["recording_id"] as? String
        clientMessageId = json["client_message_id"] as? String
        status = json["status"] as? String ?? ""
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
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? String { return Double(value) }
        return nil
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
