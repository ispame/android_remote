import Foundation

@main
struct MarkdownTableParsingTests {
    static func main() throws {
        try testMarkdownTableExportsMarkdownAndCsv()
        try testTableWithTenRowsShowsAllRows()
        try testTableWithMoreThanTenRowsDefaultsToFirstTenRows()
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

    private static func testTableWithTenRowsShowsAllRows() throws {
        let table = MarkdownTable(
            headers: ["股票代码", "公司名称"],
            rows: (1...10).map { ["00\($0)", "公司\($0)"] }
        )

        try expect(!table.shouldFoldRows, "10-row table should not show a table fold control")
        try expect(table.visibleRows(isExpanded: false).count == 10, "10-row table should show all rows")
    }

    private static func testTableWithMoreThanTenRowsDefaultsToFirstTenRows() throws {
        let table = MarkdownTable(
            headers: ["股票代码", "公司名称"],
            rows: (1...11).map { ["00\($0)", "公司\($0)"] }
        )

        try expect(table.shouldFoldRows, "11-row table should show a table fold control")
        try expect(table.visibleRows(isExpanded: false).count == 10, "11-row table should default to 10 visible rows")
        try expect(table.visibleRows(isExpanded: true).count == 11, "expanded table should show every row")
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
