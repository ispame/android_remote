package com.openclaw.remote

import android.content.Context
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import java.io.ByteArrayOutputStream

interface AudioChunkCallback {
    fun onChunk(chunk: ByteArray, isLast: Boolean)
}

class AudioRecorder(private val context: Context) {
    private var audioRecord: AudioRecord? = null
    private var recordingThread: Thread? = null
    private var streamingThread: Thread? = null
    private var isRecordingInternal = false
    private var isStreamingInternal = false
    private val audioBuffer = ByteArrayOutputStream()

    private val _isRecording = MutableStateFlow(false)
    val isRecording: StateFlow<Boolean> = _isRecording

    private val _isStreaming = MutableStateFlow(false)
    val isStreaming: StateFlow<Boolean> = _isStreaming

    private val sampleRate = 16000
    private val channelConfig = AudioFormat.CHANNEL_IN_MONO
    private val audioFormat = AudioFormat.ENCODING_PCM_16BIT
    private val bufferSize = AudioRecord.getMinBufferSize(sampleRate, channelConfig, audioFormat)

    // 流式录音: 200ms @ 16kHz @ 16bit @ mono = 6400 bytes
    private val chunkDurationMs = 200
    private val chunkSize = sampleRate * 2 * chunkDurationMs / 1000  // 6400 bytes

    fun startRecording() {
        audioBuffer.reset()
        audioRecord = AudioRecord(
            MediaRecorder.AudioSource.MIC,
            sampleRate,
            channelConfig,
            audioFormat,
            bufferSize
        )

        audioRecord?.startRecording()
        isRecordingInternal = true
        _isRecording.value = true

        recordingThread = Thread {
            val buffer = ByteArray(bufferSize)
            while (isRecordingInternal) {
                val read = audioRecord?.read(buffer, 0, buffer.size) ?: 0
                if (read > 0) {
                    audioBuffer.write(buffer, 0, read)
                }
            }
        }
        recordingThread?.start()
    }

    fun stopRecording(onComplete: (ByteArray) -> Unit) {
        isRecordingInternal = false
        _isRecording.value = false

        audioRecord?.stop()
        audioRecord?.release()
        audioRecord = null

        recordingThread?.join()
        recordingThread = null

        val wavData = createWavFile(audioBuffer.toByteArray())
        onComplete(wavData)
    }

    /**
     * 流式录音: 按 200ms 分块，通过回调实时推送
     * 调用 stopStreaming() 停止
     */
    fun startStreaming(callback: AudioChunkCallback) {
        audioBuffer.reset()
        isStreamingInternal = true
        _isStreaming.value = true

        audioRecord = AudioRecord(
            MediaRecorder.AudioSource.MIC,
            sampleRate,
            channelConfig,
            audioFormat,
            bufferSize
        )

        audioRecord?.startRecording()

        streamingThread = Thread {
            val buffer = ByteArray(bufferSize)
            while (isStreamingInternal) {
                val read = audioRecord?.read(buffer, 0, buffer.size) ?: 0
                if (read > 0) {
                    // 只取前 chunkSize bytes（200ms）
                    val chunk = buffer.copyOf(minOf(read, chunkSize))
                    audioBuffer.write(chunk, 0, chunk.size)
                    // 回调出去（WebSocket发送）
                    callback.onChunk(chunk, isLast = false)
                }
            }
        }
        streamingThread?.start()
    }

    /**
     * 停止流式录音，返回完整PCM数据
     */
    fun stopStreaming(): ByteArray {
        isStreamingInternal = false
        _isStreaming.value = false

        audioRecord?.stop()
        audioRecord?.release()
        audioRecord = null

        streamingThread?.join()
        streamingThread = null

        return audioBuffer.toByteArray()
    }

    private fun createWavFile(pcmData: ByteArray): ByteArray {
        val output = ByteArrayOutputStream()
        val totalDataLen = pcmData.size + 36
        val channels = 1
        val byteRate = sampleRate * channels * 2

        output.write("RIFF".toByteArray())
        output.write(intToByteArray(totalDataLen), 0, 4)
        output.write("WAVE".toByteArray())
        output.write("fmt ".toByteArray())
        output.write(intToByteArray(16), 0, 4)
        output.write(shortToByteArray(1), 0, 2)
        output.write(shortToByteArray(channels.toShort()), 0, 2)
        output.write(intToByteArray(sampleRate), 0, 4)
        output.write(intToByteArray(byteRate), 0, 4)
        output.write(shortToByteArray((channels * 2).toShort()), 0, 2)
        output.write(shortToByteArray(16), 0, 2)
        output.write("data".toByteArray())
        output.write(intToByteArray(pcmData.size), 0, 4)
        output.write(pcmData)

        return output.toByteArray()
    }

    private fun intToByteArray(value: Int): ByteArray {
        return byteArrayOf(
            (value and 0xff).toByte(),
            (value shr 8 and 0xff).toByte(),
            (value shr 16 and 0xff).toByte(),
            (value shr 24 and 0xff).toByte()
        )
    }

    private fun shortToByteArray(value: Short): ByteArray {
        return byteArrayOf(
            (value.toInt() and 0xff).toByte(),
            (value.toInt() shr 8 and 0xff).toByte()
        )
    }
}
