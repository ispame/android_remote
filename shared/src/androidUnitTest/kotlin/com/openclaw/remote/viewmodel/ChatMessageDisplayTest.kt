package com.openclaw.remote.viewmodel

import com.openclaw.remote.data.ChatMessage
import com.openclaw.remote.data.MessageStatus
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class ChatMessageDisplayTest {
    @Test
    fun sanitizeAssistantContentSupportsReplyToMarkerVariants() {
        assertEquals("hello", sanitizeAssistantContent("[[reply_to_current]] hello"))
        assertEquals("hello", sanitizeAssistantContent("  [[reply_to current]] hello"))
    }

    @Test
    fun mergeHistoryMessagesReplacesOptimisticUserMessage() {
        val optimistic = ChatMessage(
            content = "你好",
            timestamp = "10:12",
            senderId = "user",
            status = MessageStatus.SENDING,
        )
        val historyMessage = historyChatMessage(
            content = "你好",
            role = "user",
            rawTimestamp = "2026-05-17T10:12:34Z",
        )

        val result = mergeHistoryMessages(
            existingMessages = listOf(optimistic),
            loadedHistoryKeys = emptySet(),
            incomingMessages = listOf(historyMessage),
        )

        assertEquals(1, result.messages.size)
        assertEquals("10:12", result.messages.single().timestamp)
        assertEquals("2026-05-17T10:12:34Z", result.messages.single().rawTimestamp)
        assertEquals(MessageStatus.DELIVERED, result.messages.single().status)
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
}
