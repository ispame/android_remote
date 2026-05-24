package com.openclaw.remote.rich

import kotlin.math.ceil

data class RichApprovalRequest(
    val title: String = "危险命令审批",
    val command: String,
    val reason: String,
    val codeLines: List<String>,
) {
    val lineCount: Int
        get() = codeLines.size

    val commandPreview: String
        get() = codeLines.take(4).joinToString("\n")
}

data class RichMarkdownTable(
    val headers: List<String>,
    val rows: List<List<String>>,
) {
    fun toMarkdown(): String {
        val allRows = listOf(headers) + rows
        return allRows.mapIndexed { index, row ->
            val cells = normalizeTableRow(row, headers.size).map { it.replace("\n", " ") }
            val line = "| ${cells.joinToString(" | ")} |"
            if (index == 0) {
                val separator = "| ${List(headers.size) { "---" }.joinToString(" | ")} |"
                "$line\n$separator"
            } else {
                line
            }
        }.joinToString("\n")
    }

    fun toCsv(): String {
        return (listOf(headers) + rows)
            .joinToString("\n") { row ->
                normalizeTableRow(row, headers.size)
                    .joinToString(",") { it.csvEscaped() }
            }
    }

    fun columnCharacterWidths(min: Int = 8, max: Int = 20): List<Int> {
        val rowSet = listOf(headers) + rows
        return headers.indices.map { columnIndex ->
            rowSet.maxOfOrNull { row ->
                row.getOrNull(columnIndex)?.length ?: 0
            }
                ?.let { ceil(it * 1.2).toInt() }
                ?.coerceIn(min, max)
                ?: min
        }
    }
}

data class ApprovalHandledResult(
    val allowed: Boolean,
    val handledKeys: Set<String>,
)

sealed class RichMessageBlock {
    data class Text(val value: String) : RichMessageBlock()
    data class Table(val table: RichMarkdownTable) : RichMessageBlock()
}

fun detectApprovalRequest(content: String): RichApprovalRequest? {
    val lowercased = content.lowercase()
    if (!lowercased.contains("/approve") ||
        !lowercased.contains("/deny") ||
        !containsApprovalCue(lowercased)
    ) {
        return null
    }

    val command = extractCommand(content)
    return RichApprovalRequest(
        command = command,
        reason = extractReason(content),
        codeLines = if (command.isBlank()) emptyList() else command.split("\n"),
    )
}

fun markApprovalHandledIfAllowed(
    handledKeys: Set<String>,
    messageKey: String,
): ApprovalHandledResult {
    if (messageKey in handledKeys) {
        return ApprovalHandledResult(allowed = false, handledKeys = handledKeys)
    }
    return ApprovalHandledResult(allowed = true, handledKeys = handledKeys + messageKey)
}

fun parseRichMessageBlocks(text: String): List<RichMessageBlock> {
    val lines = text.lines()
    val blocks = mutableListOf<RichMessageBlock>()
    val buffer = mutableListOf<String>()
    var index = 0

    fun flushText() {
        if (buffer.isNotEmpty()) {
            blocks += RichMessageBlock.Text(buffer.joinToString("\n"))
            buffer.clear()
        }
    }

    while (index < lines.size) {
        val table = parseTable(lines, index)
        if (table != null) {
            flushText()
            blocks += RichMessageBlock.Table(table.first)
            index = table.second
        } else {
            buffer += lines[index]
            index += 1
        }
    }
    flushText()
    return blocks
}

private fun containsApprovalCue(lowercasedContent: String): Boolean {
    return listOf(
        "dangerous command requires approval",
        "requires approval",
        "approval required",
        "needs approval",
        "需要审批",
        "需要批准",
        "需要确认",
        "需要授权",
        "危险命令",
        "审批",
        "批准",
        "拒绝",
    ).any { lowercasedContent.contains(it) }
}

private fun extractCommand(content: String): String {
    extractFencedCodeBlock(content)?.let { return it }

    val lines = content.lines()
    for (line in lines) {
        val trimmed = line.trim()
        if (trimmed.isEmpty()) continue
        commandAfterLabel(trimmed)?.let { return it }
    }

    for (line in lines) {
        val trimmed = line.trim()
        if (looksLikeCommandLine(trimmed)) return trimmed
    }

    return ""
}

private fun extractFencedCodeBlock(content: String): String? {
    val lines = content.lines()
    val collected = mutableListOf<String>()
    var collecting = false

    for (line in lines) {
        val trimmed = line.trim()
        if (trimmed.startsWith("```")) {
            if (collecting) {
                return collected.joinToString("\n").trim().ifEmpty { null }
            }
            collecting = true
            collected.clear()
            continue
        }
        if (collecting) {
            collected += line
        }
    }

    return null
}

private fun commandAfterLabel(line: String): String? {
    val labels = listOf("命令：", "命令:", "Command:", "command:", "Terminal:", "terminal:")
    for (label in labels) {
        if (line.startsWith(label)) {
            return line.removePrefix(label).trim().stripWrappingQuotes().ifEmpty { null }
        }
    }
    return null
}

private fun String.stripWrappingQuotes(): String {
    if (length < 2) return this
    val first = first()
    val last = last()
    return if ((first == '"' && last == '"') || (first == '\'' && last == '\'')) {
        drop(1).dropLast(1)
    } else {
        this
    }
}

private fun looksLikeCommandLine(line: String): Boolean {
    val lowercased = line.lowercase()
    if (isActionLine(lowercased) ||
        lowercased.startsWith("reason:") ||
        lowercased.startsWith("原因：") ||
        lowercased.startsWith("原因:")
    ) {
        return false
    }

    val prefixes = listOf(
        "curl ", "wget ", "rm ", "sudo ", "python ", "python3 ", "node ", "npm ", "pnpm ",
        "yarn ", "git ", "docker ", "kubectl ", "ssh ", "scp ", "brew ", "chmod ", "chown ",
        "mv ", "cp ", "cat ", "bash ", "sh ", "cd ", "echo ",
    )
    return prefixes.any { lowercased.startsWith(it) }
}

private fun extractReason(content: String): String {
    val collected = mutableListOf<String>()
    var collecting = false

    for (line in content.lines()) {
        val trimmed = line.trim()
        val lowercased = trimmed.lowercase()

        if (collecting) {
            if (trimmed.isEmpty()) {
                if (collected.isEmpty()) continue
                break
            }
            if (isActionLine(lowercased) || lowercased.startsWith("```")) break
            collected += trimmed
            continue
        }

        val reason = reasonAfterLabel(trimmed)
        if (reason != null) {
            if (reason.isNotEmpty()) {
                collected += reason
            }
            collecting = true
        }
    }

    return collected.joinToString("\n").trim()
}

private fun reasonAfterLabel(line: String): String? {
    val labels = listOf("Reason:", "reason:", "原因：", "原因:", "理由：", "理由:")
    for (label in labels) {
        if (line.startsWith(label)) {
            return line.removePrefix(label).trim()
        }
    }
    return null
}

private fun isActionLine(lowercasedLine: String): Boolean {
    return lowercasedLine.startsWith("/approve") || lowercasedLine.startsWith("/deny")
}

private fun parseTable(lines: List<String>, start: Int): Pair<RichMarkdownTable, Int>? {
    if (start + 1 >= lines.size) return null
    val header = splitTableRow(lines[start])
    if (header.size < 2 || !isSeparatorRow(lines[start + 1])) return null

    val rows = mutableListOf<List<String>>()
    var index = start + 2
    while (index < lines.size) {
        val row = splitTableRow(lines[index])
        if (row.size < 2) break
        rows += normalizeTableRow(row, header.size)
        index += 1
    }

    return RichMarkdownTable(headers = header, rows = rows) to index
}

private fun splitTableRow(line: String): List<String> {
    var trimmed = line.trim()
    if (!trimmed.contains("|")) return emptyList()
    if (trimmed.startsWith("|")) trimmed = trimmed.drop(1)
    if (trimmed.endsWith("|")) trimmed = trimmed.dropLast(1)
    return trimmed.split("|").map { it.trim() }
}

private fun isSeparatorRow(line: String): Boolean {
    val cells = splitTableRow(line)
    if (cells.size < 2) return false
    return cells.all { cell ->
        val stripped = cell.replace(":", "")
        stripped.length >= 3 && stripped.all { it == '-' }
    }
}

private fun normalizeTableRow(row: List<String>, width: Int): List<String> {
    return when {
        row.size == width -> row
        row.size > width -> row.take(width)
        else -> row + List(width - row.size) { "" }
    }
}

private fun String.csvEscaped(): String {
    val normalized = replace("\r\n", "\n")
    val needsEscaping = normalized.contains(",") || normalized.contains("\"") || normalized.contains("\n")
    if (!needsEscaping) return normalized
    return "\"${normalized.replace("\"", "\"\"")}\""
}
