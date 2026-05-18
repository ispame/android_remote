package com.openclaw.remote.headset

import com.openclaw.remote.data.ChatMessage
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
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

        assertNull(result)
    }

    @Test
    fun assistantReplyAfterCurrentUserMessageTriggersOnce() {
        val trigger = AssistantSpeechTrigger()
        val user = ChatMessage("现在的问题", "10:02", "user")
        val assistant = ChatMessage("现在的回答", "10:03", "assistant")

        assertNull(trigger.onMessagesChanged(listOf(user)))
        assertEquals(assistant, trigger.onMessagesChanged(listOf(user, assistant)))
        assertNull(trigger.onMessagesChanged(listOf(user, assistant)))
    }

    @Test
    fun consecutiveAssistantRepliesAfterCurrentUserMessageAllTriggerSpeech() {
        val trigger = AssistantSpeechTrigger()
        val user = ChatMessage("现在的问题", "10:02", "user")
        val firstAssistant = ChatMessage("第一段回答", "10:03", "assistant")
        val secondAssistant = ChatMessage("第二段回答", "10:04", "assistant")

        assertNull(trigger.onMessagesChanged(listOf(user)))
        assertEquals(firstAssistant, trigger.onMessagesChanged(listOf(user, firstAssistant)))
        assertEquals(secondAssistant, trigger.onMessagesChanged(listOf(user, firstAssistant, secondAssistant)))
        assertNull(trigger.onMessagesChanged(listOf(user, firstAssistant, secondAssistant)))
    }
}
