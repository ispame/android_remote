package com.openclaw.remote.data

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull

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
                    llm = AiServiceChoice(
                        mode = "byok",
                        providerId = "openai-compatible",
                        baseUrl = "https://api.example.com/v1",
                        model = "gpt-test",
                        credentialId = "llm:openai-compatible",
                        displayName = "OpenAI-compatible",
                    ),
                    tts = AiServiceChoice(
                        mode = "byok",
                        providerId = "minimax",
                        voiceId = "male-qn-qingse",
                        credentialId = "tts:minimax",
                        displayName = "MiniMax",
                    ),
                )
            )
        )

        assertFalse(encoded.contains("apiKey", ignoreCase = true))
        assertFalse(encoded.contains("secret", ignoreCase = true))
        val decoded = decodeAiServiceSettings(encoded)
        assertEquals("minimax", decoded.defaults.tts.providerId)
        assertEquals("https://api.example.com/v1", decoded.defaults.llm.baseUrl)
        assertEquals("gpt-test", decoded.defaults.llm.model)
        assertEquals("llm:openai-compatible", decoded.defaults.llm.credentialId)
        assertEquals("OpenAI-compatible", decoded.defaults.llm.displayName)
    }

    @Test
    fun providerCatalogIncludesIosVisibleDefaults() {
        assertNotNull(AiProviderCatalog.llmProviders.firstOrNull { it.id == "openai-compatible" })
        assertNotNull(AiProviderCatalog.llmProviders.firstOrNull { it.id == "claude" })
        assertNotNull(AiProviderCatalog.asrProviders.firstOrNull { it.id == "openai-compatible-asr" })
        assertNotNull(AiProviderCatalog.ttsProviders.firstOrNull { it.id == "minimax" })
    }

    @Test
    fun resolvesAgentOverrideWithExpandedChoiceFields() {
        val settings = AiServiceSettings(
            defaults = AiServiceDefaults(
                llm = AiServiceChoice(
                    mode = "router",
                    profileId = "default",
                    providerId = "router",
                    model = "router-default",
                    displayName = "Boson Router",
                )
            ),
            agentOverrides = mapOf(
                "profile-hermes" to AiAgentOverride(
                    inherit = false,
                    llm = AiServiceChoice(
                        mode = "byok",
                        providerId = "claude",
                        baseUrl = "https://api.anthropic.com/v1",
                        model = "claude-sonnet",
                        credentialId = "llm:claude",
                        displayName = "Claude",
                    )
                )
            ),
        )

        val resolved = settings.resolvedForAgent("profile-hermes")

        assertEquals("byok", resolved.llm.mode)
        assertEquals("claude", resolved.llm.providerId)
        assertEquals("https://api.anthropic.com/v1", resolved.llm.baseUrl)
        assertEquals("claude-sonnet", resolved.llm.model)
        assertEquals("llm:claude", resolved.llm.credentialId)
        assertEquals("Claude", resolved.llm.displayName)
    }
}
