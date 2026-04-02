package com.openclaw.remote

/**
 * 聊天气泡消息数据类
 * @param content 消息文本内容（不含前缀标签）
 * @param timestamp 时间戳（HH:mm:ss 格式）
 * @param senderId 发送者标识："user" | "assistant"
 */
data class ChatMessage(
    val content: String,
    val timestamp: String,
    val senderId: String = "assistant"
)
