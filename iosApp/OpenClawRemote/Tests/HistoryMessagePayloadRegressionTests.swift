import Foundation

@main
struct HistoryMessagePayloadRegressionTests {
    static func main() throws {
        try testChatMessagePrefersPayloadTimestampOverFallback()
        try testChatMessageFallsBackWhenPayloadTimestampIsMissing()
        try testTimestampParsesNumericHermesCreatedAt()
        print("HistoryMessagePayloadRegressionTests passed")
    }

    private static func testChatMessagePrefersPayloadTimestampOverFallback() throws {
        let message = HistoryMessagePayload.chatMessage(
            content: "hello",
            role: "assistant",
            item: [
                "content": "hello",
                "created_at": "2026-05-20T10:43:00.000Z",
            ],
            fallbackTimestamp: "09:30"
        )

        try expect(message.rawTimestamp == "2026-05-20T10:43:00.000Z", "payload timestamp should win over fallback")
        try expect(message.timestamp != "09:30", "display timestamp should not use app-open fallback when created_at exists")
    }

    private static func testChatMessageFallsBackWhenPayloadTimestampIsMissing() throws {
        let message = HistoryMessagePayload.chatMessage(
            content: "hello",
            role: "assistant",
            item: ["content": "hello"],
            fallbackTimestamp: "09:30"
        )

        try expect(message.rawTimestamp == "09:30", "live message should keep fallback when router omits timestamp")
        try expect(message.timestamp == "09:30", "display timestamp should match fallback when payload has no timestamp")
    }

    private static func testTimestampParsesNumericHermesCreatedAt() throws {
        let timestamp = HistoryMessagePayload.timestamp(from: ["createdAt": 1_779_273_780_000])

        try expect(timestamp == "2026-05-20T10:43:00.000Z", "numeric Hermes createdAt should normalize to ISO8601")
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
