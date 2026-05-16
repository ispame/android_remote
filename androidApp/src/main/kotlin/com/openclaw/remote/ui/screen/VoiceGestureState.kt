package com.openclaw.remote.ui.screen

enum class VoiceRecordingState {
    IDLE,
    RECORDING_SEND,
    RECORDING_CANCEL;

    val isRecording: Boolean
        get() = this != IDLE

    val isCancelled: Boolean
        get() = this == RECORDING_CANCEL
}

fun recordingPanelTopY(screenHeightPx: Float): Float = screenHeightPx * 0.74f

fun voiceRecordingState(
    isRecording: Boolean,
    isGestureActive: Boolean,
    touchY: Float,
    panelTopY: Float,
): VoiceRecordingState {
    if (!isRecording) return VoiceRecordingState.IDLE
    if (isGestureActive && touchY < panelTopY) return VoiceRecordingState.RECORDING_CANCEL
    return VoiceRecordingState.RECORDING_SEND
}

fun shouldCancelVoiceRelease(
    finalTouchY: Float,
    panelTopY: Float,
    pointerCancelled: Boolean,
): Boolean = pointerCancelled || finalTouchY < panelTopY
