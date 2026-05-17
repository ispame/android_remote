package com.openclaw.remote.viewmodel

import com.openclaw.remote.data.ChatMessage
import com.openclaw.remote.data.MessageStatus

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

private fun displayTimestamp(rawTimestamp: String): String {
    val trimmed = rawTimestamp.trim()
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
