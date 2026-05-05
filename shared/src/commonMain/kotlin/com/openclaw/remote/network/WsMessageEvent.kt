package com.openclaw.remote.network

import com.openclaw.remote.data.ChatMessage

/**
 * WebSocket message events
 */
sealed class WsMessageEvent {
    data class Registered(val deviceId: String) : WsMessageEvent()
    data class Paired(val backendId: String, val backendLabel: String, val isRestoringPairing: Boolean = false) : WsMessageEvent()
    data class NewMessage(val message: ChatMessage) : WsMessageEvent()
    data class HistoryResponse(val messages: List<ChatMessage>, val hasMore: Boolean, val error: String?) : WsMessageEvent()
    data class AsrResult(val clientMessageId: String?, val success: Boolean, val text: String?, val error: String?) : WsMessageEvent()
    object Unpaired : WsMessageEvent()
    data class Error(val code: String, val message: String) : WsMessageEvent()
}
