import Foundation

@main
struct HistoryMessagePayloadRegressionTests {
    static func main() throws {
        try testChatMessagePrefersPayloadTimestampOverFallback()
        try testChatMessageFallsBackWhenPayloadTimestampIsMissing()
        try testTimestampParsesNumericHermesCreatedAt()
        try testChatMessageParsesCollapsedTraceItems()
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

    private static func testChatMessageParsesCollapsedTraceItems() throws {
        let message = HistoryMessagePayload.chatMessage(
            content: "系统盘使用率 90%。",
            role: "assistant",
            item: [
                "timestamp": "2026-05-20T10:43:00.000Z",
                "trace": [
                    [
                        "trace_id": "trace-1",
                        "kind": "tool_call",
                        "title": "Tool call: shell",
                        "content": "{\"cmd\":\"df -h\"}",
                        "timestamp": "2026-05-20T10:42:59.000Z",
                    ],
                    [
                        "trace_id": "trace-2",
                        "kind": "tool_result",
                        "title": "Tool result",
                        "content": "/dev/disk3s1 90%",
                    ],
                ],
            ]
        )

        try expect(message.trace.count == 2, "history trace should be parsed into the chat message")
        try expect(message.trace[0].kind == .toolCall, "tool_call trace kind should decode")
        try expect(message.trace[0].title == "Tool call: shell", "trace title should decode")
        try expect(message.trace[1].kind == .toolResult, "tool_result trace kind should decode")
        try expect(message.trace[1].content.contains("90%"), "trace content should decode")
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
