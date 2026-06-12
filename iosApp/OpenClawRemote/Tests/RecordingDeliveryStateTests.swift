import Foundation

@main
struct RecordingDeliveryStateTests {
    static func main() throws {
        let suiteName = "RecordingDeliveryStateTests-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw TestFailure("unable to create test defaults")
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RecordingDeliveryStateTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = RecordingStore(defaults: defaults, documentsDirectory: directory)
        let recording = try store.createRecording(
            agentId: "agent-1",
            audioData: Data([0x01]),
            recordingType: .meeting
        )
        store.configureRecordingForProcessing(
            recordingId: recording.id,
            type: .meeting,
            prompt: RecordingSettings.meetingPrompt,
            clientMessageId: "client-delivery-1"
        )

        store.applyLongRecordingAsrJob(
            try payload(
                recordingId: recording.id,
                deliveryStatus: "pending",
                attempts: 0,
                error: "Agent 当前离线",
                retryable: true
            ),
            fallbackRecordingId: recording.id
        )
        var saved = try require(store.items.first(where: { $0.id == recording.id }))
        try expect(saved.asrText == "会议转写", "ASR transcript should be retained")
        try expect(saved.agentDeliveryStatus == .pending, "delivery should remain pending")
        try expect(saved.processingStatus == .processing, "pending delivery should remain processing")

        store.applyLongRecordingAsrJob(
            try payload(
                recordingId: recording.id,
                deliveryStatus: "delivered",
                attempts: 1,
                retryable: false
            ),
            fallbackRecordingId: recording.id
        )
        saved = try require(store.items.first(where: { $0.id == recording.id }))
        try expect(saved.agentDeliveryStatus == .delivered, "Agent acknowledgement should be retained")
        try expect(saved.processingStatus == .completed, "Agent acknowledgement should complete processing")
        try expect(saved.events.contains { $0.kind == .delivered }, "delivery event should be recorded")
        try expect(saved.events.filter { $0.kind == .asr }.count == 1, "repeated completed polling should not duplicate ASR events")

        let reloaded = RecordingStore(defaults: defaults, documentsDirectory: directory)
        let restored = try require(reloaded.items.first(where: { $0.id == recording.id }))
        try expect(restored.agentDeliveryStatus == .delivered, "delivery status should survive restart")
        print("RecordingDeliveryStateTests passed")
    }

    private static func payload(
        recordingId: String,
        deliveryStatus: String,
        attempts: Int,
        error: String? = nil,
        retryable: Bool
    ) throws -> LongRecordingAsrJobStatusPayload {
        var json: [String: Any] = [
            "job_id": "job-delivery-1",
            "recording_id": recordingId,
            "status": "completed",
            "phase": "completed",
            "upload_percent": 100,
            "asr_progress": ["percent": 100],
            "transcript": "会议转写",
            "delivery_status": deliveryStatus,
            "delivery_attempts": attempts,
            "delivery_retryable": retryable,
        ]
        if let error {
            json["delivery_error"] = error
        }
        return try require(LongRecordingAsrJobStatusPayload(json: json))
    }

    private static func require<T>(_ value: T?) throws -> T {
        guard let value else { throw TestFailure("required value was nil") }
        return value
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw TestFailure(message) }
    }
}

private struct TestFailure: Error {
    let message: String

    init(_ message: String) {
        self.message = message
    }
}
