package com.openclaw.remote.viewmodel

import com.openclaw.remote.data.ChatMessage
import com.openclaw.remote.data.MessageStatus
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonObject
import java.text.SimpleDateFormat
import java.util.Locale
import java.util.TimeZone
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class ChatMessageDisplayTest {
    @Test
    fun displayTimestampConvertsUtcIsoTimestampToLocalTimeForToday() {
        withTimeZone("Asia/Shanghai") {
            val now = parseUtc("2026-05-21T03:00:00.000Z")

            assertEquals("08:07", displayTimestamp("2026-05-21T00:07:59.689Z", now))
        }
    }

    @Test
    fun displayTimestampIncludesMonthAndDayForOlderIsoTimestamp() {
        withTimeZone("Asia/Shanghai") {
            val now = parseUtc("2026-05-21T03:00:00.000Z")

            assertEquals("05月20日 18:43", displayTimestamp("2026-05-20T10:43:00.000Z", now))
        }
    }

    @Test
    fun historyTimestampReadsHermesCreatedAtBeforeFallback() {
        val item = buildJsonObject {
            put("created_at", "2026-05-20T10:43:00.000Z")
        }

        assertEquals("2026-05-20T10:43:00.000Z", historyTimestamp(item))
    }

    @Test
    fun historyTimestampConvertsNumericCreatedAt() {
        val item = buildJsonObject {
            put("createdAt", 1_779_273_780_000)
        }

        assertEquals("2026-05-20T10:43:00.000Z", historyTimestamp(item))
    }

    @Test
    fun historyTimestampReadsNestedDateValue() {
        val item = buildJsonObject {
            putJsonObject("createdAt") {
                put("\$date", "2026-05-20T10:43:00.000Z")
            }
        }

        assertEquals("2026-05-20T10:43:00.000Z", historyTimestamp(item))
    }

    @Test
    fun historyTimestampDoesNotFallbackToCurrentTimeWhenMissing() {
        assertEquals("", historyTimestamp(buildJsonObject { put("content", "hello") }))
    }

    @Test
    fun chatMessageFromPayloadPrefersPayloadTimestampOverFallback() {
        val item = buildJsonObject {
            put("content", "hello")
            put("created_at", "2026-05-20T10:43:00.000Z")
        }

        val message = chatMessageFromPayload(
            content = "hello",
            role = "assistant",
            item = item,
            fallbackTimestamp = "09:30",
        )

        assertEquals("2026-05-20T10:43:00.000Z", message.rawTimestamp)
        assertTrue(message.timestamp != "09:30")
    }

    @Test
    fun chatMessageFromPayloadFallsBackForLiveMessagesWithoutServerTimestamp() {
        val message = chatMessageFromPayload(
            content = "hello",
            role = "assistant",
            item = buildJsonObject { put("content", "hello") },
            fallbackTimestamp = "09:30",
        )

        assertEquals("09:30", message.rawTimestamp)
        assertEquals("09:30", message.timestamp)
    }

    @Test
    fun sanitizeAssistantContentSupportsReplyToMarkerVariants() {
        assertEquals("hello", sanitizeAssistantContent("[[reply_to_current]] hello"))
        assertEquals("hello", sanitizeAssistantContent("  [[reply_to current]] hello"))
    }

    @Test
    fun mergeHistoryMessagesReplacesOptimisticUserMessage() {
        withTimeZone("Asia/Shanghai") {
            val optimistic = ChatMessage(
                content = "你好",
                timestamp = "10:12",
                senderId = "user",
                status = MessageStatus.SENDING,
            )
            val historyMessage = ChatMessage(
                content = "你好",
                timestamp = "10:12",
                senderId = "user",
                rawTimestamp = "2026-05-21T02:12:34Z",
            )

            val result = mergeHistoryMessages(
                existingMessages = listOf(optimistic),
                loadedHistoryKeys = emptySet(),
                incomingMessages = listOf(historyMessage),
            )

            assertEquals(1, result.messages.size)
            assertEquals("10:12", result.messages.single().timestamp)
            assertEquals("2026-05-21T02:12:34Z", result.messages.single().rawTimestamp)
            assertEquals(MessageStatus.DELIVERED, result.messages.single().status)
        }
    }

    @Test
    fun mergeHistoryMessagesSkipsAlreadyLoadedHistory() {
        val historyMessage = historyChatMessage(
            content = "欢迎回来",
            role = "assistant",
            rawTimestamp = "2026-05-17T10:15:00Z",
        )

        val result = mergeHistoryMessages(
            existingMessages = emptyList(),
            loadedHistoryKeys = setOf(stableHistoryKey(historyMessage)),
            incomingMessages = listOf(historyMessage),
        )

        assertTrue(result.messages.isEmpty())
        assertEquals(setOf(stableHistoryKey(historyMessage)), result.loadedHistoryKeys)
    }

    @Test
    fun allAsrFailuresDropOptimisticMessage() {
        assertTrue(shouldDropAsrFailureMessage("ASR_AUDIO_EMPTY"))
        assertTrue(shouldDropAsrFailureMessage("ASR_EMPTY_TRANSCRIPT"))
        assertTrue(shouldDropAsrFailureMessage("ASR_PROVIDER_CLOSED"))
        assertTrue(shouldDropAsrFailureMessage(null))
    }

    private fun withTimeZone(id: String, block: () -> Unit) {
        val original = TimeZone.getDefault()
        try {
            TimeZone.setDefault(TimeZone.getTimeZone(id))
            block()
        } finally {
            TimeZone.setDefault(original)
        }
    }

    private fun parseUtc(value: String) =
        SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSSX", Locale.US).apply {
            timeZone = TimeZone.getTimeZone("UTC")
        }.parse(value)!!
}
