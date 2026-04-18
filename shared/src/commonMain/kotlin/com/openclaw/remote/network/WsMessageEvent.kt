package com.openclaw.remote.network

import com.openclaw.remote.data.ChatMessage

/**
 * WebSocket message events
 */
sealed class WsMessageEvent {
    data class Registered(val deviceId: String) : WsMessageEvent()
    data class Paired(val backendId: String, val backendLabel: String) : WsMessageEvent()
    data class NewMessage(val message: ChatMessage) : WsMessageEvent()
    object Unpaired : WsMessageEvent()
    data class Error(val code: String, val message: String) : WsMessageEvent()
}
