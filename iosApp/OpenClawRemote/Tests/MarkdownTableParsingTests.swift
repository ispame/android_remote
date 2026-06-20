import Foundation

@main
struct MarkdownTableParsingTests {
    static func main() throws {
        try testMarkdownTableExportsMarkdownAndCsv()
        try testTableWithTwentyRowsShowsAllRows()
        try testTableWithMoreThanTwentyRowsDefaultsToFirstTwentyRows()
        try testFourColumnTablesFitInlinePreview()
        try testWiderTablesKeepScrollablePreview()
        try testNonTableTextIsNotParsedAsTable()
        print("MarkdownTableParsingTests passed")
    }

    private static func testMarkdownTableExportsMarkdownAndCsv() throws {
        let markdown = """
        三档：间接配套

        | 股票代码 | 公司名称 | 配套业务 |
        | --- | --- | --- |
        | 002475 | 立讯精密 | 高速连接器、液冷散热件 |
        | 605286 | 新亚电子 | 高速通讯线缆 |

        补充关键要点
        """

        let blocks = parseBlocks(markdown)
        guard blocks.count == 3 else {
            throw TestFailure("table text should split into text, table, text blocks")
        }
        guard case .table(let table) = blocks[1] else {
            throw TestFailure("middle block should be a table")
        }

        try expect(table.headers == ["股票代码", "公司名称", "配套业务"], "table headers should parse")
        try expect(table.rows.count == 2, "table rows should parse")
        try expect(
            table.markdownSource.contains("| 002475 | 立讯精密 | 高速连接器、液冷散热件 |"),
            "markdown export should preserve cells"
        )
        try expect(
            table.csvSource == "股票代码,公司名称,配套业务\n002475,立讯精密,高速连接器、液冷散热件\n605286,新亚电子,高速通讯线缆",
            "csv export should use comma separated rows"
        )
    }

    private static func testTableWithTwentyRowsShowsAllRows() throws {
        let table = MarkdownTable(
            headers: ["股票代码", "公司名称"],
            rows: (1...20).map { ["00\($0)", "公司\($0)"] }
        )

        try expect(!table.shouldFoldRows, "20-row table should not show a table fold control")
        try expect(table.visibleRows(isExpanded: false).count == 20, "20-row table should show all rows")
    }

    private static func testTableWithMoreThanTwentyRowsDefaultsToFirstTwentyRows() throws {
        let table = MarkdownTable(
            headers: ["股票代码", "公司名称"],
            rows: (1...21).map { ["00\($0)", "公司\($0)"] }
        )

        try expect(table.shouldFoldRows, "21-row table should show a table fold control")
        try expect(table.visibleRows(isExpanded: false).count == 20, "21-row table should default to 20 visible rows")
        try expect(table.visibleRows(isExpanded: true).count == 21, "expanded table should show every row")
    }

    private static func testFourColumnTablesFitInlinePreview() throws {
        let table = MarkdownTable(
            headers: ["", "名称", "调度", "下次"],
            rows: [
                ["1", "美股早报", "每天 8:00", "6/21 周日"],
                ["2", "杭州早安天气", "每天 7:55", "6/21 7:55"]
            ]
        )

        try expect(table.shouldFitInlineColumns, "four-column task tables should fit within the inline conversation preview")
    }

    private static func testWiderTablesKeepScrollablePreview() throws {
        let table = MarkdownTable(
            headers: ["A", "B", "C", "D", "E"],
            rows: [["1", "2", "3", "4", "5"]]
        )

        try expect(!table.shouldFitInlineColumns, "wide tables should keep horizontal scrolling instead of over-compressing columns")
    }

    private static func testNonTableTextIsNotParsedAsTable() throws {
        let blocks = parseBlocks("普通说明：A | B 不是表格，因为没有分隔行。")
        guard blocks.count == 1, case .text = blocks[0] else {
            throw TestFailure("non-table text should remain a text block")
        }
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
