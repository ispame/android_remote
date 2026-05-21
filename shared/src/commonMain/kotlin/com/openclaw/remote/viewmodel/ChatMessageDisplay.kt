package com.openclaw.remote.viewmodel

import com.openclaw.remote.data.ChatMessage
import com.openclaw.remote.data.MessageStatus
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.text.ParseException
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import java.util.TimeZone

private val replyToPrefixPattern = Regex(
    pattern = "^\\s*\\[\\[reply_to(?:_current| current)]]\\s*",
    options = setOf(RegexOption.IGNORE_CASE),
)

internal data class HistoryMergeResult(
    val messages: List<ChatMessage>,
    val loadedHistoryKeys: Set<String>,
)

internal fun historyChatMessage(
    content: String,
    role: String,
    rawTimestamp: String,
): ChatMessage {
    val senderId = when (role.lowercase()) {
        "user", "human" -> "user"
        else -> "assistant"
    }
    return ChatMessage(
        content = content,
        timestamp = displayTimestamp(rawTimestamp),
        senderId = senderId,
        rawTimestamp = rawTimestamp,
    )
}

internal fun chatMessageFromPayload(
    content: String,
    role: String,
    item: JsonObject,
    fallbackTimestamp: String = "",
): ChatMessage {
    val rawTimestamp = historyTimestamp(item).ifBlank { fallbackTimestamp.trim() }
    return historyChatMessage(content, role, rawTimestamp)
}

internal fun historyTimestamp(item: JsonObject): String =
    listOf("timestamp", "created_at", "createdAt", "sent_at", "sentAt", "message_time", "messageTime", "time")
        .firstNotNullOfOrNull { key -> normalizedTimestampValue(item[key]) }
        ?: ""

internal fun sanitizeAssistantContent(content: String): String =
    replyToPrefixPattern.replaceFirst(content, "").trim()

internal fun ChatMessage.sanitizedForDisplay(): ChatMessage? {
    if (senderId == "user") {
        return if (shouldHideSystemNoise(content)) null else this
    }
    val sanitized = sanitizeAssistantContent(content)
    if (shouldHideSystemNoise(sanitized)) return null
    return copy(content = sanitized)
}

internal fun mergeHistoryMessages(
    existingMessages: List<ChatMessage>,
    loadedHistoryKeys: Set<String>,
    incomingMessages: List<ChatMessage>,
): HistoryMergeResult {
    val mergedMessages = existingMessages.toMutableList()
    val prependedMessages = mutableListOf<ChatMessage>()
    val nextLoadedKeys = loadedHistoryKeys.toMutableSet()
    val seenStableKeys = mergedMessages.map(::stableHistoryKey).toMutableSet()

    incomingMessages.forEach { incoming ->
        val message = incoming.sanitizedForDisplay() ?: return@forEach
        val stableKey = stableHistoryKey(message)
        nextLoadedKeys += stableKey
        if (stableKey in loadedHistoryKeys || stableKey in seenStableKeys) {
            return@forEach
        }

        val optimisticIndex = mergedMessages.indexOfFirst { existing ->
            existing.status == MessageStatus.SENDING &&
                existing.rawTimestamp == null &&
                existing.senderId == "user" &&
                message.senderId == "user" &&
                displayMessageKey(existing) == displayMessageKey(message)
        }
        if (optimisticIndex >= 0) {
            val optimistic = mergedMessages[optimisticIndex]
            mergedMessages[optimisticIndex] = message.copy(
                status = if (optimistic.status == MessageStatus.SENDING) MessageStatus.DELIVERED else message.status,
                clientMessageId = optimistic.clientMessageId,
            )
        } else {
            prependedMessages += message
        }
        seenStableKeys += stableKey
    }

    return HistoryMergeResult(
        messages = prependedMessages + mergedMessages,
        loadedHistoryKeys = nextLoadedKeys,
    )
}

internal fun stableHistoryKey(message: ChatMessage): String =
    "${message.senderId}|${message.rawTimestamp ?: message.timestamp}|${message.content}"

internal fun displayMessageKey(message: ChatMessage): String =
    "${message.senderId}|${message.timestamp}|${message.content}"

private fun shouldHideSystemNoise(content: String): Boolean {
    val trimmed = content.trim()
    if (trimmed == "HEARTBEAT_OK") return true
    if (trimmed.startsWith("System (untrusted):")) return true

    val containsHeartbeatPrompt = listOf(
        "Read HEARTBEAT.md if it exists",
        "reply HEARTBEAT_OK",
        "HEARTBEAT.md",
        "Do not infer or repeat oldtasks",
    ).any { trimmed.contains(it, ignoreCase = true) }
    if (containsHeartbeatPrompt && (
        trimmed.startsWith("Read HEARTBEAT.md")
            || trimmed.startsWith("Exec failed")
            || trimmed.contains("workspace/HEARTBEAT.md", ignoreCase = true)
            || trimmed.contains("Current time:", ignoreCase = true)
    )) {
        return true
    }
    return false
}

internal fun displayTimestamp(rawTimestamp: String, now: Date = Date()): String {
    val trimmed = rawTimestamp.trim()
    parseIsoTimestamp(trimmed)?.let { date ->
        val calendar = Calendar.getInstance().apply { time = now }
        val messageCalendar = Calendar.getInstance().apply { time = date }
        val isToday = calendar.get(Calendar.YEAR) == messageCalendar.get(Calendar.YEAR) &&
            calendar.get(Calendar.DAY_OF_YEAR) == messageCalendar.get(Calendar.DAY_OF_YEAR)
        val pattern = if (isToday) "HH:mm" else "MM月dd日 HH:mm"
        return SimpleDateFormat(pattern, Locale.getDefault()).format(date)
    }
    if (trimmed.length >= 16 && (trimmed[10] == 'T' || trimmed[10] == ' ')) {
        val candidate = trimmed.substring(11, 16)
        if (candidate.length == 5 && candidate[2] == ':') {
            return candidate
        }
    }
    if (trimmed.length >= 5 && trimmed[2] == ':') {
        return trimmed.substring(0, 5)
    }
    return trimmed
}

private fun normalizedTimestampValue(value: JsonElement?): String? {
    if (value == null) return null

    val primitive = runCatching { value.jsonPrimitive }.getOrNull()
    if (primitive != null) {
        val content = primitive.contentOrNull?.trim().orEmpty()
        if (content.isEmpty()) return null
        primitive.doubleOrNull?.let { return isoTimestampFromEpoch(it) }
        content.toDoubleOrNull()?.let { return isoTimestampFromEpoch(it) }
        return content
    }

    val obj = runCatching { value.jsonObject }.getOrNull() ?: return null
    return listOf("\$date", "date", "value", "iso")
        .firstNotNullOfOrNull { key -> normalizedTimestampValue(obj[key]) }
}

private fun isoTimestampFromEpoch(value: Double): String? {
    if (value <= 100_000_000) return null
    val millis = if (value > 1_000_000_000_000) value.toLong() else (value * 1000).toLong()
    return SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US).apply {
        timeZone = TimeZone.getTimeZone("UTC")
    }.format(Date(millis))
}

private fun parseIsoTimestamp(value: String): Date? {
    val patterns = listOf(
        "yyyy-MM-dd'T'HH:mm:ss.SSSX",
        "yyyy-MM-dd'T'HH:mm:ssX",
    )
    return patterns.firstNotNullOfOrNull { pattern ->
        try {
            SimpleDateFormat(pattern, Locale.US).apply {
                timeZone = TimeZone.getTimeZone("UTC")
            }.parse(value)
        } catch (_: ParseException) {
            null
        }
    }
}
