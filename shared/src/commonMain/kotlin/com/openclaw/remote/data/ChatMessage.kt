package com.openclaw.remote.data

/**
 * Chat bubble message data class
 * @param content Message text content
 * @param timestamp Timestamp (HH:mm:ss format)
 * @param senderId Sender identifier: "user" | "assistant"
 * @param status Delivery status for outgoing user messages (null for incoming)
 * @param seq Router-assigned sequence number for reliable delivery tracking (null for incoming)
 */
data class ChatMessage(
    val content: String,
    val timestamp: String,
    val senderId: String = "assistant",
    val status: MessageStatus? = null,
    val seq: Int? = null,
)

/**
 * Delivery status for user-sent messages.
 * Used by WebSocketManager to track ACK state.
 */
enum class MessageStatus {
    SENDING,   // Message sent, awaiting router ack
    DELIVERED, // Router confirmed delivery to backend
    FAILED,    // Delivery failed after retries
}
