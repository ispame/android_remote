package com.openclaw.remote.ui.screen

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ChatInitialScrollTrackerTest {
    @Test
    fun emptyConversationWaitsForMessagesBeforePositioning() {
        val tracker = ChatInitialScrollTracker()

        assertFalse(tracker.shouldPosition("agent-1", hasMessages = false))
        assertTrue(tracker.shouldPosition("agent-1", hasMessages = true))
    }

    @Test
    fun positionedConversationDoesNotRepositionForIncomingMessages() {
        val tracker = ChatInitialScrollTracker()

        assertTrue(tracker.shouldPosition("agent-1", hasMessages = true))
        tracker.markPositioned("agent-1")

        assertFalse(tracker.shouldPosition("agent-1", hasMessages = true))
    }

    @Test
    fun switchingConversationRequiresNewInitialPosition() {
        val tracker = ChatInitialScrollTracker()
        tracker.markPositioned("agent-1")

        assertTrue(tracker.shouldPosition("agent-2", hasMessages = true))
        tracker.markPositioned("agent-2")
        assertTrue(tracker.shouldPosition("agent-1", hasMessages = true))
    }
}
