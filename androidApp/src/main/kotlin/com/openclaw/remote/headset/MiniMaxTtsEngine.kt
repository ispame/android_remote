package com.openclaw.remote.headset

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaExtractor
import android.media.MediaFormat
import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.io.ByteArrayInputStream
import java.nio.ByteBuffer
import java.util.concurrent.TimeUnit

class MiniMaxTtsEngine(context: Context) : BaseTtsEngine(context) {

    private val httpClient = OkHttpClient.Builder()
        .connectTimeout(30, TimeUnit.SECONDS)
        .readTimeout(60, TimeUnit.SECONDS)
        .writeTimeout(30, TimeUnit.SECONDS)
        .build()

    private var currentTrack: AudioTrack? = null

    override fun speak(text: String, apiKey: String?) {
        if (text.isBlank()) return
        if (apiKey.isNullOrBlank()) {
            Log.e(TAG, "MiniMax API key is empty")
            onSpeakDone?.invoke()
            return
        }

        scope.launch {
            try {
                onSpeakStart?.invoke()
                val audioData = fetchTtsAudio(text, apiKey)
                playMp3Audio(audioData)
                onSpeakDone?.invoke()
            } catch (e: Exception) {
                Log.e(TAG, "MiniMax TTS failed", e)
                onSpeakDone?.invoke()
            }
        }
    }

    private suspend fun fetchTtsAudio(text: String, apiKey: String): ByteArray = withContext(Dispatchers.IO) {
        val json = JSONObject().apply {
            put("model", "speech-02-hd")
            put("text", text)
            put("stream", false)
            put("voice_setting", JSONObject().apply {
                put("voice_id", "female_sunny_zh")
            })
        }

        val request = Request.Builder()
            .url("https://api.minimax.chat/v1/t2a_v2")
            .addHeader("Authorization", "Bearer $apiKey")
            .addHeader("Content-Type", "application/json")
            .post(json.toString().toRequestBody("application/json".toMediaType()))
            .build()

        val response = httpClient.newCall(request).execute()
        if (!response.isSuccessful) {
            throw Exception("MiniMax API error: ${response.code}")
        }

        response.body?.bytes() ?: throw Exception("Empty response")
    }

    private fun playMp3Audio(mp3Data: ByteArray) {
        try {
            val extractor = MediaExtractor()
            val mediaCodec = MediaCodec.createDecoderByType("audio/mp4a-latm")

            // 创建临时文件或使用内存数据源
            // 这里使用 ByteArrayInputStream 作为数据源
            val inputStream = ByteArrayInputStream(mp3Data)

            // 简化方案：使用 MediaExtractor 从字节数组中提取
            // 由于 MediaExtractor 需要 FileDescriptor，我们先写入临时文件
            val tempFile = java.io.File(context.cacheDir, "tts_temp.mp3")
            tempFile.writeBytes(mp3Data)

            extractor.setDataSource(tempFile.absolutePath)

            var audioTrackIndex = -1
            for (i in 0 until extractor.trackCount) {
                val format = extractor.getTrackFormat(i)
                val mime = format.getString(MediaFormat.KEY_MIME) ?: continue
                if (mime.startsWith("audio/")) {
                    audioTrackIndex = i
                    break
                }
            }

            if (audioTrackIndex < 0) {
                throw Exception("No audio track found")
            }

            extractor.selectTrack(audioTrackIndex)
            val format = extractor.getTrackFormat(audioTrackIndex)

            val sampleRate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
            val channelCount = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)

            mediaCodec.configure(format, null, null, 0)
            mediaCodec.start()

            val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as android.media.AudioManager
            audioManager.mode = android.media.AudioManager.MODE_IN_COMMUNICATION
            audioManager.isSpeakerphoneOn = false

            val bufferSize = AudioTrack.getMinBufferSize(
                sampleRate,
                AudioFormat.CHANNEL_OUT_STEREO,
                AudioFormat.ENCODING_PCM_16BIT
            )

            val track = AudioTrack.Builder()
                .setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_MEDIA)
                        .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                        .build()
                )
                .setAudioFormat(
                    AudioFormat.Builder()
                        .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                        .setSampleRate(sampleRate)
                        .setChannelMask(AudioFormat.CHANNEL_OUT_STEREO)
                        .build()
                )
                .setBufferSizeInBytes(bufferSize)
                .setTransferMode(AudioTrack.MODE_STREAM)
                .build()

            currentTrack = track
            track.play()

            val buffer = ByteBuffer.allocate(1024 * 64)
            val bufferInfo = MediaCodec.BufferInfo()

            while (true) {
                val inputBufferIndex = mediaCodec.dequeueInputBuffer(10000)
                if (inputBufferIndex >= 0) {
                    val inputBuffer = mediaCodec.getInputBuffer(inputBufferIndex)
                    inputBuffer?.clear()
                    val sampleSize = extractor.readSampleData(buffer, 0)
                    if (sampleSize < 0) {
                        mediaCodec.queueInputBuffer(inputBufferIndex, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                        break
                    }
                    inputBuffer?.put(buffer)
                    mediaCodec.queueInputBuffer(inputBufferIndex, 0, sampleSize, extractor.sampleTime, 0)
                    extractor.advance()
                }

                val outputBufferIndex = mediaCodec.dequeueOutputBuffer(bufferInfo, 10000)
                if (outputBufferIndex >= 0) {
                    val outputBuffer = mediaCodec.getOutputBuffer(outputBufferIndex)
                    if (outputBuffer != null && bufferInfo.size > 0) {
                        val pcmData = ByteArray(bufferInfo.size)
                        outputBuffer.get(pcmData)
                        track.write(pcmData, 0, pcmData.size)
                    }
                    mediaCodec.releaseOutputBuffer(outputBufferIndex, false)

                    if (bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) {
                        break
                    }
                }
            }

            track.stop()
            track.release()
            mediaCodec.stop()
            mediaCodec.release()
            extractor.release()
            tempFile.delete()

            Log.d(TAG, "MiniMax TTS playback completed")
        } catch (e: Exception) {
            Log.e(TAG, "MP3 playback failed", e)
        }
    }

    override fun stop() {
        currentTrack?.stop()
        currentTrack?.release()
        currentTrack = null
    }

    override fun release() {
        stop()
    }

    companion object {
        private const val TAG = "MiniMaxTtsEngine"
    }
}