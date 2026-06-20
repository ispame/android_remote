import Foundation

@main
struct MarkdownTableLayoutTests {
    static func main() throws {
        try testInlineTablesUseFittedColumnsWhenPossible()
        try testScrollableTablesPreserveIntrinsicGridSize()
        try testFullscreenTablesPreserveIntrinsicGridSize()
        print("MarkdownTableLayoutTests passed")
    }

    private static func testInlineTablesUseFittedColumnsWhenPossible() throws {
        let source = try readSource("iosApp/OpenClawRemote/Sources/MessageBubbleView.swift")
        try expect(
            source.contains("if table.shouldFitInlineColumns") &&
                source.contains("fitsWidth: true"),
            "inline conversation tables with up to four columns should fit columns to the message bubble"
        )
    }

    private static func testScrollableTablesPreserveIntrinsicGridSize() throws {
        let source = try readSource("iosApp/OpenClawRemote/Sources/MessageBubbleView.swift")
        try expect(
            source.contains(".fixedSize(horizontal: true, vertical: true)"),
            "scrollable inline tables should preserve the full grid size so rows are not clipped"
        )
    }

    private static func testFullscreenTablesPreserveIntrinsicGridSize() throws {
        let source = try readSource("iosApp/OpenClawRemote/Sources/MainScreenView.swift")
        try expect(
            source.contains(".fixedSize(horizontal: true, vertical: true)") &&
                source.contains("minWidth: geometry.size.width") &&
                source.contains("minHeight: geometry.size.height"),
            "fullscreen tables should keep full grid size and start at the top-left of the viewport"
        )
    }

    private static func readSource(_ relativePath: String) throws -> String {
        let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
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
