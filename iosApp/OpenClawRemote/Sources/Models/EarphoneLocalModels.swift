import Foundation

enum CronExpressionValidator {
    private struct FieldRule {
        let range: ClosedRange<Int>
    }

    private static let rules = [
        FieldRule(range: 0...59),
        FieldRule(range: 0...23),
        FieldRule(range: 1...31),
        FieldRule(range: 1...12),
        FieldRule(range: 0...7)
    ]

    static func isValid(_ expression: String) -> Bool {
        let fields = expression
            .split(separator: " ")
            .map(String.init)
        guard fields.count == rules.count else { return false }
        return zip(fields, rules).allSatisfy { field, rule in
            isValidField(field, range: rule.range)
        }
    }

    private static func isValidField(_ field: String, range: ClosedRange<Int>) -> Bool {
        guard !field.isEmpty else { return false }
        return field.split(separator: ",").allSatisfy { part in
            isValidPart(String(part), range: range)
        }
    }

    private static func isValidPart(_ part: String, range: ClosedRange<Int>) -> Bool {
        if part == "*" { return true }
        if part.hasPrefix("*/") {
            guard let step = Int(part.dropFirst(2)) else { return false }
            return step > 0 && step <= range.upperBound
        }
        if part.contains("-") {
            let bounds = part.split(separator: "-").compactMap { Int($0) }
            guard bounds.count == 2 else { return false }
            return range.contains(bounds[0]) && range.contains(bounds[1]) && bounds[0] <= bounds[1]
        }
        guard let value = Int(part) else { return false }
        return range.contains(value)
    }
}

struct ApprovalHistoryItem: Identifiable, Codable, Equatable {
    var id: String
    var agentId: String
    var title: String
    var command: String
    var decision: String
    var createdAt: Date
}

struct ScheduledTask: Identifiable, Codable, Equatable {
    var id: String
    var agentId: String
    var title: String
    var prompt: String
    var cronExpression: String
    var isEnabled: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String = UUID().uuidString,
        agentId: String,
        title: String,
        prompt: String,
        cronExpression: String = "0 9 * * 1-5",
        isEnabled: Bool = true,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.agentId = agentId
        self.title = title
        self.prompt = prompt
        self.cronExpression = cronExpression
        self.isEnabled = isEnabled
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

enum RecordingInputSource: String, Codable, CaseIterable {
    case phone
    case headset

    var label: String {
        switch self {
        case .phone: return "手机麦克风"
        case .headset: return "耳机录音"
        }
    }
}

enum RecordingEventKind: String, Codable {
    case created
    case asr
    case delivered
    case agentReply = "agent_reply"
    case subtask
    case scheduledTask = "scheduled_task"
    case reminder
    case artifact
    case status
    case error
    case other

    init(protocolValue: String) {
        self = RecordingEventKind(rawValue: protocolValue) ?? .other
    }

    var label: String {
        switch self {
        case .created: return "录音"
        case .asr: return "ASR"
        case .delivered: return "投递"
        case .agentReply: return "回复"
        case .subtask: return "子任务"
        case .scheduledTask: return "定时任务"
        case .reminder: return "提醒"
        case .artifact: return "文件"
        case .status: return "状态"
        case .error: return "错误"
        case .other: return "过程"
        }
    }

    var systemImage: String {
        switch self {
        case .created: return "waveform"
        case .asr: return "text.bubble"
        case .delivered: return "paperplane"
        case .agentReply: return "bubble.left.and.bubble.right"
        case .subtask: return "checklist"
        case .scheduledTask: return "calendar.badge.clock"
        case .reminder: return "bell"
        case .artifact: return "doc.richtext"
        case .status: return "info.circle"
        case .error: return "exclamationmark.triangle"
        case .other: return "circle.dashed"
        }
    }
}

enum RecordingEventStatus: String, Codable {
    case pending
    case running
    case completed
    case failed
    case cancelled

    init(protocolValue: String?) {
        guard let protocolValue else {
            self = .completed
            return
        }
        self = RecordingEventStatus(rawValue: protocolValue) ?? .completed
    }
}

struct RecordingEventItem: Identifiable, Codable, Equatable {
    var id: String
    var kind: RecordingEventKind
    var title: String
    var content: String
    var status: RecordingEventStatus
    var createdAt: Date

    init(
        id: String = UUID().uuidString,
        kind: RecordingEventKind,
        title: String,
        content: String,
        status: RecordingEventStatus = .completed,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.content = content
        self.status = status
        self.createdAt = createdAt
    }
}

struct RecordingArtifactItem: Identifiable, Codable, Equatable {
    var id: String
    var filename: String
    var mimeType: String
    var fileURL: URL
    var backendPath: String?
    var sourceEventId: String?
    var createdAt: Date

    init(
        id: String = UUID().uuidString,
        filename: String,
        mimeType: String,
        fileURL: URL,
        backendPath: String? = nil,
        sourceEventId: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.filename = filename
        self.mimeType = mimeType
        self.fileURL = fileURL
        self.backendPath = backendPath
        self.sourceEventId = sourceEventId
        self.createdAt = createdAt
    }
}

struct RecordingReminderItem: Identifiable, Codable, Equatable {
    var id: String
    var title: String
    var notes: String
    var dueAt: Date
    var isCompleted: Bool
    var notificationId: String
    var createdAt: Date

    init(
        id: String = UUID().uuidString,
        title: String,
        notes: String = "",
        dueAt: Date,
        isCompleted: Bool = false,
        notificationId: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.dueAt = dueAt
        self.isCompleted = isCompleted
        self.notificationId = notificationId ?? "recording-reminder-\(id)"
        self.createdAt = createdAt
    }
}

struct RecordingItem: Identifiable, Codable, Equatable {
    var id: String
    var agentId: String
    var createdAt: Date
    var duration: TimeInterval
    var asrText: String
    var prompt: String
    var recordingType: RecordingType
    var processingStatus: RecordingProcessingStatus
    var selectedPrompt: String
    var fileURL: URL
    var source: RecordingInputSource
    var clientMessageId: String?
    var asrJobId: String?
    var uploadProgress: Double
    var asrProgress: Double
    var asrError: String?
    var events: [RecordingEventItem]
    var reminders: [RecordingReminderItem]
    var artifacts: [RecordingArtifactItem]

    init(
        id: String,
        agentId: String,
        createdAt: Date,
        duration: TimeInterval,
        asrText: String,
        prompt: String = "",
        recordingType: RecordingType = .audioOnly,
        processingStatus: RecordingProcessingStatus = .savedOnly,
        selectedPrompt: String? = nil,
        fileURL: URL,
        source: RecordingInputSource,
        clientMessageId: String? = nil,
        asrJobId: String? = nil,
        uploadProgress: Double = 0,
        asrProgress: Double = 0,
        asrError: String? = nil,
        events: [RecordingEventItem] = [],
        reminders: [RecordingReminderItem] = [],
        artifacts: [RecordingArtifactItem] = []
    ) {
        self.id = id
        self.agentId = agentId
        self.createdAt = createdAt
        self.duration = duration
        self.asrText = asrText
        self.prompt = prompt
        self.recordingType = recordingType
        self.processingStatus = processingStatus
        self.selectedPrompt = selectedPrompt ?? prompt
        self.fileURL = fileURL
        self.source = source
        self.clientMessageId = clientMessageId
        self.asrJobId = asrJobId
        self.uploadProgress = uploadProgress
        self.asrProgress = asrProgress
        self.asrError = asrError
        self.events = events
        self.reminders = reminders
        self.artifacts = artifacts
    }

    enum CodingKeys: String, CodingKey {
        case id
        case agentId
        case createdAt
        case duration
        case asrText
        case prompt
        case recordingType
        case processingStatus
        case selectedPrompt
        case fileURL
        case source
        case clientMessageId
        case asrJobId
        case uploadProgress
        case asrProgress
        case asrError
        case events
        case reminders
        case artifacts
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        agentId = try container.decode(String.self, forKey: .agentId)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        duration = try container.decode(TimeInterval.self, forKey: .duration)
        asrText = try container.decode(String.self, forKey: .asrText)
        prompt = try container.decodeIfPresent(String.self, forKey: .prompt) ?? ""
        recordingType = try container.decodeIfPresent(RecordingType.self, forKey: .recordingType) ?? .audioOnly
        if let savedStatus = try container.decodeIfPresent(RecordingProcessingStatus.self, forKey: .processingStatus) {
            processingStatus = savedStatus
        } else if !asrText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            processingStatus = .completed
        } else {
            processingStatus = .savedOnly
        }
        selectedPrompt = try container.decodeIfPresent(String.self, forKey: .selectedPrompt) ?? prompt
        fileURL = try container.decode(URL.self, forKey: .fileURL)
        source = try container.decode(RecordingInputSource.self, forKey: .source)
        clientMessageId = try container.decodeIfPresent(String.self, forKey: .clientMessageId)
        asrJobId = try container.decodeIfPresent(String.self, forKey: .asrJobId)
        uploadProgress = try container.decodeIfPresent(Double.self, forKey: .uploadProgress) ?? 0
        asrProgress = try container.decodeIfPresent(Double.self, forKey: .asrProgress) ?? 0
        asrError = try container.decodeIfPresent(String.self, forKey: .asrError)
        events = try container.decodeIfPresent([RecordingEventItem].self, forKey: .events) ?? []
        reminders = try container.decodeIfPresent([RecordingReminderItem].self, forKey: .reminders) ?? []
        artifacts = try container.decodeIfPresent([RecordingArtifactItem].self, forKey: .artifacts) ?? []
    }
}

struct HeadsetDevice: Identifiable, Codable, Equatable {
    var id: String
    var name: String
    var isPaired: Bool
    var leftBattery: Int
    var rightBattery: Int
}

struct EQBand: Identifiable, Codable, Equatable {
    var id: String
    var frequency: String
    var gain: Double
}

struct EQPreset: Identifiable, Codable, Equatable {
    var id: String
    var name: String
    var bands: [EQBand]
}

enum HeadsetSideSelection: String, Codable, CaseIterable, Identifiable {
    case left
    case right

    var id: String { rawValue }

    var label: String {
        switch self {
        case .left: return "左耳"
        case .right: return "右耳"
        }
    }
}

enum HeadsetGestureSelection: String, Codable, CaseIterable, Identifiable {
    case singleTap
    case doubleTap
    case tripleTap
    case longPress

    var id: String { rawValue }

    var label: String {
        switch self {
        case .singleTap: return "单击"
        case .doubleTap: return "双击"
        case .tripleTap: return "三击"
        case .longPress: return "长按"
        }
    }
}

struct HeadsetShortcut: Identifiable, Codable, Equatable {
    var id: String
    var side: HeadsetSideSelection
    var gesture: HeadsetGestureSelection
    var action: String
}

struct HeadsetLocalSettings: Codable, Equatable {
    var devices: [HeadsetDevice]
    var selectedDeviceId: String
    var selectedEQPresetId: String
    var eqPresets: [EQPreset]
    var shortcuts: [HeadsetShortcut]
    var currentFirmwareVersion: String
    var latestFirmwareVersion: String

    static let defaultValue = HeadsetLocalSettings(
        devices: [
            HeadsetDevice(
                id: "a9-ultra-demo",
                name: "A9 Ultra",
                isPaired: true,
                leftBattery: 100,
                rightBattery: 100
            )
        ],
        selectedDeviceId: "a9-ultra-demo",
        selectedEQPresetId: "pop",
        eqPresets: [
            EQPreset.defaultPreset(id: "blues", name: "蓝调", gains: [2, 1, 0, 2, 3]),
            EQPreset.defaultPreset(id: "classical", name: "古典", gains: [0, 1, 2, 1, 0]),
            EQPreset.defaultPreset(id: "jazz", name: "爵士", gains: [2, 1, 2, 1, 2]),
            EQPreset.defaultPreset(id: "hiphop", name: "嘻哈", gains: [4, 2, 0, 2, 4]),
            EQPreset.defaultPreset(id: "pop", name: "流行", gains: [1, 2, 2, 2, 1])
        ],
        shortcuts: HeadsetShortcut.defaultShortcuts,
        currentFirmwareVersion: "1.0.0",
        latestFirmwareVersion: "1.0.3"
    )

    mutating func addDemoDevice() {
        let nextNumber = devices.count + 1
        let id = "demo-\(nextNumber)"
        devices.append(
            HeadsetDevice(
                id: id,
                name: "A9 Ultra \(nextNumber)",
                isPaired: false,
                leftBattery: 100,
                rightBattery: 100
            )
        )
        selectedDeviceId = id
    }
}

extension EQPreset {
    static func defaultPreset(id: String, name: String, gains: [Double]) -> EQPreset {
        let frequencies = ["60Hz", "250Hz", "1kHz", "4kHz", "8kHz"]
        return EQPreset(
            id: id,
            name: name,
            bands: zip(frequencies, gains).map { frequency, gain in
                EQBand(id: "\(id)-\(frequency)", frequency: frequency, gain: gain)
            }
        )
    }
}

extension HeadsetShortcut {
    static let actionOptions = ["播放/暂停", "上一首", "下一首", "唤醒 Agent", "同声传译", "英语口语练习", "无操作"]

    static let defaultShortcuts: [HeadsetShortcut] = HeadsetSideSelection.allCases.flatMap { side in
        HeadsetGestureSelection.allCases.map { gesture in
            HeadsetShortcut(
                id: "\(side.rawValue)-\(gesture.rawValue)",
                side: side,
                gesture: gesture,
                action: defaultAction(for: gesture)
            )
        }
    }

    private static func defaultAction(for gesture: HeadsetGestureSelection) -> String {
        switch gesture {
        case .singleTap: return "播放/暂停"
        case .doubleTap: return "下一首"
        case .tripleTap: return "上一首"
        case .longPress: return "唤醒 Agent"
        }
    }
}
