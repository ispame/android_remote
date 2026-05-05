package com.openclaw.remote.audio

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import platform.AVFoundation.*

class AudioRecorderIOS : AudioRecorder {
    private var audioRecorder: AVAudioRecorder? = null
    private var recordingSession: AVAudioSession? = null
    private var tempFile: String? = null

    private val _isRecording = MutableStateFlow(false)
    override val isRecording: StateFlow<Boolean> = _isRecording

    override fun startRecording() {
        recordingSession = AVAudioSession.sharedInstance()
        recordingSession?.setCategory(AVAudioSession.CategoryPlayAndRecord)
        recordingSession?.setActive(true)

        val documentsPath = NSSearchPathForDirectoriesInDomains(
            NSSearchPathDirectory.DocumentDirectory,
            NSSearchPathDomainMask.UserDomainMask,
            true
        )[0] as String
        tempFile = "$documentsPath/temp_recording.wav"

        val settings = mapOf(
            AVFormatIDKey to kAudioFormatLinearPCM,
            AVSampleRateKey to 16000,
            AVNumberOfChannelsKey to 1,
            AVLinearPCMBitDepthKey to 16,
            AVLinearPCMIsFloatKey to false,
            AVLinearPCMIsBigEndianKey to false
        )

        audioRecorder = AVAudioRecorder(
            URL(string = "file://$tempFile")!!,
            settings as [String: Any]
        )
        audioRecorder?.record()
        _isRecording.value = true
    }

    override fun stopRecording(onComplete: (ByteArray) -> Unit) {
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
