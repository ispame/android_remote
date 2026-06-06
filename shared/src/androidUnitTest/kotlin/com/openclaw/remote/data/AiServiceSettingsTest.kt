package com.openclaw.remote.data

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse

class AiServiceSettingsTest {
    @Test
    fun resolvesGlobalDefaultsAndAgentOverrides() {
        val settings = AiServiceSettings(
            defaults = AiServiceDefaults(
                llm = AiServiceChoice(mode = "router", profileId = "default"),
                asr = AiServiceChoice(mode = "router", profileId = "volcengine-streaming"),
                tts = AiServiceChoice(mode = "byok", providerId = "minimax", voiceId = "male-qn-qingse"),
            ),
            agentOverrides = mapOf(
                "profile-openclaw" to AiAgentOverride(
                    inherit = false,
                    asr = AiServiceChoice(mode = "backend", profileId = ""),
                )
            )
        )

        val resolved = settings.resolvedForAgent("profile-openclaw")

        assertEquals("router", resolved.llm.mode)
        assertEquals("default", resolved.llm.profileId)
        assertEquals("backend", resolved.asr.mode)
        assertEquals("", resolved.asr.profileId)
        assertEquals("minimax", resolved.tts.providerId)
    }

    @Test
    fun serializesWithoutCredentialFields() {
        val encoded = encodeAiServiceSettings(
            AiServiceSettings(
                defaults = AiServiceDefaults(
                    tts = AiServiceChoice(mode = "byok", providerId = "minimax", voiceId = "male-qn-qingse"),
                )
            )
        )

        assertFalse(encoded.contains("apiKey", ignoreCase = true))
        assertFalse(encoded.contains("secret", ignoreCase = true))
        assertEquals("minimax", decodeAiServiceSettings(encoded).defaults.tts.providerId)
    }
}
