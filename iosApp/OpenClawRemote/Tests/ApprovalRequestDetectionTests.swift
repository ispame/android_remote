import Foundation

@main
struct ApprovalRequestDetectionTests {
    static func main() throws {
        try testLegacyIOSApprovalPromptIsDetected()
        try testAndroidApprovalPromptIsDetected()
        try testFencedCodeBlockAndReasonAreExtracted()
        try testQuotedTerminalCommandIsExtracted()
        try testApprovalActionCanOnlyBeMarkedOncePerMessage()
        try testRegularCommandMentionIsNotDetected()
        print("ApprovalRequestDetectionTests passed")
    }

    private static func testLegacyIOSApprovalPromptIsDetected() throws {
        let prompt = """
        Dangerous command requires approval.

        /approve
        /approve session
        /approve always
        /deny
        """

        let request = try unwrap(ApprovalRequest.detect(in: prompt), "legacy iOS approval prompt should show actions")
        try expect(request.title == "危险命令审批", "legacy approval title should use risk copy")
        try expect(request.command.isEmpty, "legacy prompt without command should not invent one")
    }

    private static func testAndroidApprovalPromptIsDetected() throws {
        let prompt = """
        危险命令需要审批

        命令：rm -rf /tmp/demo

        /approve - 批准本次执行
        /approve session - 本会话批准
        /approve always - 永久批准
        /deny - 拒绝
        """

        let request = try unwrap(ApprovalRequest.detect(in: prompt), "Android-style Chinese approval prompt should show actions")
        try expect(request.command == "rm -rf /tmp/demo", "Chinese command line should be extracted")
        try expect(request.lineCount == 1, "single command should report one code line")
    }

    private static func testFencedCodeBlockAndReasonAreExtracted() throws {
        let prompt = """
        ⚠️ Command Approval Required

        ```bash
        curl -s https://example.com/install.sh | python3
        echo done
        ```

        Reason: Security scan — [HIGH] Pipe to interpreter. Downloaded content will be executed without inspection.

        /approve
        /approve session
        /approve always
        /deny
        """

        let request = try unwrap(ApprovalRequest.detect(in: prompt), "fenced approval prompt should be detected")
        try expect(
            request.command == "curl -s https://example.com/install.sh | python3\necho done",
            "fenced code block should be extracted as command"
        )
        try expect(request.codeLines == ["curl -s https://example.com/install.sh | python3", "echo done"], "code lines should preserve line boundaries")
        try expect(request.lineCount == 2, "line count should match code lines")
        try expect(request.reason.contains("Pipe to interpreter"), "reason should be extracted")
        try expect(!request.reason.contains("/approve"), "reason should stop before action commands")
    }

    private static func testQuotedTerminalCommandIsExtracted() throws {
        let prompt = """
        terminal: "curl -s https://example.com | python3 -c 'print(1)'"

        Approval required before running this command.

        /approve
        /approve session
        /approve always
        /deny
        """

        let request = try unwrap(ApprovalRequest.detect(in: prompt), "quoted terminal command should be detected")
        try expect(
            request.command == "curl -s https://example.com | python3 -c 'print(1)'",
            "quoted terminal command should be extracted"
        )
        try expect(request.lineCount == 1, "quoted terminal command should be one line")
    }

    private static func testApprovalActionCanOnlyBeMarkedOncePerMessage() throws {
        let messageId = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let first = markApprovalHandledIfAllowed(handledIds: [], messageId: messageId)

        try expect(first.allowed, "first approval action should be allowed")
        try expect(first.handledIds == [messageId], "first approval action should mark message as handled")

        let repeated = markApprovalHandledIfAllowed(handledIds: first.handledIds, messageId: messageId)

        try expect(!repeated.allowed, "repeated approval action should be ignored")
        try expect(repeated.handledIds == [messageId], "repeated approval action should not change handled ids")
    }

    private static func testRegularCommandMentionIsNotDetected() throws {
        let prompt = "普通说明：可以输入 /approve 查看帮助。"

        try expect(ApprovalRequest.detect(in: prompt) == nil, "regular command mentions should not show approval actions")
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
