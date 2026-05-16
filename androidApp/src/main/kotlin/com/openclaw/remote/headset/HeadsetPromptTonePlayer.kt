package com.openclaw.remote.headset

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import android.util.Log
import kotlin.math.PI
import kotlin.math.sin

class HeadsetPromptTonePlayer {
    private var currentTrack: AudioTrack? = null

    fun play(frequency: Double = 880.0, duration: Float = 0.12f) {
        try {
            val sampleRate = 44_100
            val numSamples = (sampleRate * duration).toInt()
            if (numSamples <= 0) return

            val samples = ShortArray(numSamples)
            for (i in 0 until numSamples) {
                val progress = i.toDouble() / numSamples
                val envelope = sin(PI * progress)
                val sample = sin(2.0 * PI * frequency * i / sampleRate) * envelope * 0.6
                samples[i] = (sample * Short.MAX_VALUE).toInt().coerceIn(Short.MIN_VALUE.toInt(), Short.MAX_VALUE.toInt()).toShort()
            }

            val bufferSize = samples.size * 2
            val audioTrack = AudioTrack.Builder()
                .setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_MEDIA)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build()
                )
                .setAudioFormat(
                    AudioFormat.Builder()
                        .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                        .setSampleRate(sampleRate)
                        .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                        .build()
                )
                .setBufferSizeInBytes(bufferSize)
                .setTransferMode(AudioTrack.MODE_STATIC)
                .build()

            audioTrack.write(samples, 0, samples.size)
            audioTrack.play()

            currentTrack?.release()
            currentTrack = audioTrack

            Log.d("PromptTone", "Playing tone: freq=$frequency duration=$duration")
        } catch (e: Exception) {
            Log.e("PromptTone", "Failed to play tone", e)
        }
    }
}