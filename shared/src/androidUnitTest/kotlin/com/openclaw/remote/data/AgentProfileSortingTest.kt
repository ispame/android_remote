package com.openclaw.remote.data

import kotlin.test.Test
import kotlin.test.assertEquals

class AgentProfileSortingTest {
    @Test
    fun sortedForAgentListPutsPinnedProfilesBeforeUnreadAndRecentProfiles() {
        val olderUnread = profile("older-unread", updatedAt = 100, sortIndex = 10)
        val newerUnread = profile("newer-unread", updatedAt = 200, sortIndex = 20)
        val pinnedRead = profile("pinned-read", updatedAt = 50, isPinned = true, sortIndex = 30)
        val recentRead = profile("recent-read", updatedAt = 300, sortIndex = 40)

        val sorted = listOf(olderUnread, newerUnread, pinnedRead, recentRead).sortedForAgentList(
            unreadCounts = mapOf(
                "older-unread" to 2,
                "newer-unread" to 1,
            ),
            activities = mapOf(
                "older-unread" to AgentListActivity(lastMessageText = "old unread", lastMessageAt = 1_000),
                "newer-unread" to AgentListActivity(lastMessageText = "new unread", lastMessageAt = 2_000),
                "recent-read" to AgentListActivity(lastMessageText = "read", lastMessageAt = 3_000),
            ),
        )

        assertEquals(
            listOf("pinned-read", "newer-unread", "older-unread", "recent-read"),
            sorted.map { it.id },
        )
    }

    @Test
    fun legacyProfileDecodeDefaultsPinAndSortFields() {
        val decoded = decodeProfiles(
            """
            [
              {
                "id": "legacy",
                "platform": "openclaw",
                "displayName": "Legacy Agent",
                "gatewayUrl": "wss://boson-tech.top/ws",
                "backendId": "bk_legacy"
              }
            ]
            """.trimIndent()
        )

        assertEquals(false, decoded.single().isPinned)
        assertEquals(0, decoded.single().sortIndex)
    }

    private fun profile(
        id: String,
        updatedAt: Long,
        isPinned: Boolean = false,
        sortIndex: Int = 0,
    ): AgentProfile =
        AgentProfile(
            id = id,
            backendId = "bk_$id",
            displayName = id,
            updatedAt = updatedAt,
            createdAt = updatedAt,
            isPinned = isPinned,
            sortIndex = sortIndex,
        )
}
