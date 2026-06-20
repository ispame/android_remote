import Foundation

@main
struct CodexSessionModelTests {
    static func main() throws {
        try testProjectNameFallsBackToLastPathSegment()
        try testProjectNameFallsBackToChatForEmptyProject()
        try testTimeGroupingUsesExpectedBuckets()
        try testProjectGroupingSortsByRecentActivity()
        try testLatestAssistantPreviewFallsBackToPreview()
        print("CodexSessionModelTests passed")
    }

    private static func testProjectNameFallsBackToLastPathSegment() throws {
        let session = CodexSessionSummary(
            sessionId: "thread-1",
            title: "Fix router",
            preview: "",
            lastAssistantPreview: "",
            projectPath: "/Users/spame/WorkTable/openclaw_coder/boson",
            projectName: nil,
            createdAt: "2026-06-20T02:00:00Z",
            updatedAt: "2026-06-20T03:00:00Z",
            status: "idle",
            archived: false,
            model: "gpt-5"
        )

        try expect(session.displayProjectName == "boson", "project name should default to last cwd segment")
    }

    private static func testProjectNameFallsBackToChatForEmptyProject() throws {
        let session = CodexSessionSummary(
            sessionId: "thread-2",
            title: "Chat",
            preview: "",
            lastAssistantPreview: "",
            projectPath: "",
            projectName: "",
            createdAt: "2026-06-20T02:00:00Z",
            updatedAt: "2026-06-20T03:00:00Z",
            status: "idle",
            archived: false,
            model: nil
        )

        try expect(session.displayProjectName == "聊天", "empty project should be grouped as chat")
    }

    private static func testTimeGroupingUsesExpectedBuckets() throws {
        let now = date("2026-06-20T12:00:00Z")
        let groups = CodexSessionGrouping.groups(
            for: [
                sample("today", updatedAt: "2026-06-20T11:00:00Z"),
                sample("yesterday", updatedAt: "2026-06-19T10:00:00Z"),
                sample("four-days", updatedAt: "2026-06-16T10:00:00Z"),
                sample("last-week", updatedAt: "2026-06-10T10:00:00Z"),
                sample("two-weeks", updatedAt: "2026-06-03T10:00:00Z"),
                sample("last-month", updatedAt: "2026-05-20T10:00:00Z")
            ],
            mode: .time,
            now: now
        )

        try expect(groups.map(\.title) == ["今天", "昨天", "4天前", "上周", "2周前", "上个月"], "time grouping labels should match Codex UX")
    }

    private static func testProjectGroupingSortsByRecentActivity() throws {
        let groups = CodexSessionGrouping.groups(
            for: [
                sample("older-boson", projectName: "boson", updatedAt: "2026-06-19T09:00:00Z"),
                sample("newer-boson", projectName: "boson", updatedAt: "2026-06-20T09:00:00Z"),
                sample("android", projectName: "android_remote", updatedAt: "2026-06-20T08:00:00Z")
            ],
            mode: .project,
            now: date("2026-06-20T12:00:00Z")
        )

        try expect(groups.map(\.title) == ["boson", "android_remote"], "project groups should be ordered by latest session")
        try expect(groups[0].sessions.map(\.sessionId) == ["newer-boson", "older-boson"], "sessions in project should sort newest first")
    }

    private static func testLatestAssistantPreviewFallsBackToPreview() throws {
        let assistant = sample("assistant", preview: "user prompt", assistantPreview: "final model reply")
        let fallback = sample("fallback", preview: "conversation preview", assistantPreview: "")

        try expect(assistant.displayPreview == "final model reply", "assistant preview should win")
        try expect(fallback.displayPreview == "conversation preview", "preview should be fallback")
    }

    private static func sample(
        _ id: String,
        preview: String = "",
        assistantPreview: String = "",
        projectName: String? = "boson",
        updatedAt: String = "2026-06-20T10:00:00Z"
    ) -> CodexSessionSummary {
        CodexSessionSummary(
            sessionId: id,
            title: id,
            preview: preview,
            lastAssistantPreview: assistantPreview,
            projectPath: projectName == nil ? "" : "/tmp/\(projectName!)",
            projectName: projectName,
            createdAt: updatedAt,
            updatedAt: updatedAt,
            status: "idle",
            archived: false,
            model: nil
        )
    }

    private static func date(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso)!
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
