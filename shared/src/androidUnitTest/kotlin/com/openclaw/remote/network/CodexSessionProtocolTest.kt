package com.openclaw.remote.network

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertIs

class CodexSessionProtocolTest {
    @Test
    fun messageFrameCarriesSessionKey() {
        val event = parseWsMessageEventForTest(
            """
            {
              "type": "message",
              "backend_id": "codex-main",
              "session_key": "thread-123",
              "content": "done",
              "timestamp": "2026-06-20T10:00:00Z"
            }
            """.trimIndent()
        )

        val message = assertIs<WsMessageEvent.NewMessage>(event)
        assertEquals("thread-123", message.sessionKey)
        assertEquals("codex-main", message.backendId)
        assertEquals("done", message.message.content)
    }

    @Test
    fun sessionListResponseParsesSummaries() {
        val event = parseWsMessageEventForTest(
            """
            {
              "type": "agent_session_list_response",
              "backend_id": "codex-main",
              "request_id": "req-1",
              "sessions": [
                {
                  "session_id": "thread-1",
                  "title": "接入 Codex",
                  "preview": "user",
                  "last_assistant_preview": "assistant",
                  "project_path": "/tmp/boson",
                  "updated_at": "2026-06-20T10:00:00Z"
                }
              ]
            }
            """.trimIndent()
        )

        val response = assertIs<WsMessageEvent.CodexSessionListResponse>(event)
        assertEquals("codex-main", response.backendId)
        assertEquals("thread-1", response.sessions.single().sessionId)
        assertEquals("assistant", response.sessions.single().displayPreview)
    }

    @Test
    fun codexMessageFrameIncludesSessionKey() {
        val frame = codexMessageFrame(
            backendId = "codex-main",
            messageId = "msg-1",
            content = "hello",
            sessionId = "thread-123",
            timestamp = "2026-06-20T10:00:00Z",
        )

        assertEquals("message", frame["type"]?.toString()?.trim('"'))
        assertEquals("thread-123", frame["session_key"]?.toString()?.trim('"'))
    }
}
