package com.openclaw.remote.data

data class CodexSessionSummary(
    val sessionId: String,
    val title: String = "",
    val preview: String = "",
    val lastAssistantPreview: String = "",
    val projectPath: String = "",
    val projectName: String? = null,
    val createdAt: String = "",
    val updatedAt: String = "",
    val status: String = "",
    val archived: Boolean = false,
    val model: String? = null,
) {
    val displayTitle: String
        get() = title.trim().ifEmpty { "未命名会话" }

    val displayPreview: String
        get() = lastAssistantPreview.trim().ifEmpty {
            preview.trim().ifEmpty { "暂无回复" }
        }

    val displayProjectName: String
        get() {
            projectName?.trim()?.takeIf { it.isNotEmpty() }?.let { return it }
            val normalizedPath = projectPath.trim().trimEnd('/')
            if (normalizedPath.isEmpty()) return "聊天"
            return normalizedPath.substringAfterLast('/').ifBlank { "聊天" }
        }

    val updatedEpochDay: Int
        get() = codexEpochDayFromIso(updatedAt).takeIf { it > 0 }
            ?: codexEpochDayFromIso(createdAt)
}

enum class CodexSessionGroupingMode {
    TIME,
    PROJECT,
}

data class CodexSessionGroup(
    val title: String,
    val sessions: List<CodexSessionSummary>,
)

fun groupCodexSessions(
    sessions: List<CodexSessionSummary>,
    mode: CodexSessionGroupingMode,
    nowEpochDay: Int = (currentTimestampMillis() / 86_400_000L).toInt(),
): List<CodexSessionGroup> {
    val sorted = sessions.sortedByDescending { it.updatedAt.ifBlank { it.createdAt } }
    return when (mode) {
        CodexSessionGroupingMode.TIME -> sorted
            .groupBy { codexTimeBucket(it.updatedEpochDay, nowEpochDay) }
            .map { (title, groupSessions) -> CodexSessionGroup(title, groupSessions) }
        CodexSessionGroupingMode.PROJECT -> sorted
            .groupBy { it.displayProjectName }
            .map { (title, groupSessions) ->
                CodexSessionGroup(title, groupSessions.sortedByDescending { it.updatedAt.ifBlank { it.createdAt } })
            }
            .sortedWith(
                compareByDescending<CodexSessionGroup> { group ->
                    group.sessions.firstOrNull()?.updatedAt.orEmpty()
                }.thenBy { it.title }
            )
    }
}

fun codexEpochDayFromIso(iso: String): Int {
    val date = iso.trim().take(10)
    if (date.length != 10) return 0
    val year = date.substring(0, 4).toIntOrNull() ?: return 0
    val month = date.substring(5, 7).toIntOrNull() ?: return 0
    val day = date.substring(8, 10).toIntOrNull() ?: return 0
    return daysFromCivil(year, month, day)
}

private fun codexTimeBucket(epochDay: Int, nowEpochDay: Int): String {
    val diff = (nowEpochDay - epochDay).coerceAtLeast(0)
    return when (diff) {
        0 -> "今天"
        1 -> "昨天"
        in 2..6 -> "${diff}天前"
        in 7..13 -> "上周"
        in 14..30 -> "${diff / 7}周前"
        else -> "上个月"
    }
}

private fun daysFromCivil(year: Int, month: Int, day: Int): Int {
    var y = year
    var m = month
    y -= if (m <= 2) 1 else 0
    val era = floorDiv(y, 400)
    val yearOfEra = y - era * 400
    m += if (m > 2) -3 else 9
    val dayOfYear = (153 * m + 2) / 5 + day - 1
    val dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
    return era * 146097 + dayOfEra - 719468
}

private fun floorDiv(value: Int, divisor: Int): Int {
    var result = value / divisor
    if ((value xor divisor) < 0 && result * divisor != value) {
        result--
    }
    return result
}
