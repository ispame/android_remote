import Foundation

@main
struct EarphoneLocalModelsTests {
    static func main() throws {
        try testAgentProfileDecodesPinnedDefaults()
        try testAgentProfilesSortPinnedFirst()
        try testAgentProfilesSortPinnedBeforeUnreadActivity()
        try testAgentProfilesSortUnreadBeforeReadActivity()
        try testAgentProfilesSortRecentActivityWithinUnreadGroup()
        try testAgentProfilesSortFallsBackWithoutActivity()
        try testCronValidatorAcceptsFiveFieldExpressions()
        try testAgentTaskItemParsesProtocolPayload()
        try testRecordingStoreCreatesAndDeletesMetadata()
        try testRecordingStoreBackfillsAsrByClientMessageId()
        try testHeadsetSettingsStorePersistsEQAndShortcuts()
        print("EarphoneLocalModelsTests passed")
    }

    private static func testAgentProfileDecodesPinnedDefaults() throws {
        let json = """
        {
          "id": "legacy-agent",
          "platform": "openclaw",
          "displayName": "Legacy",
          "gatewayUrl": "wss://example.com/ws",
          "backendId": "backend-1",
          "backendLabel": "Backend 1",
          "token": "secret",
          "isPaired": true,
          "asrMode": "router",
          "asrProfileId": "default",
          "createdAt": 725846400,
          "updatedAt": 725846500
        }
        """.data(using: .utf8)!

        let profile = try JSONDecoder().decode(AgentProfile.self, from: json)

        try expect(!profile.isPinned, "legacy profile should default to not pinned")
        try expect(profile.sortIndex == 0, "legacy profile should default sort index to 0")
    }

    private static func testAgentProfilesSortPinnedFirst() throws {
        let old = profile(id: "old", name: "Old", isPinned: false, sortIndex: 0, updatedAt: Date(timeIntervalSince1970: 100))
        let recent = profile(id: "recent", name: "Recent", isPinned: false, sortIndex: 0, updatedAt: Date(timeIntervalSince1970: 300))
        let pinnedLater = profile(id: "pinned-later", name: "Pinned Later", isPinned: true, sortIndex: 2, updatedAt: Date(timeIntervalSince1970: 150))
        let pinnedFirst = profile(id: "pinned-first", name: "Pinned First", isPinned: true, sortIndex: 1, updatedAt: Date(timeIntervalSince1970: 50))

        let sorted = [old, pinnedLater, recent, pinnedFirst].sortedForAgentList()

        try expect(sorted.map(\.id) == ["pinned-first", "pinned-later", "recent", "old"], "pinned agents should sort first, then recent agents")
    }

    private static func testAgentProfilesSortPinnedBeforeUnreadActivity() throws {
        let pinnedOld = profile(id: "pinned-old", name: "Pinned Old", isPinned: true, sortIndex: 1, updatedAt: Date(timeIntervalSince1970: 100))
        let unreadRecent = profile(id: "unread-recent", name: "Unread Recent", isPinned: false, sortIndex: 0, updatedAt: Date(timeIntervalSince1970: 500))
        let activities = [
            "pinned-old": AgentListActivity(latestMessagePreview: "older", latestMessageAt: Date(timeIntervalSince1970: 120)),
            "unread-recent": AgentListActivity(latestMessagePreview: "newer", latestMessageAt: Date(timeIntervalSince1970: 900))
        ]

        let sorted = [unreadRecent, pinnedOld].sortedForAgentList(
            unreadCounts: ["unread-recent": 2],
            activities: activities
        )

        try expect(sorted.map(\.id) == ["pinned-old", "unread-recent"], "pinned agents should sort before unread unpinned agents")
    }

    private static func testAgentProfilesSortUnreadBeforeReadActivity() throws {
        let readRecent = profile(id: "read-recent", name: "Read Recent", isPinned: false, sortIndex: 0, updatedAt: Date(timeIntervalSince1970: 100))
        let unreadOld = profile(id: "unread-old", name: "Unread Old", isPinned: false, sortIndex: 0, updatedAt: Date(timeIntervalSince1970: 100))
        let activities = [
            "read-recent": AgentListActivity(latestMessagePreview: "newer", latestMessageAt: Date(timeIntervalSince1970: 900)),
            "unread-old": AgentListActivity(latestMessagePreview: "older", latestMessageAt: Date(timeIntervalSince1970: 200))
        ]

        let sorted = [readRecent, unreadOld].sortedForAgentList(
            unreadCounts: ["unread-old": 1],
            activities: activities
        )

        try expect(sorted.map(\.id) == ["unread-old", "read-recent"], "unread unpinned agents should sort before read unpinned agents")
    }

    private static func testAgentProfilesSortRecentActivityWithinUnreadGroup() throws {
        let olderUnread = profile(id: "older-unread", name: "Older Unread", isPinned: false, sortIndex: 0, updatedAt: Date(timeIntervalSince1970: 100))
        let newerUnread = profile(id: "newer-unread", name: "Newer Unread", isPinned: false, sortIndex: 0, updatedAt: Date(timeIntervalSince1970: 100))
        let statusUpdated = profile(id: "status-updated", name: "Status Updated", isPinned: false, sortIndex: 0, updatedAt: Date(timeIntervalSince1970: 100))
        let activities = [
            "older-unread": AgentListActivity(latestMessagePreview: "older", latestMessageAt: Date(timeIntervalSince1970: 200)),
            "newer-unread": AgentListActivity(latestMessagePreview: "newer", latestMessageAt: Date(timeIntervalSince1970: 900)),
            "status-updated": AgentListActivity(lastStatus: .available, lastStatusChangedAt: Date(timeIntervalSince1970: 600))
        ]

        let sorted = [olderUnread, statusUpdated, newerUnread].sortedForAgentList(
            unreadCounts: ["older-unread": 1, "newer-unread": 1, "status-updated": 1],
            activities: activities
        )

        try expect(sorted.map(\.id) == ["newer-unread", "status-updated", "older-unread"], "unread agents should sort by newest message or status activity")
    }

    private static func testAgentProfilesSortFallsBackWithoutActivity() throws {
        let alpha = profile(id: "alpha", name: "Alpha", isPinned: false, sortIndex: 0, updatedAt: Date(timeIntervalSince1970: 100))
        let beta = profile(id: "beta", name: "Beta", isPinned: false, sortIndex: 0, updatedAt: Date(timeIntervalSince1970: 100))
        let recent = profile(id: "recent", name: "Recent", isPinned: false, sortIndex: 0, updatedAt: Date(timeIntervalSince1970: 300))

        let sorted = [beta, recent, alpha].sortedForAgentList(
            unreadCounts: [:],
            activities: [:]
        )

        try expect(sorted.map(\.id) == ["recent", "alpha", "beta"], "agents without activity should fall back to updated date and display name")
    }

    private static func testCronValidatorAcceptsFiveFieldExpressions() throws {
        try expect(CronExpressionValidator.isValid("*/15 * * * *"), "step minute cron should be valid")
        try expect(CronExpressionValidator.isValid("0 9 * * 1-5"), "weekday cron should be valid")
        try expect(!CronExpressionValidator.isValid("0 9 * *"), "four-field cron should be invalid")
        try expect(!CronExpressionValidator.isValid("61 * * * *"), "out-of-range minute should be invalid")
        try expect(!CronExpressionValidator.isValid("0 24 * * *"), "out-of-range hour should be invalid")
    }

    private static func testRecordingStoreCreatesAndDeletesMetadata() throws {
        let defaults = try temporaryDefaults()
        let directory = try temporaryDirectory()
        let store = RecordingStore(defaults: defaults, documentsDirectory: directory)
        let audio = Data([0x01, 0x02, 0x03, 0x04])

        let item = try store.createRecording(agentId: "agent-1", audioData: audio, asrText: "你好")

        try expect(store.recordings(for: "agent-1").map(\.id) == [item.id], "created recording should be listed for its agent")
        try expect(FileManager.default.fileExists(atPath: item.fileURL.path), "recording audio file should exist")

        try store.deleteRecording(id: item.id)

        try expect(store.recordings(for: "agent-1").isEmpty, "deleted recording metadata should disappear")
        try expect(!FileManager.default.fileExists(atPath: item.fileURL.path), "deleted recording audio file should be removed")
    }

    private static func testAgentTaskItemParsesProtocolPayload() throws {
        let item = AgentTaskItem(json: [
            "task_id": "task-1",
            "backend_id": "backend-1",
            "title": "Morning brief",
            "prompt": "Summarize overnight alerts",
            "schedule": "0 8 * * *",
            "schedule_display": "每天 08:00",
            "enabled": true,
            "state": "scheduled",
            "source": "hermes",
            "updated_at": "2026-05-24T00:00:00+08:00"
        ])

        try expect(item?.taskId == "task-1", "task id should parse from protocol payload")
        try expect(item?.backendId == "backend-1", "backend id should parse from protocol payload")
        try expect(item?.scheduleDisplay == "每天 08:00", "schedule display should parse from protocol payload")
        try expect(item?.source == "hermes", "source should parse from protocol payload")
    }

    private static func testRecordingStoreBackfillsAsrByClientMessageId() throws {
        let defaults = try temporaryDefaults()
        let directory = try temporaryDirectory()
        let store = RecordingStore(defaults: defaults, documentsDirectory: directory)

        let item = try store.createRecording(
            agentId: "agent-1",
            audioData: Data([0x01]),
            source: .phone,
            clientMessageId: "client-audio-1"
        )

        store.updateAsrText(clientMessageId: "client-audio-1", text: "转写完成")

        try expect(store.recordings(for: "agent-1").first?.id == item.id, "recording should still be listed")
        try expect(store.recordings(for: "agent-1").first?.asrText == "转写完成", "ASR result should backfill matching recording")
    }

    private static func testHeadsetSettingsStorePersistsEQAndShortcuts() throws {
        let defaults = try temporaryDefaults()
        let store = HeadsetSettingsStore(defaults: defaults)
        var settings = store.load()
        settings.selectedEQPresetId = "jazz"
        settings.eqPresets = settings.eqPresets.map { preset in
            if preset.id == "jazz" {
                var copy = preset
                copy.bands[0].gain = 4
                return copy
            }
            return preset
        }
        settings.shortcuts[0].action = "同声传译"

        store.save(settings)
        let reloaded = HeadsetSettingsStore(defaults: defaults).load()

        try expect(reloaded.selectedEQPresetId == "jazz", "selected EQ preset should persist")
        try expect(reloaded.eqPresets.first { $0.id == "jazz" }?.bands.first?.gain == 4, "edited EQ gain should persist")
        try expect(reloaded.shortcuts[0].action == "同声传译", "edited shortcut should persist")
    }

    private static func profile(
        id: String,
        name: String,
        isPinned: Bool,
        sortIndex: Int,
        updatedAt: Date
    ) -> AgentProfile {
        AgentProfile(
            id: id,
            platform: .openclaw,
            displayName: name,
            gatewayUrl: "wss://example.com/ws",
            backendId: id,
            backendLabel: name,
            token: "",
            isPaired: true,
            asrMode: "router",
            asrProfileId: "",
            createdAt: updatedAt,
            updatedAt: updatedAt,
            isPinned: isPinned,
            sortIndex: sortIndex
        )
    }

    private static func temporaryDefaults() throws -> UserDefaults {
        let suiteName = "EarphoneLocalModelsTests-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw TestFailure("could not create temporary defaults")
        }
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private static func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("EarphoneLocalModelsTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() {
            throw TestFailure(message)
        }
    }
}

private struct TestFailure: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}
