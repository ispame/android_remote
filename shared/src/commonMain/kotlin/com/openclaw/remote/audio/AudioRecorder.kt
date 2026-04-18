package com.openclaw.remote.audio

import kotlinx.coroutines.flow.StateFlow

/**
 * Audio Recorder - cross-platform abstraction for audio recording.
 */
expect class AudioRecorder() {
    val isRecording: StateFlow<Boolean>
    fun startRecording()
    fun stopRecording(onComplete: (ByteArray) -> Unit)
}
