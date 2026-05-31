import Foundation

struct AgentTaskItem: Identifiable, Codable, Equatable {
    var id: String { taskId }

    var taskId: String
    var backendId: String
    var title: String
    var prompt: String
    var schedule: String
    var scheduleDisplay: String?
    var enabled: Bool
    var state: String
    var nextRunAt: String?
    var lastRunAt: String?
    var lastStatus: String?
    var lastError: String?
    var source: String
    var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case taskId = "task_id"
        case backendId = "backend_id"
        case title
        case prompt
        case schedule
        case scheduleDisplay = "schedule_display"
        case enabled
        case state
        case nextRunAt = "next_run_at"
        case lastRunAt = "last_run_at"
        case lastStatus = "last_status"
        case lastError = "last_error"
        case source
        case updatedAt = "updated_at"
    }

    init(
        taskId: String,
        backendId: String,
        title: String,
        prompt: String,
        schedule: String,
        scheduleDisplay: String? = nil,
        enabled: Bool,
        state: String,
        nextRunAt: String? = nil,
        lastRunAt: String? = nil,
        lastStatus: String? = nil,
        lastError: String? = nil,
        source: String,
        updatedAt: String? = nil
    ) {
        self.taskId = taskId
        self.backendId = backendId
        self.title = title
        self.prompt = prompt
        self.schedule = schedule
        self.scheduleDisplay = scheduleDisplay
        self.enabled = enabled
        self.state = state
        self.nextRunAt = nextRunAt
        self.lastRunAt = lastRunAt
        self.lastStatus = lastStatus
        self.lastError = lastError
        self.source = source
        self.updatedAt = updatedAt
    }

    init?(json: [String: Any]) {
        guard let taskId = json["task_id"] as? String,
              let backendId = json["backend_id"] as? String else {
            return nil
        }
        self.init(
            taskId: taskId,
            backendId: backendId,
            title: json["title"] as? String ?? "未命名任务",
            prompt: json["prompt"] as? String ?? "",
            schedule: json["schedule"] as? String ?? "",
            scheduleDisplay: json["schedule_display"] as? String,
            enabled: json["enabled"] as? Bool ?? true,
            state: json["state"] as? String ?? "scheduled",
            nextRunAt: json["next_run_at"] as? String,
            lastRunAt: json["last_run_at"] as? String,
            lastStatus: json["last_status"] as? String,
            lastError: json["last_error"] as? String,
            source: json["source"] as? String ?? "backend",
            updatedAt: json["updated_at"] as? String
        )
    }
}

struct AgentApprovalHistoryPayload: Equatable {
    var approvalId: String
    var backendId: String
    var title: String
    var command: String
    var decision: String
    var createdAt: String
    var source: String

    init?(json: [String: Any]) {
        guard let approvalId = json["approval_id"] as? String,
              let backendId = json["backend_id"] as? String else {
            return nil
        }
        self.approvalId = approvalId
        self.backendId = backendId
        self.title = json["title"] as? String ?? "审批记录"
        self.command = json["command"] as? String ?? ""
        self.decision = json["decision"] as? String ?? "unknown"
        self.createdAt = json["created_at"] as? String ?? ""
        self.source = json["source"] as? String ?? "backend"
    }
}

struct TaskListResponsePayload: Equatable {
    var requestId: String
    var backendId: String
    var tasks: [AgentTaskItem]
    var capability: String?
    var error: String?

    init(json: [String: Any]) {
        requestId = json["request_id"] as? String ?? ""
        backendId = json["backend_id"] as? String ?? ""
        tasks = (json["tasks"] as? [[String: Any]] ?? []).compactMap(AgentTaskItem.init(json:))
        capability = json["capability"] as? String
        error = json["error"] as? String
    }
}

struct TaskMutationResponsePayload: Equatable {
    var requestId: String
    var backendId: String
    var task: AgentTaskItem?
    var taskId: String?
    var deleted: Bool
    var accepted: Bool
    var requiresAgentConfirmation: Bool
    var message: String?
    var error: String?

    init(json: [String: Any]) {
        requestId = json["request_id"] as? String ?? ""
        backendId = json["backend_id"] as? String ?? ""
        task = (json["task"] as? [String: Any]).flatMap(AgentTaskItem.init(json:))
        taskId = json["task_id"] as? String
        deleted = json["deleted"] as? Bool ?? false
        accepted = json["accepted"] as? Bool ?? false
        requiresAgentConfirmation = json["requires_agent_confirmation"] as? Bool ?? false
        message = json["message"] as? String
        error = json["error"] as? String
    }
}

struct ApprovalHistoryResponsePayload: Equatable {
    var requestId: String
    var backendId: String
    var approvals: [AgentApprovalHistoryPayload]
    var error: String?

    init(json: [String: Any]) {
        requestId = json["request_id"] as? String ?? ""
        backendId = json["backend_id"] as? String ?? ""
        approvals = (json["approvals"] as? [[String: Any]] ?? []).compactMap(AgentApprovalHistoryPayload.init(json:))
        error = json["error"] as? String
    }
}

struct ASRResultEventPayload: Equatable {
    var clientMessageId: String
    var success: Bool
    var text: String?
    var error: String?

    init?(json: [String: Any]) {
        guard let clientMessageId = json["client_message_id"] as? String else { return nil }
        self.clientMessageId = clientMessageId
        self.success = json["success"] as? Bool ?? false
        self.text = json["text"] as? String
        self.error = json["error"] as? String
    }
}

struct RecordingEventPayload: Equatable {
    var recordingId: String?
    var clientMessageId: String?
    var event: RecordingEventItem
    var artifact: RecordingArtifactPayload?
    var jobId: String?
    var percent: Double?
    var completedSegments: Int?
    var totalSegments: Int?

    init?(json: [String: Any]) {
        let title = (json["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let content = (json["content"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !title.isEmpty || !content.isEmpty else { return nil }

        recordingId = json["recording_id"] as? String
        clientMessageId = json["client_message_id"] as? String
        let eventId = (json["event_id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let kind = RecordingEventKind(protocolValue: json["kind"] as? String ?? "")
        let status = RecordingEventStatus(protocolValue: json["status"] as? String)
        let timestamp = (json["timestamp"] as? String)
            .flatMap { HistoryMessagePayload.date(from: $0) } ?? Date()
        event = RecordingEventItem(
            id: eventId?.isEmpty == false ? eventId! : UUID().uuidString,
            kind: kind,
            title: title.isEmpty ? kind.label : title,
            content: content,
            status: status,
            createdAt: timestamp
        )
        if let data = json["data"] as? [String: Any] {
            jobId = data["job_id"] as? String
            percent = Self.doubleValue(data["percent"])
            completedSegments = Self.intValue(data["completed_segments"])
            totalSegments = Self.intValue(data["total_segments"])
            if let artifactJson = data["artifact"] as? [String: Any] {
                artifact = RecordingArtifactPayload(json: artifactJson)
            }
        }
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
        if let value = value as? String { return Int(value) }
        return nil
    }
}

struct RecordingArtifactPayload: Equatable {
    var filename: String
    var mimeType: String
    var encoding: String
    var content: String
    var backendPath: String?

    init?(json: [String: Any]) {
        let filename = (json["filename"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let content = json["content"] as? String ?? ""
        guard !filename.isEmpty else { return nil }
        self.filename = filename
        self.mimeType = (json["mime_type"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "text/plain"
        self.encoding = (json["encoding"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "utf8"
        self.content = content
        self.backendPath = (json["backend_path"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
