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
    var metadata: [String: String]

    enum CodingKeys: String, CodingKey {
        case id
        case kind
        case title
        case content
        case status
        case createdAt
        case metadata
    }

    init(
        id: String = UUID().uuidString,
        kind: RecordingEventKind,
        title: String,
        content: String,
        status: RecordingEventStatus = .completed,
        createdAt: Date = Date(),
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.content = content
        self.status = status
        self.createdAt = createdAt
        self.metadata = metadata
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        kind = try container.decode(RecordingEventKind.self, forKey: .kind)
        title = try container.decode(String.self, forKey: .title)
        content = try container.decode(String.self, forKey: .content)
        status = try container.decode(RecordingEventStatus.self, forKey: .status)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        metadata = try container.decodeIfPresent([String: String].self, forKey: .metadata) ?? [:]
    }
}

struct RecordingArtifactItem: Identifiable, Codable, Equatable {
    var id: String
    var filename: String
    var mimeType: String
    var fileURL: URL
    var backendPath: String?
    var sourceEventId: String?
    var relatedTaskId: String?
    var createdAt: Date

    init(
        id: String = UUID().uuidString,
        filename: String,
        mimeType: String,
        fileURL: URL,
        backendPath: String? = nil,
        sourceEventId: String? = nil,
        relatedTaskId: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.filename = filename
        self.mimeType = mimeType
        self.fileURL = fileURL
        self.backendPath = backendPath
        self.sourceEventId = sourceEventId
        self.relatedTaskId = relatedTaskId
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

enum RecordingWorkflowStatus: String, Codable {
    case planning
    case running
    case paused
    case waitingApproval = "waiting_approval"
    case succeeded
    case partial
    case failed
    case cancelled

    var label: String {
        switch self {
        case .planning: return "规划中"
        case .running: return "执行中"
        case .paused: return "已暂停"
        case .waitingApproval: return "等待审批"
        case .succeeded: return "已完成"
        case .partial: return "部分完成"
        case .failed: return "失败"
        case .cancelled: return "已取消"
        }
    }

    var isTerminal: Bool {
        [.succeeded, .partial, .failed, .cancelled].contains(self)
    }
}

enum RecordingExecutionTaskStatus: String, Codable {
    case planned
    case queued
    case running
    case paused
    case waitingApproval = "waiting_approval"
    case succeeded
    case degraded
    case failed
    case blocked
    case cancelled

    var label: String {
        switch self {
        case .planned: return "已规划"
        case .queued: return "排队中"
        case .running: return "执行中"
        case .paused: return "已暂停"
        case .waitingApproval: return "等待审批"
        case .succeeded: return "已完成"
        case .degraded: return "降级完成"
        case .failed: return "失败"
        case .blocked: return "已阻塞"
        case .cancelled: return "已取消"
        }
    }

    var isTerminal: Bool {
        [.succeeded, .degraded, .failed, .blocked, .cancelled].contains(self)
    }

    var isDelivered: Bool {
        self == .succeeded || self == .degraded
    }
}

struct RecordingTaskEvidence: Codable, Equatable, Identifiable {
    var type: String
    var description: String
    var path: String?
    var sha256: String?
    var exitCode: Int?
    var passed: Bool?
    var receiptId: String?
    var url: String?
    var toolReceiptId: String?
    var verified: Bool?

    var id: String {
        [type, description, path ?? "", url ?? "", sha256 ?? "", receiptId ?? "", toolReceiptId ?? ""]
            .joined(separator: "|")
    }

    init?(json: [String: Any]) {
        guard let type = json["type"] as? String,
              let description = json["description"] as? String else { return nil }
        self.type = type
        self.description = description
        path = json["path"] as? String
        sha256 = json["sha256"] as? String
        exitCode = (json["exit_code"] as? NSNumber)?.intValue
        passed = json["passed"] as? Bool
        receiptId = json["receipt_id"] as? String
        url = json["url"] as? String
        toolReceiptId = json["tool_receipt_id"] as? String
        verified = json["verified"] as? Bool
    }
}

struct RecordingArtifactReference: Codable, Equatable, Identifiable {
    var artifactId: String?
    var filename: String
    var mimeType: String?
    var backendPath: String?
    var sha256: String?
    var sizeBytes: Int?
    var retrievalRef: String?
    var downloadUrl: String?
    var expiresAt: Date?
    var content: String?

    var id: String { artifactId ?? [filename, backendPath ?? "", sha256 ?? ""].joined(separator: "|") }

    init?(json: [String: Any]) {
        guard let filename = json["filename"] as? String else { return nil }
        artifactId = json["artifact_id"] as? String
        self.filename = filename
        mimeType = json["mime_type"] as? String
        backendPath = json["backend_path"] as? String
        sha256 = json["sha256"] as? String
        sizeBytes = (json["size_bytes"] as? NSNumber)?.intValue
        retrievalRef = json["retrieval_ref"] as? String
        downloadUrl = json["download_url"] as? String
        expiresAt = Self.date(json["expires_at"])
        content = json["content"] as? String
    }

    private static func date(_ value: Any?) -> Date? {
        guard let text = value as? String else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }
}

struct RecordingExecutionTaskSnapshot: Codable, Equatable, Identifiable {
    var taskId: String
    var workflowId: String
    var systemKind: String?
    var title: String
    var prompt: String
    var dependsOn: [String]
    var completionCriteria: [String]
    var risk: String
    var riskReason: String?
    var replaySafety: String
    var criticality: String?
    var dependencyPolicy: String?
    var failurePolicy: String?
    var deadlineAt: Date?
    var status: RecordingExecutionTaskStatus
    var attempt: Int
    var maxAttempts: Int
    var leaseExpiresAt: Date?
    var executorRef: String?
    var executorHint: String?
    var modelHint: String?
    var sourceConstraints: [String]?
    var resultSummary: String?
    var lastError: String?
    var confidence: Double?
    var warnings: [String]?
    var blockingTaskIds: [String]?
    var availableActions: [String]?
    var rawOutputRef: String?
    var evidence: [RecordingTaskEvidence]
    var artifacts: [RecordingArtifactReference]
    var createdAt: Date
    var updatedAt: Date

    var id: String { taskId }

    init?(json: [String: Any]) {
        guard let taskId = json["task_id"] as? String,
              let workflowId = json["workflow_id"] as? String,
              let title = json["title"] as? String,
              let prompt = json["prompt"] as? String,
              let statusValue = json["status"] as? String,
              let status = RecordingExecutionTaskStatus(rawValue: statusValue) else { return nil }
        self.taskId = taskId
        self.workflowId = workflowId
        systemKind = json["system_kind"] as? String
        self.title = title
        self.prompt = prompt
        dependsOn = json["depends_on"] as? [String] ?? []
        completionCriteria = json["completion_criteria"] as? [String] ?? []
        risk = json["risk"] as? String ?? "normal"
        riskReason = json["risk_reason"] as? String
        replaySafety = json["replay_safety"] as? String ?? "safe"
        criticality = json["criticality"] as? String
        dependencyPolicy = json["dependency_policy"] as? String
        failurePolicy = json["failure_policy"] as? String
        deadlineAt = Self.date(json["deadline_at"])
        self.status = status
        attempt = (json["attempt"] as? NSNumber)?.intValue ?? 0
        maxAttempts = (json["max_attempts"] as? NSNumber)?.intValue ?? 3
        leaseExpiresAt = Self.date(json["lease_expires_at"])
        executorRef = json["executor_ref"] as? String
        executorHint = json["executor_hint"] as? String
        modelHint = json["model_hint"] as? String
        sourceConstraints = json["source_constraints"] as? [String]
        resultSummary = json["result_summary"] as? String
        lastError = json["last_error"] as? String
        confidence = (json["confidence"] as? NSNumber)?.doubleValue
        warnings = json["warnings"] as? [String]
        blockingTaskIds = json["blocking_task_ids"] as? [String]
        availableActions = json["available_actions"] as? [String]
        rawOutputRef = json["raw_output_ref"] as? String
        evidence = (json["evidence"] as? [[String: Any]] ?? []).compactMap(RecordingTaskEvidence.init)
        artifacts = (json["artifacts"] as? [[String: Any]] ?? []).compactMap(RecordingArtifactReference.init)
        createdAt = Self.date(json["created_at"]) ?? Date()
        updatedAt = Self.date(json["updated_at"]) ?? createdAt
    }

    private static func date(_ value: Any?) -> Date? {
        guard let text = value as? String else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }
}

struct RecordingWorkflowSnapshot: Codable, Equatable, Identifiable {
    var workflowId: String
    var accountId: String
    var backendId: String
    var recordingId: String
    var title: String
    var status: RecordingWorkflowStatus
    var summary: String?
    var revision: Int?
    var deadlineAt: Date?
    var qualityState: String?
    var warnings: [String]?
    var finalArtifact: RecordingArtifactReference?
    var createdAt: Date
    var updatedAt: Date
    var tasks: [RecordingExecutionTaskSnapshot]

    var id: String { workflowId }
    var effectiveRevision: Int { revision ?? 1 }
    var businessTasks: [RecordingExecutionTaskSnapshot] { tasks.filter { $0.systemKind != "summary" } }
    var businessTaskCount: Int { businessTasks.count }
    var successfulTaskCount: Int { businessTasks.filter { $0.status == .succeeded }.count }
    var degradedTaskCount: Int { businessTasks.filter { $0.status == .degraded }.count }
    var failedTaskCount: Int { businessTasks.filter { $0.status == .failed }.count }
    var blockedTaskCount: Int { businessTasks.filter { $0.status == .blocked }.count }
    var cancelledTaskCount: Int { businessTasks.filter { $0.status == .cancelled }.count }
    var completedTaskCount: Int { businessTasks.filter(\.status.isDelivered).count }
    var progress: Double {
        guard businessTaskCount > 0 else { return status.isTerminal ? 1 : 0 }
        return Double(completedTaskCount) / Double(businessTaskCount)
    }

    init?(json: [String: Any]) {
        guard let workflowId = json["workflow_id"] as? String,
              let accountId = json["account_id"] as? String,
              let backendId = json["backend_id"] as? String,
              let recordingId = json["recording_id"] as? String,
              let title = json["title"] as? String,
              let statusValue = json["status"] as? String,
              let status = RecordingWorkflowStatus(rawValue: statusValue) else { return nil }
        self.workflowId = workflowId
        self.accountId = accountId
        self.backendId = backendId
        self.recordingId = recordingId
        self.title = title
        self.status = status
        summary = json["summary"] as? String
        revision = (json["revision"] as? NSNumber)?.intValue
        deadlineAt = Self.date(json["deadline_at"])
        qualityState = json["quality_state"] as? String
        warnings = json["warnings"] as? [String]
        finalArtifact = (json["final_artifact"] as? [String: Any]).flatMap(RecordingArtifactReference.init)
        createdAt = Self.date(json["created_at"]) ?? Date()
        updatedAt = Self.date(json["updated_at"]) ?? createdAt
        tasks = (json["tasks"] as? [[String: Any]] ?? []).compactMap(RecordingExecutionTaskSnapshot.init)
    }

    private static func date(_ value: Any?) -> Date? {
        guard let text = value as? String else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text) ?? ISO8601DateFormatter().date(from: text)
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
    var agentDeliveryStatus: RecordingAgentDeliveryStatus?
    var agentDeliveryAttempts: Int
    var agentDeliveryError: String?
    var agentDeliveryRetryable: Bool
    var agentDeliveredAt: String?
    var events: [RecordingEventItem]
    var reminders: [RecordingReminderItem]
    var artifacts: [RecordingArtifactItem]
    var workflow: RecordingWorkflowSnapshot?

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
        agentDeliveryStatus: RecordingAgentDeliveryStatus? = nil,
        agentDeliveryAttempts: Int = 0,
        agentDeliveryError: String? = nil,
        agentDeliveryRetryable: Bool = false,
        agentDeliveredAt: String? = nil,
        events: [RecordingEventItem] = [],
        reminders: [RecordingReminderItem] = [],
        artifacts: [RecordingArtifactItem] = [],
        workflow: RecordingWorkflowSnapshot? = nil
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
        self.agentDeliveryStatus = agentDeliveryStatus
        self.agentDeliveryAttempts = agentDeliveryAttempts
        self.agentDeliveryError = agentDeliveryError
        self.agentDeliveryRetryable = agentDeliveryRetryable
        self.agentDeliveredAt = agentDeliveredAt
        self.events = events
        self.reminders = reminders
        self.artifacts = artifacts
        self.workflow = workflow
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
        case agentDeliveryStatus
        case agentDeliveryAttempts
        case agentDeliveryError
        case agentDeliveryRetryable
        case agentDeliveredAt
        case events
        case reminders
        case artifacts
        case workflow
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
        agentDeliveryStatus = try container.decodeIfPresent(RecordingAgentDeliveryStatus.self, forKey: .agentDeliveryStatus)
        agentDeliveryAttempts = try container.decodeIfPresent(Int.self, forKey: .agentDeliveryAttempts) ?? 0
        agentDeliveryError = try container.decodeIfPresent(String.self, forKey: .agentDeliveryError)
        agentDeliveryRetryable = try container.decodeIfPresent(Bool.self, forKey: .agentDeliveryRetryable) ?? false
        agentDeliveredAt = try container.decodeIfPresent(String.self, forKey: .agentDeliveredAt)
        events = try container.decodeIfPresent([RecordingEventItem].self, forKey: .events) ?? []
        reminders = try container.decodeIfPresent([RecordingReminderItem].self, forKey: .reminders) ?? []
        artifacts = try container.decodeIfPresent([RecordingArtifactItem].self, forKey: .artifacts) ?? []
        workflow = try container.decodeIfPresent(RecordingWorkflowSnapshot.self, forKey: .workflow)
    }
}

enum RecordingAgentDeliveryStatus: String, Codable, Equatable {
    case notRequired = "not_required"
    case pending
    case delivering
    case delivered
    case failed

    var label: String {
        switch self {
        case .notRequired: return "无需发送"
        case .pending: return "等待 Agent 上线"
        case .delivering: return "正在发送给 Agent"
        case .delivered: return "Agent 已接收"
        case .failed: return "发送失败"
        }
    }

    var canRetry: Bool {
        self == .pending || self == .failed
    }
}

struct RecordingAgentTaskGroup: Identifiable, Equatable {
    var id: String { taskId }

    var taskId: String
    var event: RecordingEventItem
    var artifacts: [RecordingArtifactItem]
}

struct RecordingDetailPresentation: Equatable {
    var latestAgentReply: RecordingEventItem?
    var agentTaskGroups: [RecordingAgentTaskGroup]
    var humanTodos: [RecordingEventItem]
    var scheduledEvents: [RecordingEventItem]
    var generalTimelineEvents: [RecordingEventItem]
    var unassignedArtifacts: [RecordingArtifactItem]

    init(recording: RecordingItem) {
        let events = recording.events.sorted { $0.createdAt < $1.createdAt }
        latestAgentReply = events.filter { $0.kind == .agentReply }.last
        humanTodos = events.filter(Self.isHumanTodo)
        scheduledEvents = events.filter { $0.kind == .scheduledTask }
        generalTimelineEvents = events.filter(Self.isGeneralTimelineEvent)

        let agentTasks = events.filter(Self.isAgentTask)
        let artifacts = recording.artifacts.sorted { $0.createdAt < $1.createdAt }
        var assignedArtifactIds = Set<String>()

        agentTaskGroups = agentTasks.map { event in
            let taskId = Self.taskId(for: event)
            let relatedArtifacts = artifacts.filter { artifact in
                guard artifact.relatedTaskId == taskId else { return false }
                assignedArtifactIds.insert(artifact.id)
                return true
            }
            return RecordingAgentTaskGroup(taskId: taskId, event: event, artifacts: relatedArtifacts)
        }

        let unassigned = artifacts.filter { !assignedArtifactIds.contains($0.id) }
        if agentTaskGroups.count == 1 {
            agentTaskGroups[0].artifacts.append(contentsOf: unassigned)
            unassignedArtifacts = []
        } else {
            unassignedArtifacts = unassigned
        }
    }

    private static func isGeneralTimelineEvent(_ event: RecordingEventItem) -> Bool {
        switch event.kind {
        case .subtask, .scheduledTask, .reminder, .artifact, .agentReply:
            return false
        case .created, .asr, .delivered, .status, .error, .other:
            return true
        }
    }

    private static func isAgentTask(_ event: RecordingEventItem) -> Bool {
        event.kind == .subtask && owner(for: event) != "user" && !needsUserInput(event)
    }

    private static func isHumanTodo(_ event: RecordingEventItem) -> Bool {
        event.kind == .subtask && (owner(for: event) == "user" || needsUserInput(event))
    }

    private static func taskId(for event: RecordingEventItem) -> String {
        let value = event.metadata["task_id"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == false ? value! : event.id
    }

    private static func owner(for event: RecordingEventItem) -> String {
        event.metadata["owner"]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    }

    private static func needsUserInput(_ event: RecordingEventItem) -> Bool {
        let rawValue = event.metadata["needs_user_input"]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return rawValue == "true" || rawValue == "1" || rawValue == "yes"
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
