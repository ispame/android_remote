import Foundation

@main
struct LongRecordingAsrModelTests {
    static func main() throws {
        try testCompletedJobPayload()
        try testAudioLimits()
        print("LongRecordingAsrModelTests passed")
    }

    private static func testCompletedJobPayload() throws {
        guard let payload = LongRecordingAsrJobStatusPayload(json: [
            "job_id": "job-completed",
            "status": "completed",
            "phase": "completed",
            "upload_percent": 100,
            "asr_progress": ["percent": 100],
            "transcript": "完整转写文本",
            "retryable": false,
            "provider_status_code": "20000000",
            "provider_log_id": "provider-log",
            "delivery_status": "failed",
            "delivery_attempts": 2,
            "delivery_error": "Agent 未确认接收",
            "delivery_retryable": true,
            "delivered_at": NSNull(),
        ]) else {
            throw TestFailure("completed payload should parse")
        }
        try expect(payload.phase == "completed", "phase should parse")
        try expect(payload.transcript == "完整转写文本", "transcript should parse")
        try expect(payload.providerStatusCode == "20000000", "provider status should parse")
        try expect(payload.providerLogId == "provider-log", "provider log id should parse")
        try expect(payload.deliveryStatus == "failed", "delivery status should parse")
        try expect(payload.deliveryAttempts == 2, "delivery attempts should parse")
        try expect(payload.deliveryError == "Agent 未确认接收", "delivery error should parse")
        try expect(payload.deliveryRetryable, "delivery retryable should parse")
        try expect(payload.deliveredAt == nil, "null delivered timestamp should parse")
    }

    private static func testAudioLimits() throws {
        let valid = pcmWavHeader(dataSize: 16000 * 2 * 60)
        let metadata = try LongRecordingAudioValidator.validate(
            fileSize: valid.count + 16000 * 2 * 60,
            wavHeader: valid
        )
        try expect(metadata.durationSeconds == 60, "duration should be calculated from PCM bytes")

        try expectValidationError(.tooLarge) {
            try LongRecordingAudioValidator.validate(
                fileSize: LongRecordingAudioValidator.maxAudioBytes + 1,
                wavHeader: valid
            )
        }
        let tooLong = pcmWavHeader(dataSize: 16000 * 2 * 7201)
        try expectValidationError(.tooLong) {
            try LongRecordingAudioValidator.validate(
                fileSize: tooLong.count + 16000 * 2 * 7201,
                wavHeader: tooLong
            )
        }
    }

    private static func expectValidationError(
        _ expected: LongRecordingAudioValidationError,
        operation: () throws -> LongRecordingAudioMetadata
    ) throws {
        do {
            _ = try operation()
            throw TestFailure("expected validation failure")
        } catch let error as LongRecordingAudioValidationError {
            try expect(error == expected, "unexpected validation error: \(error)")
        }
    }

    private static func pcmWavHeader(dataSize: Int) -> Data {
        var data = Data(count: 44)
        data.replaceSubrange(0..<4, with: Data("RIFF".utf8))
        data.replaceSubrange(8..<12, with: Data("WAVE".utf8))
        data.replaceSubrange(12..<16, with: Data("fmt ".utf8))
        data.replaceSubrange(36..<40, with: Data("data".utf8))
        writeLittleEndian(UInt32(36 + dataSize), to: &data, at: 4)
        writeLittleEndian(UInt32(16), to: &data, at: 16)
        writeLittleEndian(UInt16(1), to: &data, at: 20)
        writeLittleEndian(UInt16(1), to: &data, at: 22)
        writeLittleEndian(UInt32(16000), to: &data, at: 24)
        writeLittleEndian(UInt32(32000), to: &data, at: 28)
        writeLittleEndian(UInt16(2), to: &data, at: 32)
        writeLittleEndian(UInt16(16), to: &data, at: 34)
        writeLittleEndian(UInt32(dataSize), to: &data, at: 40)
        return data
    }

    private static func writeLittleEndian<T: FixedWidthInteger>(_ value: T, to data: inout Data, at offset: Int) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { bytes in
            data.replaceSubrange(offset..<(offset + bytes.count), with: bytes)
        }
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw TestFailure(message) }
    }
}

private struct TestFailure: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}

struct GatewayAccountAgentProfile: Codable {
    var agentProfileId: String
    var platform: String
    var displayName: String
    var gatewayUrl: String
    var backendId: String
    var backendLabel: String?
    var isPaired: Bool
    var asrMode: String
    var pinned: Bool
    var sortOrder: Int
}
