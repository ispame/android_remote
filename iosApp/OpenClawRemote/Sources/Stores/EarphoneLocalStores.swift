import Foundation
import Combine

final class ScheduledTaskStore: ObservableObject {
    private let defaults: UserDefaults
    private let key = "earphone_scheduled_tasks_v1"

    @Published private(set) var tasks: [ScheduledTask]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        tasks = Self.loadTasks(from: defaults, key: key)
    }

    func tasks(for agentId: String) -> [ScheduledTask] {
        tasks
            .filter { $0.agentId == agentId }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func save(_ task: ScheduledTask) {
        var copy = task
        copy.updatedAt = Date()
        if let index = tasks.firstIndex(where: { $0.id == copy.id }) {
            tasks[index] = copy
        } else {
            tasks.append(copy)
        }
        persist()
    }

    func delete(id: String) {
        tasks.removeAll { $0.id == id }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(tasks) {
            defaults.set(data, forKey: key)
        }
    }

    private static func loadTasks(from defaults: UserDefaults, key: String) -> [ScheduledTask] {
        guard let data = defaults.data(forKey: key),
              let tasks = try? JSONDecoder().decode([ScheduledTask].self, from: data) else {
            return []
        }
        return tasks
    }
}

final class RecordingStore: ObservableObject {
    private let defaults: UserDefaults
    private let documentsDirectory: URL
    private let key = "earphone_recordings_v1"

    @Published private(set) var items: [RecordingItem]

    init(
        defaults: UserDefaults = .standard,
        documentsDirectory: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    ) {
        self.defaults = defaults
        self.documentsDirectory = documentsDirectory
        items = Self.loadItems(from: defaults, key: key)
    }

    func recordings(for agentId: String) -> [RecordingItem] {
        items
            .filter { $0.agentId == agentId }
            .sorted { $0.createdAt > $1.createdAt }
    }

    @discardableResult
    func createRecording(
        agentId: String,
        audioData: Data,
        asrText: String = "",
        prompt: String = "",
        recordingType: RecordingType = .audioOnly,
        processingStatus: RecordingProcessingStatus? = nil,
        selectedPrompt: String? = nil,
        source: RecordingInputSource = .phone,
        duration: TimeInterval = 0,
        clientMessageId: String? = nil
    ) throws -> RecordingItem {
        let id = UUID().uuidString
        let directory = documentsDirectory.appendingPathComponent("Recordings", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent("\(id).wav")
        try audioData.write(to: fileURL, options: .atomic)

        let item = RecordingItem(
            id: id,
            agentId: agentId,
            createdAt: Date(),
            duration: duration,
            asrText: asrText,
            prompt: prompt,
            recordingType: recordingType,
            processingStatus: processingStatus ?? (asrText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .savedOnly : .completed),
            selectedPrompt: selectedPrompt ?? prompt,
            fileURL: fileURL,
            source: source,
            clientMessageId: clientMessageId,
            events: [
                RecordingEventItem(
                    kind: .created,
                    title: "录音已保存",
                    content: source.label,
                    status: .completed
                )
            ]
        )
        items.insert(item, at: 0)
        persist()
        return item
    }

    func configureRecordingForProcessing(
        recordingId: String,
        type: RecordingType,
        prompt: String,
        clientMessageId: String?
    ) {
        guard let index = items.firstIndex(where: { $0.id == recordingId }) else { return }
        items[index].recordingType = type
        items[index].processingStatus = type.sendsToAgent ? .processing : .savedOnly
        items[index].prompt = prompt
        items[index].selectedPrompt = prompt
        items[index].clientMessageId = clientMessageId
        appendEvent(
            RecordingEventItem(
                kind: .status,
                title: type.sendsToAgent ? "开始处理录音" : "仅保存录音",
                content: type.label,
                status: type.sendsToAgent ? .running : .completed
            ),
            index: index
        )
        persist()
    }

    func update(_ item: RecordingItem) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = item
            persist()
        }
    }

    func updateAsrText(clientMessageId: String, text: String) {
        guard let index = items.firstIndex(where: { $0.clientMessageId == clientMessageId }) else { return }
        items[index].asrText = text
        items[index].asrProgress = 1
        items[index].asrError = nil
        if items[index].processingStatus == .queued || items[index].processingStatus == .savedOnly {
            items[index].processingStatus = .processing
        }
        appendEvent(
            RecordingEventItem(
                kind: .asr,
                title: "ASR 转写完成",
                content: text,
                status: .completed
            ),
            index: index
        )
        persist()
    }

    func updateAsrJob(recordingId: String, jobId: String, uploadProgress: Double, asrProgress: Double) {
        guard let index = items.firstIndex(where: { $0.id == recordingId }) else { return }
        items[index].asrJobId = jobId
        items[index].uploadProgress = clampedProgress(uploadProgress)
        items[index].asrProgress = clampedProgress(asrProgress)
        items[index].asrError = nil
        if items[index].processingStatus == .savedOnly {
            items[index].processingStatus = .queued
        }
        persist()
    }

    func updateAsrFailure(clientMessageId: String, error: String) {
        guard let index = items.firstIndex(where: { $0.clientMessageId == clientMessageId }) else { return }
        items[index].asrError = error
        items[index].processingStatus = .failed
        appendEvent(
            RecordingEventItem(
                kind: .error,
                title: "ASR 转写失败",
                content: error,
                status: .failed
            ),
            index: index
        )
        persist()
    }

    func updateClientMessageId(recordingId: String, clientMessageId: String?) {
        guard let index = items.firstIndex(where: { $0.id == recordingId }) else { return }
        items[index].clientMessageId = clientMessageId
        persist()
    }

    func appendEvent(_ event: RecordingEventItem, recordingId: String) {
        guard let index = items.firstIndex(where: { $0.id == recordingId }) else { return }
        appendEvent(event, index: index)
        persist()
    }

    func appendEvent(_ event: RecordingEventItem, clientMessageId: String) {
        guard let index = items.firstIndex(where: { $0.clientMessageId == clientMessageId }) else { return }
        appendEvent(event, index: index)
        persist()
    }

    func appendEvent(_ payload: RecordingEventPayload) {
        let index: Int?
        if let recordingId = payload.recordingId, !recordingId.isEmpty {
            index = items.firstIndex(where: { $0.id == recordingId })
        } else if let clientMessageId = payload.clientMessageId, !clientMessageId.isEmpty {
            index = items.firstIndex(where: { $0.clientMessageId == clientMessageId })
        } else {
            index = nil
        }
        guard let index else { return }
        if let jobId = payload.jobId {
            items[index].asrJobId = jobId
        }
        if let percent = payload.percent {
            items[index].asrProgress = clampedProgress(percent / 100)
        } else if let completed = payload.completedSegments,
                  let total = payload.totalSegments,
                  total > 0 {
            items[index].asrProgress = clampedProgress(Double(completed) / Double(total))
        }
        appendEvent(payload.event, index: index)
        updateProcessingStatus(for: payload.event, index: index)
        if let artifact = payload.artifact {
            writeArtifact(artifact, recordingId: items[index].id, sourceEventId: payload.event.id, index: index)
        }
        persist()
    }

    @discardableResult
    func addReminder(
        recordingId: String,
        title: String,
        notes: String = "",
        dueAt: Date
    ) -> RecordingReminderItem {
        let reminder = RecordingReminderItem(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            dueAt: dueAt
        )
        guard let index = items.firstIndex(where: { $0.id == recordingId }) else { return reminder }
        items[index].reminders.append(reminder)
        appendEvent(
            RecordingEventItem(
                kind: .reminder,
                title: reminder.title.isEmpty ? "新增提醒" : reminder.title,
                content: reminder.notes,
                status: .pending,
                createdAt: reminder.createdAt
            ),
            index: index
        )
        persist()
        return reminder
    }

    func setReminderCompleted(recordingId: String, reminderId: String, isCompleted: Bool) {
        guard let recordingIndex = items.firstIndex(where: { $0.id == recordingId }),
              let reminderIndex = items[recordingIndex].reminders.firstIndex(where: { $0.id == reminderId }) else { return }
        items[recordingIndex].reminders[reminderIndex].isCompleted = isCompleted
        persist()
    }

    func deleteRecording(id: String) throws {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let item = items.remove(at: index)
        if FileManager.default.fileExists(atPath: item.fileURL.path) {
            try FileManager.default.removeItem(at: item.fileURL)
        }
        let artifactDirectory = documentsDirectory
            .appendingPathComponent("RecordingArtifacts", isDirectory: true)
            .appendingPathComponent(item.id, isDirectory: true)
        if FileManager.default.fileExists(atPath: artifactDirectory.path) {
            try FileManager.default.removeItem(at: artifactDirectory)
        }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(items) {
            defaults.set(data, forKey: key)
        }
    }

    private func appendEvent(_ event: RecordingEventItem, index: Int) {
        if items[index].events.contains(where: { $0.id == event.id }) { return }
        if event.kind == .asr,
           items[index].events.contains(where: { $0.kind == .asr && $0.content == event.content }) {
            return
        }
        items[index].events.append(event)
        items[index].events.sort { $0.createdAt < $1.createdAt }
    }

    private func clampedProgress(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    private func updateProcessingStatus(for event: RecordingEventItem, index: Int) {
        switch event.kind {
        case .error:
            items[index].processingStatus = .failed
        case .agentReply:
            items[index].processingStatus = .completed
        case .asr, .delivered, .subtask, .scheduledTask, .reminder, .artifact, .status, .created, .other:
            if items[index].processingStatus != .failed {
                items[index].processingStatus = .processing
            }
        }
    }

    private func writeArtifact(_ payload: RecordingArtifactPayload, recordingId: String, sourceEventId: String, index: Int) {
        if items[index].artifacts.contains(where: { $0.sourceEventId == sourceEventId }) { return }
        let directory = documentsDirectory
            .appendingPathComponent("RecordingArtifacts", isDirectory: true)
            .appendingPathComponent(recordingId, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let fileURL = directory.appendingPathComponent(Self.safeArtifactFilename(payload.filename))
            let data: Data
            if payload.encoding == "base64", let decoded = Data(base64Encoded: payload.content) {
                data = decoded
            } else {
                data = Data(payload.content.utf8)
            }
            try data.write(to: fileURL, options: .atomic)
            items[index].artifacts.append(RecordingArtifactItem(
                filename: payload.filename,
                mimeType: payload.mimeType,
                fileURL: fileURL,
                backendPath: payload.backendPath,
                sourceEventId: sourceEventId,
                relatedTaskId: eventRelatedTaskId(items[index].events.first { $0.id == sourceEventId }),
                createdAt: Date()
            ))
            items[index].artifacts.sort { $0.createdAt < $1.createdAt }
        } catch {
            appendEvent(
                RecordingEventItem(
                    kind: .error,
                    title: "文件保存失败",
                    content: error.localizedDescription,
                    status: .failed
                ),
                index: index
            )
            items[index].processingStatus = .failed
        }
    }

    private static func safeArtifactFilename(_ filename: String) -> String {
        let trimmed = filename.trimmingCharacters(in: .whitespacesAndNewlines)
        let safe = trimmed.map { character -> Character in
            if character == "/" || character == "\\" || character == ":" {
                return "-"
            }
            return character
        }
        let result = String(safe).trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? "recording-artifact.md" : result
    }

    private func eventRelatedTaskId(_ event: RecordingEventItem?) -> String? {
        guard let event else { return nil }
        for key in ["related_task_id", "task_id"] {
            if let value = event.metadata[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private static func loadItems(from defaults: UserDefaults, key: String) -> [RecordingItem] {
        guard let data = defaults.data(forKey: key),
              let items = try? JSONDecoder().decode([RecordingItem].self, from: data) else {
            return []
        }
        return items
    }
}

final class HeadsetSettingsStore: ObservableObject {
    private let defaults: UserDefaults
    private let key = "earphone_headset_settings_v1"

    @Published private(set) var settings: HeadsetLocalSettings

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        settings = Self.loadSettings(from: defaults, key: key)
    }

    func load() -> HeadsetLocalSettings {
        Self.loadSettings(from: defaults, key: key)
    }

    func save(_ settings: HeadsetLocalSettings) {
        self.settings = settings
        if let data = try? JSONEncoder().encode(settings) {
            defaults.set(data, forKey: key)
        }
    }

    func update(_ transform: (inout HeadsetLocalSettings) -> Void) {
        var copy = settings
        transform(&copy)
        save(copy)
    }

    private static func loadSettings(from defaults: UserDefaults, key: String) -> HeadsetLocalSettings {
        guard let data = defaults.data(forKey: key),
              let settings = try? JSONDecoder().decode(HeadsetLocalSettings.self, from: data) else {
            return .defaultValue
        }
        return settings
    }
}
