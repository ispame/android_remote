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
            fileURL: fileURL,
            source: source,
            clientMessageId: clientMessageId
        )
        items.insert(item, at: 0)
        persist()
        return item
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
        persist()
    }

    func deleteRecording(id: String) throws {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let item = items.remove(at: index)
        if FileManager.default.fileExists(atPath: item.fileURL.path) {
            try FileManager.default.removeItem(at: item.fileURL)
        }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(items) {
            defaults.set(data, forKey: key)
        }
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
