package com.openclaw.remote.network

import com.openclaw.remote.data.CodexSessionSummary
import com.openclaw.remote.data.ChatMessage
import com.openclaw.remote.data.RecordingAsrJob
import com.openclaw.remote.data.RecordingEvent
import com.openclaw.remote.data.RecordingWorkflow

/**
 * WebSocket message events
 */
sealed class WsMessageEvent {
    data class Registered(
        val accountId: String,
        val pairedBackendIds: List<String> = emptyList(),
    ) : WsMessageEvent()
    data class Paired(val backendId: String, val backendLabel: String, val isRestoringPairing: Boolean = false) : WsMessageEvent()
    data class NewMessage(
        val message: ChatMessage,
        val backendId: String? = null,
        val sessionKey: String? = null,
    ) : WsMessageEvent()
    data class HistoryResponse(
        val messages: List<ChatMessage>,
        val hasMore: Boolean,
        val error: String?,
        val backendId: String? = null,
        val sessionKey: String? = null,
    ) : WsMessageEvent()
    data class CodexSessionListResponse(
        val sessions: List<CodexSessionSummary>,
        val archived: Boolean,
        val error: String?,
        val backendId: String? = null,
        val requestId: String? = null,
    ) : WsMessageEvent()
    data class CodexSessionCreateResponse(
        val session: CodexSessionSummary?,
        val sessionId: String?,
        val accepted: Boolean,
        val error: String?,
        val backendId: String? = null,
        val requestId: String? = null,
    ) : WsMessageEvent()
    data class CodexSessionArchiveResponse(
        val sessionId: String,
        val archived: Boolean,
        val error: String?,
        val backendId: String? = null,
        val requestId: String? = null,
    ) : WsMessageEvent()
    data class CodexSessionUnarchiveResponse(
        val sessionId: String,
        val unarchived: Boolean,
        val error: String?,
        val backendId: String? = null,
        val requestId: String? = null,
    ) : WsMessageEvent()
    data class AsrResult(val clientMessageId: String?, val success: Boolean, val text: String?, val error: String?) : WsMessageEvent()
    data class RecordingWorkflowUpdate(val workflow: RecordingWorkflow) : WsMessageEvent()
    data class RecordingEventReceived(val event: RecordingEvent) : WsMessageEvent()
    data class LongRecordingAsrStatusReceived(
        val recordingId: String,
        val job: RecordingAsrJob,
        val text: String?,
    ) : WsMessageEvent()
    data class Unpaired(val backendId: String? = null) : WsMessageEvent()
    data class SessionPreempted(
        val reason: String,
        val replacementTerminalLabel: String? = null,
    ) : WsMessageEvent()
    data class Error(val code: String, val message: String) : WsMessageEvent()
}
