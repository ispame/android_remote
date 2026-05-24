package com.openclaw.remote.rich

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

class RichMessageParserTest {
    @Test
    fun approvalRequestExtractsFencedCodeAndReason() {
        val prompt = """
            Command Approval Required

            ```bash
            curl -s https://example.com/install.sh | python3
            echo done
            ```

            Reason: Security scan - [HIGH] Pipe to interpreter. Downloaded content will be executed without inspection.

            /approve
            /approve session
            /approve always
            /deny
        """.trimIndent()

        val request = assertNotNull(detectApprovalRequest(prompt))

        assertEquals("危险命令审批", request.title)
        assertEquals("curl -s https://example.com/install.sh | python3\necho done", request.command)
        assertEquals(listOf("curl -s https://example.com/install.sh | python3", "echo done"), request.codeLines)
        assertEquals(2, request.lineCount)
        assertTrue(request.reason.contains("Pipe to interpreter"))
        assertFalse(request.reason.contains("/approve"))
    }

    @Test
    fun approvalRequestExtractsChineseCommandLine() {
        val prompt = """
            危险命令需要审批

            命令：rm -rf /tmp/demo

            /approve - 批准本次执行
            /approve session - 本会话批准
            /approve always - 永久批准
            /deny - 拒绝
        """.trimIndent()

        val request = assertNotNull(detectApprovalRequest(prompt))

        assertEquals("rm -rf /tmp/demo", request.command)
        assertEquals(1, request.lineCount)
    }

    @Test
    fun regularCommandMentionIsNotApproval() {
        assertEquals(null, detectApprovalRequest("普通说明：可以输入 /approve 查看帮助。"))
    }

    @Test
    fun markdownTableExportsMarkdownAndCsv() {
        val markdown = """
            三档：间接配套

            | 股票代码 | 公司名称 | 配套业务 |
            | --- | --- | --- |
            | 002475 | 立讯精密 | 高速连接器、液冷散热件 |
            | 605286 | 新亚电子 | 高速通讯线缆 |

            补充关键要点
        """.trimIndent()

        val blocks = parseRichMessageBlocks(markdown)
        assertEquals(3, blocks.size)
        val table = (blocks[1] as RichMessageBlock.Table).table

        assertEquals(listOf("股票代码", "公司名称", "配套业务"), table.headers)
        assertEquals(2, table.rows.size)
        assertTrue(table.toMarkdown().contains("| 002475 | 立讯精密 | 高速连接器、液冷散热件 |"))
        assertEquals(
            "股票代码,公司名称,配套业务\n002475,立讯精密,高速连接器、液冷散热件\n605286,新亚电子,高速通讯线缆",
            table.toCsv(),
        )
    }

    @Test
    fun markdownTableColumnWidthsAreStablePerColumn() {
        val table = RichMarkdownTable(
            headers = listOf("股票代码", "公司名称", "配套业务"),
            rows = listOf(
                listOf("002475", "立讯精密", "高速连接器、液冷散热件"),
                listOf("605286", "新亚电子", "高速通讯线缆"),
            ),
        )

        val widths = table.columnCharacterWidths(min = 8, max = 18)

        assertEquals(listOf(8, 8, 14), widths)
    }

    @Test
    fun approvalActionCanOnlyBeMarkedOncePerMessage() {
        val result = markApprovalHandledIfAllowed(
            handledKeys = emptySet(),
            messageKey = "message-1",
        )

        assertTrue(result.allowed)
        assertEquals(setOf("message-1"), result.handledKeys)

        val repeated = markApprovalHandledIfAllowed(
            handledKeys = result.handledKeys,
            messageKey = "message-1",
        )

        assertFalse(repeated.allowed)
        assertEquals(setOf("message-1"), repeated.handledKeys)
    }

    @Test
    fun nonTableTextRemainsTextBlock() {
        val blocks = parseRichMessageBlocks("普通说明：A | B 不是表格，因为没有分隔行。")

        assertEquals(1, blocks.size)
        assertTrue(blocks.single() is RichMessageBlock.Text)
    }
}
