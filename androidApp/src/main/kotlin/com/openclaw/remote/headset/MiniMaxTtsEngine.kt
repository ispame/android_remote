package com.openclaw.remote.headset

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import android.media.MediaCodec
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
        // MiniMax TTS API - 参考: https://api.minimaxi.com/document/APIDetail/3
        val json = JSONObject().apply {
            put("model", "speech-2.8-hd")
            put("text", text)
            put("stream", false)
            put("voice_setting", JSONObject().apply {
                put("voice_id", "male-qn-qingse")
                put("speed", 1.0)
                put("vol", 1.0)
                put("pitch", 0.0)
                put("emotion", "happy")
            })
            put("audio_setting", JSONObject().apply {
                put("sample_rate", 32000)
                put("bitrate", 128000)
                put("format", "mp3")
                put("channel", 1)
            })
            put("subtitle_enable", false)
            put("output_format", "hex")
        }

        val request = Request.Builder()
            .url("https://api.minimaxi.com/v1/t2a_v2")
            .addHeader("Authorization", "Bearer $apiKey")
            .addHeader("Content-Type", "application/json")
            .post(json.toString().toRequestBody("application/json".toMediaType()))
            .build()

        httpClient.newCall(request).execute().use { response ->
            val responseBody = response.body?.string() ?: throw Exception("Empty response")
            if (!response.isSuccessful) {
                throw Exception("MiniMax API error: ${response.code}, body: $responseBody")
            }

            val parsed = MiniMaxTtsResponseParser.parse(responseBody)
            Log.i(
                TAG,
                "MiniMax TTS fetch success trace_id=${parsed.traceId} " +
                    "format=${parsed.audioFormat} bytes=${parsed.audioBytes.size} " +
                    "sample_rate=${parsed.sampleRate} channels=${parsed.channelCount}"
            )
            parsed.audioBytes
        }
    }

    private fun playMp3Audio(mp3Data: ByteArray) {
        var extractor: MediaExtractor? = null
        var mediaCodec: MediaCodec? = null
        var codecStarted = false
        var track: AudioTrack? = null
        val tempFile = java.io.File(context.cacheDir, "tts_temp.mp3")
        try {
            tempFile.writeBytes(mp3Data)
            Log.d(TAG, "MiniMax playback temp file bytes=${mp3Data.size} header=${mp3Data.headerHex()}")

            extractor = MediaExtractor()
            extractor.setDataSource(tempFile.absolutePath)

            var audioTrackIndex = -1
            var mime = ""
            for (i in 0 until extractor.trackCount) {
                val format = extractor.getTrackFormat(i)
                val candidateMime = format.getString(MediaFormat.KEY_MIME) ?: continue
                if (candidateMime.startsWith("audio/")) {
                    audioTrackIndex = i
                    mime = candidateMime
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
            val channelMask = if (channelCount == 1) {
                AudioFormat.CHANNEL_OUT_MONO
            } else {
                AudioFormat.CHANNEL_OUT_STEREO
            }

            mediaCodec = MediaCodec.createDecoderByType(mime)
            mediaCodec.configure(format, null, null, 0)
            mediaCodec.start()
            codecStarted = true

            val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as android.media.AudioManager
            audioManager.mode = android.media.AudioManager.MODE_IN_COMMUNICATION
            audioManager.isSpeakerphoneOn = false

            val minBufferSize = AudioTrack.getMinBufferSize(
                sampleRate,
                channelMask,
                AudioFormat.ENCODING_PCM_16BIT
            )
            val bufferSize = if (minBufferSize > 0) minBufferSize else 4096

            track = AudioTrack.Builder()
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
                        .setChannelMask(channelMask)
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
                    } else {
                        buffer.position(0)
                        buffer.limit(sampleSize)
                        inputBuffer?.put(buffer)
                        mediaCodec.queueInputBuffer(inputBufferIndex, 0, sampleSize, extractor.sampleTime, 0)
                        extractor.advance()
                    }
                }

                val outputBufferIndex = mediaCodec.dequeueOutputBuffer(bufferInfo, 10000)
                if (outputBufferIndex >= 0) {
                    val outputBuffer = mediaCodec.getOutputBuffer(outputBufferIndex)
                    if (outputBuffer != null && bufferInfo.size > 0) {
                        val pcmData = ByteArray(bufferInfo.size)
                        outputBuffer.position(bufferInfo.offset)
                        outputBuffer.limit(bufferInfo.offset + bufferInfo.size)
                        outputBuffer.get(pcmData)
                        track.write(pcmData, 0, pcmData.size)
                    }
                    mediaCodec.releaseOutputBuffer(outputBufferIndex, false)

                    if (bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) {
                        break
                    }
                }
            }

            Log.d(TAG, "MiniMax TTS playback completed")
        } catch (e: Exception) {
            Log.e(TAG, "MP3 playback failed", e)
        } finally {
            try {
                track?.stop()
            } catch (_: Exception) {
            }
            track?.release()
            if (currentTrack === track) {
                currentTrack = null
            }
            try {
                if (codecStarted) mediaCodec?.stop()
            } catch (_: Exception) {
            }
            mediaCodec?.release()
            extractor?.release()
            tempFile.delete()
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

data class MiniMaxTtsAudio(
    val audioBytes: ByteArray,
    val traceId: String,
    val audioFormat: String,
    val audioSize: Int,
    val sampleRate: Int,
    val channelCount: Int,
)

object MiniMaxTtsResponseParser {
    fun parse(responseBody: String): MiniMaxTtsAudio {
        val root = JSONObject(responseBody)
        val traceId = root.optString("trace_id", "")
        val baseResp = root.optJSONObject("base_resp")
        val statusCode = baseResp?.optInt("status_code", 0) ?: 0
        val statusMsg = baseResp?.optString("status_msg", "") ?: ""
        if (statusCode != 0) {
            throw IllegalStateException(
                "MiniMax TTS provider error status_code=$statusCode status_msg=$statusMsg trace_id=$traceId"
            )
        }

        val audioHex = root.optJSONObject("data")
            ?.optString("audio", "")
            ?.trim()
            .orEmpty()
        if (audioHex.isEmpty()) {
            throw IllegalStateException("MiniMax TTS response missing data.audio trace_id=$traceId")
        }

        val audioBytes = decodeHex(audioHex)
        val extraInfo = root.optJSONObject("extra_info")
        return MiniMaxTtsAudio(
            audioBytes = audioBytes,
            traceId = traceId,
            audioFormat = extraInfo?.optString("audio_format", "mp3")?.ifBlank { "mp3" } ?: "mp3",
            audioSize = extraInfo?.optInt("audio_size", audioBytes.size) ?: audioBytes.size,
            sampleRate = extraInfo?.optInt("audio_sample_rate", 32000) ?: 32000,
            channelCount = extraInfo?.optInt("audio_channel", 1) ?: 1,
        )
    }

    private fun decodeHex(hex: String): ByteArray {
        val clean = hex.filterNot { it.isWhitespace() }
        require(clean.length % 2 == 0) { "MiniMax TTS audio hex has odd length" }
        return ByteArray(clean.length / 2) { index ->
            val high = Character.digit(clean[index * 2], 16)
            val low = Character.digit(clean[index * 2 + 1], 16)
            require(high >= 0 && low >= 0) { "MiniMax TTS audio contains non-hex characters" }
            ((high shl 4) or low).toByte()
        }
    }
}

private fun ByteArray.headerHex(maxBytes: Int = 8): String =
    take(maxBytes).joinToString(separator = "") { byte -> "%02x".format(byte) }
