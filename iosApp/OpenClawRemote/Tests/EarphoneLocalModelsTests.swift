import Foundation
import Combine

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
        try testAgentTaskServiceExpiresPendingTaskRequest()
        try testAgentTaskServiceClearsLoadingOnRouterError()
        try testRecordingStoreCreatesAndDeletesMetadata()
        try testRecordingStoreBackfillsAsrByClientMessageId()
        try testRecordingStoreTracksLongAsrJobProgressAndFailure()
        try testRecordingStoreTracksPromptEventsAndReminders()
        try testLegacyRecordingDecodesAsAudioOnly()
        try testRecordingStoreConfiguresProcessingTypePromptAndArtifacts()
        try testRecordingArtifactPersistsRelatedTaskId()
        try testRecordingEventPayloadParsesProtocolFrame()
        try testRecordingEventPayloadPreservesDisplayMetadata()
        try testRecordingDetailPresentationGroupsArtifactsByAgentTask()
        try testRecordingDetailPresentationKeepsUnboundArtifactsUnassignedForMultipleTasks()
        try testRecordingDetailPresentationHidesEmptyScheduledEvents()
        try testMeetingRecordingPromptRequiresExecutableStructuredEvents()
        try testIdeaRecordingPromptRequiresResearchReport()
        try testRecordingChatContentFormatsPromptAndTranscript()
        try testRecordingSettingsDefaultToFirstConfiguredAgent()
        try testRecordingSettingsFallbackWhenPrimaryAgentIsDeleted()
        try testRecordingAsrPayloadIncludesRecordingContext()
        try testChatAsrPayloadOmitsRecordingContext()
        try testLongRecordingUploadRequestUsesHttpJobMetadata()
        try testHeadsetDefaultFakeData()
        try testHeadsetSettingsAddsDemoDevice()
        try testHeadsetSettingsStorePersistsEQAndShortcuts()
        try testSettingsManagerClearsPairingWhenTokenChanges()
        try testSettingsManagerDoesNotProjectUnpairedBackendAsPaired()
        try testSettingsManagerMigratesMiniMaxKeyToCredentialVault()
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

        let item = try store.createRecording(agentId: "agent-1", audioData: audio, asrText: "你好", prompt: "请总结录音")

        try expect(store.recordings(for: "agent-1").map(\.id) == [item.id], "created recording should be listed for its agent")
        try expect(store.recordings(for: "agent-1").first?.prompt == "请总结录音", "recording should persist the prompt used for Agent delivery")
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

    private static func testAgentTaskServiceExpiresPendingTaskRequest() throws {
        let defaults = try temporaryDefaults()
        var timeoutActions: [() -> Void] = []
        let service = AgentTaskService(
            defaults: defaults,
            timeoutInterval: 0.1,
            timeoutScheduler: { _, action in
                timeoutActions.append(action)
                return AnyCancellable {}
            }
        )
        let client = FakeAgentTaskRequestClient()
        service.bind(to: client)

        let profile = profile(id: "hermes", name: "Hermes")
        service.refreshTasks(for: profile)

        try expect(client.taskListRequests.count == 1, "refresh should send one task list request")
        try expect(service.isLoading(profile.id), "pending task list request should mark profile loading")

        timeoutActions.first?()
        drainMainQueue()

        try expect(!service.isLoading(profile.id), "timeout should clear task loading state")
        try expect(service.errorsByProfileId[profile.id] == "请求超时，请稍后重试", "timeout should surface a profile error")
    }

    private static func testAgentTaskServiceClearsLoadingOnRouterError() throws {
        let defaults = try temporaryDefaults()
        let service = AgentTaskService(defaults: defaults, timeoutScheduler: { _, _ in AnyCancellable {} })
        let client = FakeAgentTaskRequestClient()
        service.bind(to: client)

        let profile = profile(id: "hermes", name: "Hermes")
        service.refreshTasks(for: profile)

        try expect(service.isLoading(profile.id), "pending task list request should start loading")

        client.subject.send(.error(code: "CLIENT_NOT_FOUND", message: "Backend offline"))
        drainMainQueue()

        try expect(!service.isLoading(profile.id), "router error should clear task loading state")
        try expect(service.errorsByProfileId[profile.id] == "Backend offline", "router error should surface the backend failure")
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

        let recording = store.recordings(for: "agent-1").first
        let hasAsrEvent = recording?.events.contains { event in
            event.kind == .asr && event.content == "转写完成"
        } == true
        try expect(recording?.id == item.id, "recording should still be listed")
        try expect(recording?.asrText == "转写完成", "ASR result should backfill matching recording")
        try expect(hasAsrEvent, "ASR backfill should add a recording timeline event")
    }

    private static func testRecordingStoreTracksLongAsrJobProgressAndFailure() throws {
        let defaults = try temporaryDefaults()
        let directory = try temporaryDirectory()
        let store = RecordingStore(defaults: defaults, documentsDirectory: directory)

        let item = try store.createRecording(
            agentId: "agent-1",
            audioData: Data([0x01]),
            source: .phone
        )
        store.configureRecordingForProcessing(
            recordingId: item.id,
            type: .meeting,
            prompt: RecordingSettings.meetingPrompt,
            clientMessageId: "client-long-1"
        )
        store.updateAsrJob(recordingId: item.id, jobId: "job-long-1", uploadProgress: 0.25, asrProgress: 0)

        let progressPayload = try unwrap(RecordingEventPayload(json: [
            "recording_id": item.id,
            "client_message_id": "client-long-1",
            "event_id": "progress-1",
            "kind": "asr",
            "title": "ASR 转写中",
            "content": "1/4",
            "status": "running",
            "data": [
                "job_id": "job-long-1",
                "percent": 50,
                "completed_segments": 2,
                "total_segments": 4,
            ],
        ]), "long ASR progress payload should parse")
        store.appendEvent(progressPayload)
        store.updateAsrFailure(clientMessageId: "client-long-1", error: "ASR_EMPTY_TRANSCRIPT")

        let recording = try unwrap(store.recordings(for: "agent-1").first, "recording should be present")
        try expect(recording.asrJobId == "job-long-1", "recording should retain the long ASR job id")
        try expect(recording.uploadProgress == 0.25, "recording should retain upload progress")
        try expect(recording.asrProgress == 0.5, "recording should update ASR progress from recording_event data")
        try expect(recording.asrError == "ASR_EMPTY_TRANSCRIPT", "recording should retain ASR failure code")
        try expect(recording.processingStatus == .failed, "ASR failure should mark recording failed")
        try expect(recording.events.contains { $0.kind == .error && $0.content == "ASR_EMPTY_TRANSCRIPT" }, "ASR failure should add an error event")
    }

    private static func testRecordingStoreTracksPromptEventsAndReminders() throws {
        let defaults = try temporaryDefaults()
        let directory = try temporaryDirectory()
        let store = RecordingStore(defaults: defaults, documentsDirectory: directory)
        let item = try store.createRecording(
            agentId: "agent-1",
            audioData: Data([0x01]),
            prompt: "分析录音并拆任务",
            source: .headset,
            clientMessageId: "client-audio-2"
        )

        store.appendEvent(RecordingEventItem(
            kind: .subtask,
            title: "保存文档",
            content: "已保存 docs/meeting.md",
            status: .completed
        ), clientMessageId: "client-audio-2")
        let dueAt = Date(timeIntervalSince1970: 1_800_000_000)
        let reminder = store.addReminder(
            recordingId: item.id,
            title: "跟进会议纪要",
            notes: "确认负责人",
            dueAt: dueAt
        )

        let reloaded = RecordingStore(defaults: defaults, documentsDirectory: directory)
        let recording = try unwrap(reloaded.recordings(for: "agent-1").first, "recording should reload")
        let hasSavedDocEvent = recording.events.contains { $0.title == "保存文档" }
        try expect(recording.prompt == "分析录音并拆任务", "prompt should survive persistence")
        try expect(hasSavedDocEvent, "timeline event should survive persistence")
        try expect(recording.reminders.map(\.id) == [reminder.id], "reminder should be attached to the recording")
        try expect(recording.reminders.first?.dueAt == dueAt, "reminder due date should survive persistence")
    }

    private static func testLegacyRecordingDecodesAsAudioOnly() throws {
        let json = """
        {
          "id": "legacy-recording",
          "agentId": "agent-1",
          "createdAt": 725846400,
          "duration": 12,
          "asrText": "旧转写",
          "prompt": "旧 Prompt",
          "fileURL": "file:///tmp/legacy.wav",
          "source": "phone",
          "clientMessageId": "cm-old"
        }
        """.data(using: .utf8)!

        let recording = try JSONDecoder().decode(RecordingItem.self, from: json)

        try expect(recording.recordingType == .audioOnly, "legacy recordings should decode as audio-only")
        try expect(recording.processingStatus == .completed, "legacy recordings with ASR text should decode as completed")
        try expect(recording.selectedPrompt == "旧 Prompt", "legacy prompt should seed selected prompt")
        try expect(recording.artifacts.isEmpty, "legacy recordings should default to no artifacts")
    }

    private static func testRecordingStoreConfiguresProcessingTypePromptAndArtifacts() throws {
        let defaults = try temporaryDefaults()
        let directory = try temporaryDirectory()
        let store = RecordingStore(defaults: defaults, documentsDirectory: directory)
        let item = try store.createRecording(agentId: "agent-1", audioData: Data([0x01]), source: .phone)

        store.configureRecordingForProcessing(
            recordingId: item.id,
            type: .meeting,
            prompt: RecordingSettings.meetingPrompt,
            clientMessageId: "client-meeting-1"
        )

        let payload = try unwrap(RecordingEventPayload(json: [
            "recording_id": item.id,
            "client_message_id": "client-meeting-1",
            "event_id": "artifact-event-1",
            "kind": "artifact",
            "title": "会议纪要文件",
            "content": "meeting.md",
            "status": "completed",
            "timestamp": "2026-05-31T10:00:00.000Z",
            "data": [
                "artifact": [
                    "filename": "meeting.md",
                    "mime_type": "text/markdown",
                    "encoding": "utf8",
                    "content": "# 会议纪要\n\n结论。",
                    "backend_path": "docs/meeting.md",
                ]
            ],
        ]), "artifact payload should parse")

        store.appendEvent(payload)

        let recording = try unwrap(store.recordings(for: "agent-1").first, "recording should be present")
        try expect(recording.recordingType == .meeting, "recording type should update before processing")
        try expect(recording.processingStatus == .processing, "recording should enter processing state after configuration")
        try expect(recording.selectedPrompt == RecordingSettings.meetingPrompt, "selected prompt should be persisted on the recording")
        try expect(recording.clientMessageId == "client-meeting-1", "client message id should bind ASR results and events")
        try expect(recording.artifacts.count == 1, "artifact event should create one local artifact")
        try expect(recording.artifacts[0].filename == "meeting.md", "artifact filename should be preserved")
        try expect(recording.artifacts[0].mimeType == "text/markdown", "artifact mime type should be preserved")
        try expect(FileManager.default.fileExists(atPath: recording.artifacts[0].fileURL.path), "artifact content should be written locally")
        let artifactText = try String(contentsOf: recording.artifacts[0].fileURL, encoding: .utf8)
        try expect(artifactText == "# 会议纪要\n\n结论。", "artifact file content should match event payload")
    }

    private static func testRecordingArtifactPersistsRelatedTaskId() throws {
        let defaults = try temporaryDefaults()
        let directory = try temporaryDirectory()
        let store = RecordingStore(defaults: defaults, documentsDirectory: directory)
        let item = try store.createRecording(agentId: "agent-1", audioData: Data([0x01]), source: .phone)

        let payload = try unwrap(RecordingEventPayload(json: [
            "recording_id": item.id,
            "event_id": "artifact-event-related",
            "kind": "artifact",
            "title": "调研报告",
            "content": "research.md",
            "status": "completed",
            "data": [
                "related_task_id": "task-research",
                "artifact": [
                    "filename": "research.md",
                    "mime_type": "text/markdown",
                    "encoding": "utf8",
                    "content": "# 调研报告",
                ]
            ],
        ]), "artifact payload should parse")

        store.appendEvent(payload)

        let recording = try unwrap(store.recordings(for: "agent-1").first, "recording should be present")
        try expect(recording.artifacts.first?.relatedTaskId == "task-research", "artifact should persist related task id from event metadata")
    }

    private static func testRecordingEventPayloadParsesProtocolFrame() throws {
        let payload = RecordingEventPayload(json: [
            "recording_id": "recording-1",
            "client_message_id": "client-audio-1",
            "event_id": "event-1",
            "kind": "scheduled_task",
            "title": "新增定时任务",
            "content": "每天 9 点提醒跟进",
            "status": "completed",
            "timestamp": "2026-05-31T10:00:00.000Z",
        ])

        try expect(payload?.recordingId == "recording-1", "recording event should parse recording id")
        try expect(payload?.clientMessageId == "client-audio-1", "recording event should parse client message id")
        try expect(payload?.event.kind == .scheduledTask, "recording event kind should parse scheduled_task")
        try expect(payload?.event.status == .completed, "recording event status should parse completed")
        try expect(payload?.event.title == "新增定时任务", "recording event title should parse")
    }

    private static func testRecordingEventPayloadPreservesDisplayMetadata() throws {
        let payload = RecordingEventPayload(json: [
            "recording_id": "recording-1",
            "client_message_id": "client-audio-1",
            "event_id": "event-1",
            "kind": "subtask",
            "title": "调研 Loose Index / 轻量化索引技术方案",
            "content": "搜集轻量化索引方案、开源项目、技术论文，输出调研报告",
            "status": "pending",
            "data": [
                "owner": "agent",
                "next_action": "开始调研并补充文档",
                "needs_user_input": false,
                "assumptions": ["先按手机端本地搜索场景调研"],
            ],
        ])

        try expect(payload?.event.metadata["owner"] == "agent", "recording event should preserve owner metadata for grouping")
        try expect(payload?.event.metadata["next_action"] == "开始调研并补充文档", "recording event should preserve next action metadata")
        try expect(payload?.event.metadata["needs_user_input"] == "false", "recording event should stringify boolean metadata")
        try expect(payload?.event.metadata["assumptions"] == "先按手机端本地搜索场景调研", "recording event should stringify list metadata")
    }

    private static func testRecordingDetailPresentationGroupsArtifactsByAgentTask() throws {
        let recording = recordingFixture(
            events: [
                RecordingEventItem(
                    id: "task-1-event",
                    kind: .subtask,
                    title: "调研 Loose Index",
                    content: "输出调研报告",
                    status: .running,
                    metadata: ["owner": "agent", "task_id": "task-1"]
                ),
                RecordingEventItem(
                    id: "task-2-event",
                    kind: .subtask,
                    title: "整理会议纪要",
                    content: "整理成 Markdown",
                    status: .completed,
                    metadata: ["owner": "agent", "task_id": "task-2"]
                ),
            ],
            artifacts: [
                artifactFixture(id: "artifact-1", filename: "research.md", relatedTaskId: "task-1"),
                artifactFixture(id: "artifact-2", filename: "compare.md", relatedTaskId: "task-1"),
                artifactFixture(id: "artifact-3", filename: "meeting.md", relatedTaskId: "task-2"),
            ]
        )

        let presentation = RecordingDetailPresentation(recording: recording)

        try expect(presentation.agentTaskGroups.map(\.taskId) == ["task-1", "task-2"], "agent tasks should preserve event order")
        try expect(presentation.agentTaskGroups[0].artifacts.map(\.filename) == ["research.md", "compare.md"], "first task should group multiple related files")
        try expect(presentation.agentTaskGroups[1].artifacts.map(\.filename) == ["meeting.md"], "second task should include its related file")
        try expect(presentation.unassignedArtifacts.isEmpty, "all related artifacts should be assigned to task groups")
    }

    private static func testRecordingDetailPresentationKeepsUnboundArtifactsUnassignedForMultipleTasks() throws {
        let recording = recordingFixture(
            events: [
                RecordingEventItem(kind: .subtask, title: "任务一", content: "", metadata: ["owner": "agent", "task_id": "task-1"]),
                RecordingEventItem(kind: .subtask, title: "任务二", content: "", metadata: ["owner": "agent", "task_id": "task-2"]),
            ],
            artifacts: [
                artifactFixture(id: "artifact-unbound", filename: "unbound.md", relatedTaskId: nil),
            ]
        )

        let presentation = RecordingDetailPresentation(recording: recording)

        try expect(presentation.agentTaskGroups.allSatisfy { $0.artifacts.isEmpty }, "unbound artifact should not be guessed when there are multiple agent tasks")
        try expect(presentation.unassignedArtifacts.map(\.filename) == ["unbound.md"], "unbound artifact should remain visible as unassigned")
    }

    private static func testRecordingDetailPresentationHidesEmptyScheduledEvents() throws {
        let recording = recordingFixture(
            events: [
                RecordingEventItem(kind: .agentReply, title: "Agent 回复", content: "已完成"),
                RecordingEventItem(kind: .status, title: "处理中", content: "执行中"),
            ],
            artifacts: []
        )

        let presentation = RecordingDetailPresentation(recording: recording)

        try expect(presentation.latestAgentReply?.content == "已完成", "latest agent reply should be exposed for the hero card")
        try expect(presentation.scheduledEvents.isEmpty, "scheduled section should be empty when no scheduled task events exist")
        try expect(presentation.generalTimelineEvents.map(\.kind) == [.status], "general timeline should exclude agent reply from low-priority progress")
    }

    private static func testMeetingRecordingPromptRequiresExecutableStructuredEvents() throws {
        try expect(RecordingSettings.meetingPrompt.contains("# 会议纪要"), "meeting prompt should require the meeting note heading")
        try expect(RecordingSettings.meetingPrompt.contains("## 会议核心结论"), "meeting prompt should require core conclusion heading")
        try expect(RecordingSettings.meetingPrompt.contains("优先基于合理假设直接开始"), "meeting prompt should tell the agent to proceed without unnecessary questions")
        try expect(RecordingSettings.recordingEventProtocolPrompt.contains("一个合法 JSON 数组"), "event protocol should require one JSON array")
        try expect(RecordingSettings.recordingEventProtocolPrompt.contains("禁止输出多个相邻 JSON 对象"), "event protocol should forbid the malformed multi-object format")
        try expect(RecordingSettings.recordingEventProtocolPrompt.contains("task_id"), "event protocol should require stable task ids for agent subtasks")
        try expect(RecordingSettings.recordingEventProtocolPrompt.contains("related_task_id"), "event protocol should bind artifact files to agent subtasks")
    }

    private static func testIdeaRecordingPromptRequiresResearchReport() throws {
        let prompt = RecordingSettings.ideaPrompt

        try expect(prompt.contains("研究型灵感报告"), "idea prompt should identify the output as a research report")
        try expect(prompt.contains("# 灵感研究报告"), "idea prompt should require a Markdown report title")
        try expect(prompt.contains("## 摘要"), "idea prompt should require an executive summary section")
        try expect(prompt.contains("## 问题/机会"), "idea prompt should require problem/opportunity analysis")
        try expect(prompt.contains("## 核心洞察"), "idea prompt should require insight and reasoning")
        try expect(prompt.contains("## 方案"), "idea prompt should require an implementation plan")
        try expect(prompt.contains("## 风险"), "idea prompt should require risk analysis")
        try expect(prompt.contains("## 行动项"), "idea prompt should require next actions")
        try expect(prompt.contains("后台 Agent"), "idea prompt should describe background report generation")
    }

    private static func testRecordingChatContentFormatsPromptAndTranscript() throws {
        let content = RecordingChatContent.format(prompt: "请分析录音", transcript: "今天下午开会")
        let parsed = try unwrap(RecordingChatContent.parse(content), "recording chat content should parse")

        try expect(parsed.prompt == "请分析录音", "recording chat content should retain prompt")
        try expect(parsed.transcript == "今天下午开会", "recording chat content should retain transcript")
    }

    private static func testRecordingSettingsDefaultToFirstConfiguredAgent() throws {
        let defaults = try temporaryDefaults()
        let settings = SettingsManager(defaults: defaults)
        let older = profile(id: "older", name: "Older", isPinned: false, sortIndex: 0, updatedAt: Date(timeIntervalSince1970: 100))
        let pinned = profile(id: "pinned", name: "Pinned", isPinned: true, sortIndex: 1, updatedAt: Date(timeIntervalSince1970: 50))

        _ = settings.saveProfile(older, select: true)
        _ = settings.saveProfile(pinned, select: false)

        try expect(settings.recordingSettings.primaryAgentProfileId == "pinned", "default recording primary agent should follow sorted configured agents")
        try expect(settings.primaryRecordingProfile?.id == "pinned", "primary recording profile should resolve to the default primary agent")
        try expect(settings.recordingSettings.defaultRecordingType == .audioOnly, "recordings should default to audio-only")
        try expect(settings.recordingSettings.customPrompt.isEmpty, "custom recording prompt should default to empty")
    }

    private static func testRecordingSettingsFallbackWhenPrimaryAgentIsDeleted() throws {
        let defaults = try temporaryDefaults()
        let settings = SettingsManager(defaults: defaults)
        let primary = profile(id: "primary", name: "Primary", isPinned: true, sortIndex: 1, updatedAt: Date(timeIntervalSince1970: 100))
        let fallback = profile(id: "fallback", name: "Fallback", isPinned: false, sortIndex: 0, updatedAt: Date(timeIntervalSince1970: 200))

        _ = settings.saveProfile(primary, select: true)
        _ = settings.saveProfile(fallback, select: false)
        settings.updateRecordingSettings(RecordingSettings(
            primaryAgentProfileId: "primary",
            deliverToAgent: true,
            prompt: "自定义录音提示",
            asrProfileId: "doubao",
            defaultRecordingType: .meeting,
            customPrompt: "自定义模板"
        ))

        settings.deleteProfile("primary")

        try expect(settings.recordingSettings.primaryAgentProfileId == "fallback", "deleted primary recording agent should fall back to the next configured agent")
        try expect(settings.recordingSettings.defaultRecordingType == .meeting, "fallback should preserve the default recording type")
        try expect(settings.recordingSettings.customPrompt == "自定义模板", "fallback should preserve the custom recording template")
        try expect(settings.recordingSettings.asrProfileId == "doubao", "fallback should preserve the selected recording ASR model")
    }

    private static func testRecordingAsrPayloadIncludesRecordingContext() throws {
        let settings = RecordingSettings(
            primaryAgentProfileId: "agent-1",
            deliverToAgent: false,
            prompt: "请分析这段录音",
            asrProfileId: "doubao"
        )

        let payload = AudioAsrPayload.recording(
            settings: settings,
            source: .phone,
            recordingId: "recording-1",
            recordingType: .meeting,
            prompt: "请分析这段录音"
        ).jsonObject

        try expect(payload["mode"] as? String == "router", "recording ASR should use router mode")
        try expect(payload["profile_id"] as? String == "doubao", "recording ASR should use the selected recording model")
        try expect(payload["recording_id"] as? String == "recording-1", "recording ASR should carry local recording id")
        try expect(payload["recording_type"] as? String == "meeting", "recording ASR should carry recording type")
        try expect(payload["intent"] as? String == "recording", "recording ASR should mark recording intent")
        try expect(payload["source"] as? String == "phone", "recording ASR should include source")
        try expect(payload["deliver_to_agent"] as? Bool == true, "processed recording types should be delivered to Agent")
        try expect(payload["agent_prompt"] as? String == "请分析这段录音", "recording ASR should carry custom prompt")
    }

    private static func testChatAsrPayloadOmitsRecordingContext() throws {
        let payload = AudioAsrPayload.chat(mode: "router", profileId: "doubao").jsonObject

        try expect(payload["mode"] as? String == "router", "chat ASR should preserve mode")
        try expect(payload["profile_id"] as? String == "doubao", "chat ASR should preserve profile id")
        try expect(payload["intent"] == nil, "chat ASR should not include recording intent")
        try expect(payload["source"] == nil, "chat ASR should not include recording source")
        try expect(payload["deliver_to_agent"] == nil, "chat ASR should not include recording delivery preference")
        try expect(payload["agent_prompt"] == nil, "chat ASR should not include recording prompt")
    }

    private static func testLongRecordingUploadRequestUsesHttpJobMetadata() throws {
        let settings = RecordingSettings(primaryAgentProfileId: "agent-1", asrProfileId: "doubao")
        let request = LongRecordingAsrJobRequest(
            recordingId: "recording-1",
            backendId: "backend-1",
            clientMessageId: "client-long-1",
            recordingType: .idea,
            source: .phone,
            prompt: RecordingSettings.ideaPrompt,
            settings: settings,
            fileSize: 123,
            sha256: "abc123"
        )
        let json = request.jsonObject

        try expect(json["recording_id"] as? String == "recording-1", "job request should include recording id")
        try expect(json["backend_id"] as? String == "backend-1", "job request should include backend id")
        try expect(json["client_message_id"] as? String == "client-long-1", "job request should include client message id")
        try expect(json["recording_type"] as? String == "idea", "job request should include recording type")
        try expect(json["agent_prompt"] as? String == RecordingSettings.ideaPrompt, "job request should include prompt")
        try expect(json["file_size"] as? Int == 123, "job request should include file size")
        try expect(json["sha256"] as? String == "abc123", "job request should include sha256")
        let asr = try unwrap(json["asr"] as? [String: Any], "job request should include ASR payload")
        try expect(asr["mode"] as? String == "router", "long recording ASR should use router mode")
        try expect(asr["profile_id"] as? String == "doubao", "long recording ASR should use selected ASR profile")
    }

    private static func testHeadsetDefaultFakeData() throws {
        let settings = HeadsetLocalSettings.defaultValue
        let expectedPresetIds = ["blues", "classical", "jazz", "hiphop", "pop"]
        let expectedShortcutIds = Set(
            HeadsetSideSelection.allCases.flatMap { side in
                HeadsetGestureSelection.allCases.map { gesture in
                    "\(side.rawValue)-\(gesture.rawValue)"
                }
            }
        )

        try expect(settings.devices.count == 1, "default fake data should include one headset")
        try expect(settings.devices[0].name == "A9 Ultra", "default headset should be A9 Ultra")
        try expect(settings.devices[0].isPaired, "default headset should be paired")
        try expect(settings.devices[0].leftBattery == 100, "default left battery should be 100")
        try expect(settings.devices[0].rightBattery == 100, "default right battery should be 100")
        try expect(settings.eqPresets.map(\.id) == expectedPresetIds, "default EQ presets should include requested genres")
        try expect(settings.eqPresets.allSatisfy { $0.bands.count == 5 }, "each EQ preset should include five frequency bands")
        try expect(Set(settings.shortcuts.map(\.id)) == expectedShortcutIds, "shortcuts should cover both ears and all gestures")
    }

    private static func testHeadsetSettingsAddsDemoDevice() throws {
        var settings = HeadsetLocalSettings.defaultValue

        settings.addDemoDevice()

        try expect(settings.devices.count == 2, "adding a demo headset should append one device")
        try expect(settings.selectedDeviceId == settings.devices[1].id, "new demo headset should become selected")
        try expect(settings.devices[1].name == "A9 Ultra 2", "new demo headset should use the next A9 Ultra name")
        try expect(!settings.devices[1].isPaired, "new demo headset should start unpaired")
        try expect(settings.devices[1].leftBattery == 100, "new demo left battery should be 100")
        try expect(settings.devices[1].rightBattery == 100, "new demo right battery should be 100")
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

    private static func testSettingsManagerClearsPairingWhenTokenChanges() throws {
        let defaults = try temporaryDefaults()
        let manager = SettingsManager(defaults: defaults)
        let pairedProfile = AgentProfile(
            id: "agent-token",
            platform: .openclaw,
            displayName: "OpenClaw",
            gatewayUrl: "wss://boson-tech.top/ws",
            backendId: "bk_openclaw",
            backendLabel: "OpenClaw",
            token: "good-token",
            isPaired: true
        )

        try expect(manager.saveProfile(pairedProfile), "paired profile should save")
        var editedProfile = manager.selectedProfile
        editedProfile.token = "wrong-token"
        editedProfile.isPaired = true

        try expect(manager.saveProfile(editedProfile), "edited profile should save")
        try expect(!manager.selectedProfile.isPaired, "changing the Agent token should clear stale pairing")
        try expect(manager.config.token == "wrong-token", "edited Agent token should be projected")
        try expect(manager.config.pairedBackendId == nil, "unpaired profile should not project paired backend")
    }

    private static func testSettingsManagerDoesNotProjectUnpairedBackendAsPaired() throws {
        let defaults = try temporaryDefaults()
        let manager = SettingsManager(defaults: defaults)
        let unpairedProfile = AgentProfile(
            id: "agent-unpaired",
            platform: .openclaw,
            displayName: "OpenClaw",
            gatewayUrl: "wss://boson-tech.top/ws",
            backendId: "bk_openclaw",
            backendLabel: "OpenClaw",
            token: "token",
            isPaired: false
        )

        try expect(manager.saveProfile(unpairedProfile), "unpaired configured profile should save")
        try expect(manager.selectedProfile.backendId == "bk_openclaw", "backend id should remain editable config")
        try expect(manager.config.pairedBackendId == nil, "backend id without isPaired should not be treated as paired")
        try expect(manager.config.pairedBackendLabel == nil, "unpaired backend should not project a paired label")
    }

    private static func testSettingsManagerMigratesMiniMaxKeyToCredentialVault() throws {
        let defaults = try temporaryDefaults()
        let vault = FakeCredentialVault()
        defaults.set("minimax", forKey: "tts_engine")
        defaults.set("legacy-minimax-key", forKey: "minimax_api_key")
        defaults.set("female_sunny_zh", forKey: "minimax_voice_id")

        let manager = SettingsManager(defaults: defaults, credentialVault: vault)

        try expect(vault.secret(for: localMiniMaxCredentialId) == "legacy-minimax-key", "legacy MiniMax key should migrate to credential vault")
        try expect(defaults.string(forKey: "minimax_api_key") == nil, "legacy MiniMax key should be removed from UserDefaults")
        try expect(manager.config.minimaxApiKey == "legacy-minimax-key", "runtime config should still resolve the local MiniMax key")

        guard let profileData = defaults.data(forKey: "agent_profiles_v1"),
              let rawProfiles = String(data: profileData, encoding: .utf8) else {
            throw TestFailure("agent profiles should persist")
        }
        try expect(!rawProfiles.contains("legacy-minimax-key"), "persisted agent profiles should not contain the local MiniMax key")
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

    private static func profile(id: String, name: String) -> AgentProfile {
        AgentProfile(
            id: id,
            platform: .hermes,
            displayName: name,
            gatewayUrl: "wss://example.com/ws",
            backendId: id,
            backendLabel: name,
            token: "",
            isPaired: true,
            asrMode: "router",
            asrProfileId: "",
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 100),
            isPinned: false,
            sortIndex: 0
        )
    }

    private static func recordingFixture(
        events: [RecordingEventItem],
        artifacts: [RecordingArtifactItem]
    ) -> RecordingItem {
        RecordingItem(
            id: "recording-fixture",
            agentId: "agent-1",
            createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            duration: 0,
            asrText: "转写文本",
            prompt: "录音 Prompt",
            recordingType: .meeting,
            processingStatus: .processing,
            fileURL: URL(fileURLWithPath: "/tmp/recording-fixture.wav"),
            source: .phone,
            events: events,
            artifacts: artifacts
        )
    }

    private static func artifactFixture(
        id: String,
        filename: String,
        relatedTaskId: String?
    ) -> RecordingArtifactItem {
        RecordingArtifactItem(
            id: id,
            filename: filename,
            mimeType: "text/markdown",
            fileURL: URL(fileURLWithPath: "/tmp/\(filename)"),
            sourceEventId: id,
            relatedTaskId: relatedTaskId,
            createdAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
    }

    private static func drainMainQueue() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
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

    private static func unwrap<T>(_ value: T?, _ message: String) throws -> T {
        guard let value else {
            throw TestFailure(message)
        }
        return value
    }
}

private struct TestFailure: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}

private final class FakeCredentialVault: CredentialVault {
    private var secrets: [String: String] = [:]

    func secret(for id: String) -> String? {
        secrets[id]
    }

    func setSecret(_ secret: String, for id: String) {
        secrets[id] = secret
    }

    func removeSecret(for id: String) {
        secrets.removeValue(forKey: id)
    }
}

private final class FakeAgentTaskRequestClient: AgentTaskRequestClient {
    let subject = PassthroughSubject<WsMessageEvent, Never>()
    var messageChannel: AnyPublisher<WsMessageEvent, Never> {
        subject.eraseToAnyPublisher()
    }

    private(set) var taskListRequests: [(requestId: String, backendId: String, includeDisabled: Bool)] = []

    func requestTaskList(requestId: String, backendId: String, includeDisabled: Bool) -> Bool {
        taskListRequests.append((requestId: requestId, backendId: backendId, includeDisabled: includeDisabled))
        return true
    }

    func createAgentTask(
        requestId: String,
        backendId: String,
        title: String,
        prompt: String,
        schedule: String?,
        enabled: Bool
    ) -> Bool {
        true
    }

    func updateAgentTask(
        requestId: String,
        backendId: String,
        taskId: String,
        title: String,
        prompt: String,
        schedule: String,
        enabled: Bool
    ) -> Bool {
        true
    }

    func deleteAgentTask(requestId: String, backendId: String, taskId: String) -> Bool {
        true
    }

    func requestApprovalHistory(requestId: String, backendId: String, limit: Int) -> Bool {
        true
    }
}
