package com.openclaw.remote.headset

import com.openclaw.remote.data.ChatMessage

class AssistantSpeechTrigger {
    private var hasSeenCurrentUserMessage = false
    private var lastObservedMessageKey: String? = null
    private val spokenAssistantKeys = mutableSetOf<String>()

    fun onMessagesChanged(messages: List<ChatMessage>): ChatMessage? {
        val lastMessage = messages.lastOrNull() ?: return null
        val key = lastMessage.speechKey()
        if (lastObservedMessageKey == key) return null
        lastObservedMessageKey = key

        if (lastMessage.senderId == "user") {
            hasSeenCurrentUserMessage = true
            return null
        }

        if (lastMessage.senderId != "assistant" || lastMessage.content.isBlank()) {
            return null
        }
        if (!hasSeenCurrentUserMessage || !spokenAssistantKeys.add(key)) {
            return null
        }

        hasSeenCurrentUserMessage = false
        return lastMessage
    }

    private fun ChatMessage.speechKey(): String =
        clientMessageId ?: "$senderId|$timestamp|$content"
}
