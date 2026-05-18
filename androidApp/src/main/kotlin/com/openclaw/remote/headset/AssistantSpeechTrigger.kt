package com.openclaw.remote.headset

import com.openclaw.remote.data.ChatMessage

class AssistantSpeechTrigger {
    private var hasSeenCurrentUserMessage = false
    private var lastObservedMessageKey: String? = null
    private val spokenAssistantKeys = mutableSetOf<String>()

    fun onMessagesChanged(messages: List<ChatMessage>): List<ChatMessage> {
        if (messages.isEmpty()) return emptyList()
        val previousKey = lastObservedMessageKey
        val lastKey = messages.last().speechKey()
        if (previousKey == lastKey) return emptyList()
        if (previousKey == null) {
            if (messages.last().senderId == "user") {
                hasSeenCurrentUserMessage = true
            }
            lastObservedMessageKey = lastKey
            return emptyList()
        }

        val startIndex = messages.indexOfLast { it.speechKey() == previousKey }
        if (startIndex < 0) {
            lastObservedMessageKey = lastKey
            return emptyList()
        }

        val messagesToSpeak = mutableListOf<ChatMessage>()
        messages.drop(startIndex + 1).forEach { message ->
            val key = message.speechKey()
            if (message.senderId == "user") {
                hasSeenCurrentUserMessage = true
                return@forEach
            }
            if (
                message.senderId == "assistant" &&
                message.content.isNotBlank() &&
                hasSeenCurrentUserMessage &&
                spokenAssistantKeys.add(key)
            ) {
                messagesToSpeak += message
            }
        }

        lastObservedMessageKey = lastKey
        return messagesToSpeak
    }

    private fun ChatMessage.speechKey(): String =
        clientMessageId ?: "$senderId|$timestamp|$content"
}
