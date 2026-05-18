package com.openclaw.remote.headset

import com.openclaw.remote.data.ChatMessage
import org.junit.Assert.assertEquals
import org.junit.Test

class AssistantSpeechTriggerTest {
    @Test
    fun initialHistoryAssistantMessageDoesNotTriggerSpeech() {
        val trigger = AssistantSpeechTrigger()

        val result = trigger.onMessagesChanged(
            listOf(
                ChatMessage("之前的问题", "10:00", "user"),
                ChatMessage("之前的回答", "10:01", "assistant"),
            )
        )

        assertEquals(emptyList<ChatMessage>(), result)
    }

    @Test
    fun assistantReplyAfterCurrentUserMessageTriggersOnce() {
        val trigger = AssistantSpeechTrigger()
        val user = ChatMessage("现在的问题", "10:02", "user")
        val assistant = ChatMessage("现在的回答", "10:03", "assistant")

        assertEquals(emptyList<ChatMessage>(), trigger.onMessagesChanged(listOf(user)))
        assertEquals(listOf(assistant), trigger.onMessagesChanged(listOf(user, assistant)))
        assertEquals(emptyList<ChatMessage>(), trigger.onMessagesChanged(listOf(user, assistant)))
    }

    @Test
    fun consecutiveAssistantRepliesAfterCurrentUserMessageAllTriggerSpeech() {
        val trigger = AssistantSpeechTrigger()
        val user = ChatMessage("现在的问题", "10:02", "user")
        val firstAssistant = ChatMessage("第一段回答", "10:03", "assistant")
        val secondAssistant = ChatMessage("第二段回答", "10:04", "assistant")

        assertEquals(emptyList<ChatMessage>(), trigger.onMessagesChanged(listOf(user)))
        assertEquals(listOf(firstAssistant), trigger.onMessagesChanged(listOf(user, firstAssistant)))
        assertEquals(listOf(secondAssistant), trigger.onMessagesChanged(listOf(user, firstAssistant, secondAssistant)))
        assertEquals(emptyList<ChatMessage>(), trigger.onMessagesChanged(listOf(user, firstAssistant, secondAssistant)))
    }

    @Test
    fun batchedUserAndAssistantMessagesAfterObservedHistoryTriggerSpeech() {
        val trigger = AssistantSpeechTrigger()
        val history = listOf(
            ChatMessage("之前的问题", "09:58", "user"),
            ChatMessage("之前的回答", "09:59", "assistant"),
        )
        val user = ChatMessage("现在的问题", "10:02", "user")
        val firstAssistant = ChatMessage("第一段回答", "10:03", "assistant")
        val secondAssistant = ChatMessage("第二段回答", "10:04", "assistant")

        assertEquals(emptyList<ChatMessage>(), trigger.onMessagesChanged(history))
        assertEquals(
            listOf(firstAssistant, secondAssistant),
            trigger.onMessagesChanged(history + user + firstAssistant + secondAssistant)
        )
        assertEquals(
            emptyList<ChatMessage>(),
            trigger.onMessagesChanged(history + user + firstAssistant + secondAssistant)
        )
    }
}
