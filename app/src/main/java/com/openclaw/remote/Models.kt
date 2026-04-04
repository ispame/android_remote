package com.openclaw.remote

import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.UUID

enum class BackendKind(val title: String) {
    NANOBOT("Nanobot"),
    OPENCLAW("OpenClaw"),
}

enum class ChatRole {
    USER,
    ASSISTANT,
    SYSTEM,
}

data class ChatMessage(
    val id: String = UUID.randomUUID().toString(),
    val role: ChatRole,
    val content: String,
    val timestampMs: Long = System.currentTimeMillis(),
)

data class RemoteSettings(
    val backend: BackendKind = BackendKind.NANOBOT,
    val host: String = "192.168.1.14",
    val portText: String = "8765",
    val useTls: Boolean = false,
    val nanobotPath: String = "/ws",
    val openClawSharedToken: String = "",
    val openClawBootstrapToken: String = "",
    val openClawPassword: String = "",
    val openClawSessionKey: String = "main",
) {
    fun resolvedPort(): Int? = portText.trim().toIntOrNull()?.takeIf { it in 1..65535 }

    fun effectiveNanobotPath(): String {
        val trimmed = nanobotPath.trim()
        if (trimmed.isEmpty()) {
            return "/ws"
        }
        return if (trimmed.startsWith("/")) trimmed else "/$trimmed"
    }
}

fun defaultPortFor(backend: BackendKind): String {
    return when (backend) {
        BackendKind.NANOBOT -> "8765"
        BackendKind.OPENCLAW -> "18789"
    }
}

fun formatChatTimestamp(timestampMs: Long): String {
    val formatter = SimpleDateFormat("HH:mm:ss", Locale.getDefault())
    return formatter.format(Date(timestampMs))
}

fun formatHostAuthority(host: String): String {
    val normalizedHost = host.trim().trim('[', ']')
    return if (normalizedHost.contains(':')) "[${normalizedHost}]" else normalizedHost
}
