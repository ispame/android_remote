package com.openclaw.remote.headset

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class MiniMaxTtsResponseParserTest {
    @Test
    fun requestBuilderUsesSelectedVoiceId() {
        val json = MiniMaxTtsRequestBuilder.build(
            text = "你好",
            voiceId = "Chinese (Mandarin)_Warm_Girl",
        )

        assertEquals(
            "Chinese (Mandarin)_Warm_Girl",
            json.getJSONObject("voice_setting").getString("voice_id"),
        )
        assertEquals("hex", json.getString("output_format"))
    }

    @Test
    fun parsesHexEncodedAudioFromNonStreamingResponse() {
        val parsed = MiniMaxTtsResponseParser.parse(
            """
            {
              "data": {
                "audio": "4944330400",
                "status": 2
              },
              "extra_info": {
                "audio_sample_rate": 32000,
                "audio_size": 5,
                "audio_format": "mp3",
                "audio_channel": 1
              },
              "trace_id": "trace-123",
              "base_resp": {
                "status_code": 0,
                "status_msg": "success"
              }
            }
            """.trimIndent()
        )

        assertArrayEquals(byteArrayOf(0x49, 0x44, 0x33, 0x04, 0x00), parsed.audioBytes)
        assertEquals("trace-123", parsed.traceId)
        assertEquals("mp3", parsed.audioFormat)
        assertEquals(5, parsed.audioSize)
        assertEquals(32000, parsed.sampleRate)
        assertEquals(1, parsed.channelCount)
    }

    @Test
    fun rejectsProviderErrorsWithTraceId() {
        val error = runCatching {
            MiniMaxTtsResponseParser.parse(
                """
                {
                  "trace_id": "trace-error",
                  "base_resp": {
                    "status_code": 1004,
                    "status_msg": "auth failed"
                  }
                }
                """.trimIndent()
            )
        }.exceptionOrNull()

        assertTrue(error is IllegalStateException)
        assertTrue(error?.message.orEmpty().contains("1004"))
        assertTrue(error?.message.orEmpty().contains("auth failed"))
        assertTrue(error?.message.orEmpty().contains("trace-error"))
    }
}
