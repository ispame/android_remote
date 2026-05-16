package com.openclaw.remote.ui.screen

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class VoiceGestureStateTest {
    @Test
    fun recordingPanelTopYUsesBottomTwentySixPercentAsCancelBoundary() {
        assertEquals(740f, recordingPanelTopY(screenHeightPx = 1000f))
    }

    @Test
    fun voiceRecordingStateIsIdleWhenNotRecording() {
        val state = voiceRecordingState(
            isRecording = false,
            isGestureActive = true,
            touchY = 600f,
            panelTopY = 740f,
        )

        assertEquals(VoiceRecordingState.IDLE, state)
    }

    @Test
    fun voiceRecordingStateSendsWhenFingerStaysInsideRecordingPanel() {
        val state = voiceRecordingState(
            isRecording = true,
            isGestureActive = true,
            touchY = 900f,
            panelTopY = 740f,
        )

        assertEquals(VoiceRecordingState.RECORDING_SEND, state)
    }

    @Test
    fun voiceRecordingStateCancelsWhenFingerMovesAboveRecordingPanel() {
        val state = voiceRecordingState(
            isRecording = true,
            isGestureActive = true,
            touchY = 739f,
            panelTopY = 740f,
        )

        assertEquals(VoiceRecordingState.RECORDING_CANCEL, state)
    }

    @Test
    fun releaseAboveRecordingPanelCancels() {
        assertTrue(shouldCancelVoiceRelease(finalTouchY = 739f, panelTopY = 740f, pointerCancelled = false))
    }

    @Test
    fun pointerCancellationAlwaysCancels() {
        assertTrue(shouldCancelVoiceRelease(finalTouchY = 900f, panelTopY = 740f, pointerCancelled = true))
    }

    @Test
    fun releaseAtRecordingPanelBoundaryStillSends() {
        assertFalse(shouldCancelVoiceRelease(finalTouchY = 740f, panelTopY = 740f, pointerCancelled = false))
    }
}
