import Foundation

@main
struct MessageContentAnalysisTests {
    static func main() throws {
        try testTenLinesAreNotCollapsed()
        try testElevenLinesAreCollapsed()
        try testTwentyRowMarkdownTableIsNotCollapsedByMessageAnalysis()
        try testLongMarkdownTableIsNotCollapsedByMessageAnalysis()
        print("MessageContentAnalysisTests passed")
    }

    private static func testTenLinesAreNotCollapsed() throws {
        let text = (1...10).map { "line \($0)" }.joined(separator: "\n")
        let analysis = analyzeMessageContent(text)

        try expect(analysis.kind == .normal, "10-line message should not collapse")
    }

    private static func testElevenLinesAreCollapsed() throws {
        let text = (1...11).map { "line \($0)" }.joined(separator: "\n")
        let analysis = analyzeMessageContent(text)

        try expect(analysis.kind == .longText, "11-line message should collapse")
    }

    private static func testTwentyRowMarkdownTableIsNotCollapsedByMessageAnalysis() throws {
        let table = markdownTable(rowCount: 20)
        let analysis = analyzeMessageContent(table)

        try expect(analysis.kind == .normal, "20-row markdown table should not be truncated by message analysis")
    }

    private static func testLongMarkdownTableIsNotCollapsedByMessageAnalysis() throws {
        let table = markdownTable(rowCount: 21)
        let analysis = analyzeMessageContent(table)

        try expect(analysis.kind == .normal, "long markdown table should be handled by table row folding, not message analysis")
    }

    private static func markdownTable(rowCount: Int) -> String {
        let rows = (1...rowCount)
            .map { "| \($0) | 公司\($0) | 业务\($0) |" }
            .joined(separator: "\n")
        return """
        | 股票代码 | 公司名称 | 配套业务 |
        | --- | --- | --- |
        \(rows)
        """
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
