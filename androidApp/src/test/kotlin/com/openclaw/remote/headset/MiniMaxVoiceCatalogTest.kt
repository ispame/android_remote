package com.openclaw.remote.headset

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class MiniMaxVoiceCatalogTest {
    @Test
    fun parsesAvailableVoicesFromMiniMaxGetVoiceResponse() {
        val voices = MiniMaxVoiceCatalog.parseGetVoiceResponse(
            """
            {
              "system_voice": [
                {
                  "voice_id": "Chinese (Mandarin)_Warm_Girl",
                  "voice_name": "温暖少女",
                  "description": ["标准普通话"]
                }
              ],
              "voice_cloning": [
                {
                  "voice_id": "my-cloned-voice",
                  "description": []
                }
              ],
              "voice_generation": [
                {
                  "voice_id": "ttv-voice-123",
                  "voice_name": ""
                }
              ],
              "base_resp": {
                "status_code": 0,
                "status_msg": "success"
              }
            }
            """.trimIndent()
        )

        assertEquals(
            listOf(
                MiniMaxVoiceOption("Chinese (Mandarin)_Warm_Girl", "温暖少女", "系统音色"),
                MiniMaxVoiceOption("my-cloned-voice", "my-cloned-voice", "复刻音色"),
                MiniMaxVoiceOption("ttv-voice-123", "ttv-voice-123", "文生音色"),
            ),
            voices,
        )
    }

    @Test
    fun builtinVoicesIncludeCurrentDefault() {
        assertTrue(MiniMaxVoiceCatalog.builtinVoices.any { it.id == MiniMaxVoiceCatalog.DEFAULT_VOICE_ID })
    }

    @Test
    fun selectableVoicesPreferFetchedListAndRemoveDuplicates() {
        val voices = MiniMaxVoiceCatalog.buildSelectableVoices(
            currentVoiceId = "male-qn-qingse",
            fetchedVoices = listOf(
                MiniMaxVoiceOption("male-qn-qingse", "青涩青年音色", "系统音色"),
                MiniMaxVoiceOption("duplicate-a", "温暖少女", "系统音色"),
                MiniMaxVoiceOption("duplicate-b", "温暖少女", "系统音色"),
            ),
        )

        assertEquals(
            listOf(
                MiniMaxVoiceOption("male-qn-qingse", "青涩青年音色", "系统音色"),
                MiniMaxVoiceOption("duplicate-a", "温暖少女", "系统音色"),
            ),
            voices,
        )
    }
}
