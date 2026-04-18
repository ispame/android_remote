package com.openclaw.remote.data

/**
 * Chat bubble message data class
 * @param content Message text content
 * @param timestamp Timestamp (HH:mm:ss format)
 * @param senderId Sender identifier: "user" | "assistant"
 */
data class ChatMessage(
    val content: String,
    val timestamp: String,
    val senderId: String = "assistant"
)
