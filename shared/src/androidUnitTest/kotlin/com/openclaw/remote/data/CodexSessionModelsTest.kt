package com.openclaw.remote.data

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse

class CodexSessionModelsTest {
    @Test
    fun codexPlatformDecodesAndDisablesAudio() {
        assertEquals(AgentPlatform.CODEX, AgentPlatform.fromWireValue("codex"))
        assertEquals("Codex", AgentPlatform.CODEX.label)
        assertFalse(AgentPlatform.CODEX.supportsAudio)
    }

    @Test
    fun projectNameFallsBackToLastPathSegmentOrChat() {
        assertEquals(
            "boson",
            CodexSessionSummary(
                sessionId = "thread-1",
                title = "Router",
                projectPath = "/Users/spame/WorkTable/openclaw_coder/boson",
                projectName = "",
                updatedAt = "2026-06-20T03:00:00Z",
            ).displayProjectName,
        )
        assertEquals(
            "聊天",
            CodexSessionSummary(
                sessionId = "thread-2",
                title = "Chat",
                projectPath = "",
                projectName = null,
                updatedAt = "2026-06-20T03:00:00Z",
            ).displayProjectName,
        )
    }

    @Test
    fun groupsByTimeAndProject() {
        val sessions = listOf(
            sample("today", "boson", "2026-06-20T10:00:00Z"),
            sample("yesterday", "boson", "2026-06-19T10:00:00Z"),
            sample("four-days", "android_remote", "2026-06-16T10:00:00Z"),
            sample("last-week", "boson", "2026-06-10T10:00:00Z"),
            sample("two-weeks", "android_remote", "2026-06-03T10:00:00Z"),
            sample("last-month", "boson", "2026-05-20T10:00:00Z"),
        )

        assertEquals(
            listOf("今天", "昨天", "4天前", "上周", "2周前", "上个月"),
            groupCodexSessions(
                sessions = sessions,
                mode = CodexSessionGroupingMode.TIME,
                nowEpochDay = codexEpochDayFromIso("2026-06-20T12:00:00Z"),
            ).map { it.title },
        )

        val projectGroups = groupCodexSessions(
            sessions = sessions,
            mode = CodexSessionGroupingMode.PROJECT,
            nowEpochDay = codexEpochDayFromIso("2026-06-20T12:00:00Z"),
        )
        assertEquals(listOf("boson", "android_remote"), projectGroups.map { it.title })
        assertEquals(listOf("today", "yesterday", "last-week", "last-month"), projectGroups[0].sessions.map { it.sessionId })
    }

    private fun sample(id: String, projectName: String, updatedAt: String): CodexSessionSummary =
        CodexSessionSummary(
            sessionId = id,
            title = id,
            projectName = projectName,
            projectPath = "/tmp/$projectName",
            updatedAt = updatedAt,
        )
}
