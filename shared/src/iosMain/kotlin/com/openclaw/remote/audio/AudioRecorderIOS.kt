package com.openclaw.remote.audio

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import platform.AVFoundation.*

actual class AudioRecorder {
    private var audioRecorder: AVAudioRecorder? = null
    private var recordingSession: AVAudioSession? = null
    private var tempFile: String? = null

    private val _isRecording = MutableStateFlow(false)
    actual val isRecording: StateFlow<Boolean> = _isRecording

    actual fun startRecording() {
        recordingSession = AVAudioSession.sharedInstance()
        recordingSession?.setCategory(AVAudioSession.CategoryPlayAndRecord)
        recordingSession?.setActive(true)

        val documentsPath = NSSearchPathForDirectoriesInDomains(
            NSSearchPathDirectory.DocumentDirectory,
            NSSearchPathDomainMask.UserDomainMask,
            true
        )[0] as String
        tempFile = "$documentsPath/temp_recording.m4a"

        val settings = mapOf(
            AVFormatIDKey to kAudioFormatMPEG4AAC,
            AVSampleRateKey to 16000,
            AVNumberOfChannelsKey to 1,
            AVEncoderAudioQualityKey to AVAudioQuality.High.rawValue
        )

        audioRecorder = AVAudioRecorder(
            URL(string = "file://$tempFile")!!,
            settings as [String: Any]
        )
        audioRecorder?.record()
        _isRecording.value = true
    }

    actual fun stopRecording(onComplete: (ByteArray) -> Unit) {
        audioRecorder?.stop()
        audioRecorder = null
        _isRecording.value = false

        recordingSession?.setActive(false)

        tempFile?.let { path ->
            val data = NSData.alloc().initWithContentsOfFile(path)!!
            val bytes = ByteArray(data.length.toInt()) { data.bytes[index].toByte() }
            onComplete(bytes)
        } ?: onComplete(ByteArray(0))
    }
}
