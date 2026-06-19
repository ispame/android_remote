package com.openclaw.remote.data

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

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
    fun preferredProviderUsesSavedCredentialBeforeListOrder() {
        val preferred = AiProviderCatalog.llmProviders.preferredBySavedCredential(
            currentProviderId = "openai-compatible",
            hasCredential = { it == "llm:kimi" },
        )

        assertEquals("kimi", preferred?.id)

        val fallback = AiProviderCatalog.llmProviders.preferredBySavedCredential(
            currentProviderId = "claude",
            hasCredential = { false },
        )

        assertEquals("claude", fallback?.id)
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

    @Test
    fun decodesV2ServiceLibraryAndSceneSelectionsWithoutSecrets() {
        val decoded = decodeAiServiceSettings(
            """
            {
              "version": 2,
              "serviceConfigs": {
                "llm": [
                  {
                    "id": "llm-router-default",
                    "capability": "llm",
                    "mode": "router",
                    "providerId": "router",
                    "profileId": "default",
                    "apiKey": "must-not-persist"
                  },
                  {
                    "id": "llm-byok-openai",
                    "capability": "llm",
                    "mode": "byok",
                    "providerId": "openai-compatible",
                    "baseUrl": "https://api.example.com/v1/",
                    "model": "gpt-test",
                    "credentialId": "llm:openai-compatible",
                    "apiKey": "must-not-persist"
                  }
                ],
                "asr": [
                  {
                    "id": "asr-agent-backend",
                    "capability": "asr",
                    "mode": "backend",
                    "providerId": "agent"
                  }
                ],
                "tts": [
                  {
                    "id": "tts-system",
                    "capability": "tts",
                    "mode": "system",
                    "providerId": "system"
                  },
                  {
                    "id": "tts-router-coming-soon",
                    "capability": "tts",
                    "mode": "router",
                    "providerId": "router",
                    "enabled": true,
                    "status": "available"
                  }
                ]
              },
              "sceneSelections": {
                "providerChat": { "llmConfigId": "llm-byok-openai" },
                "recording": { "asrConfigId": "asr-agent-backend" },
                "playback": { "ttsConfigId": "tts-router-coming-soon" },
                "agentOverrides": {
                  "profile-openclaw": {
                    "inherit": false,
                    "llmConfigId": "llm-router-default",
                    "asrConfigId": "asr-agent-backend",
                    "ttsConfigId": "tts-system"
                  }
                }
              }
            }
            """.trimIndent()
        )

        assertEquals(2, decoded.version)
        assertEquals("llm-byok-openai", decoded.sceneSelections.providerChat.llmConfigId)
        assertEquals("asr-agent-backend", decoded.sceneSelections.recording.asrConfigId)
        assertEquals("tts-system", decoded.sceneSelections.playback.ttsConfigId)
        assertEquals("byok", decoded.defaults.llm.mode)
        assertEquals("https://api.example.com/v1", decoded.defaults.llm.baseUrl)
        assertEquals("backend", decoded.defaults.asr.mode)
        assertEquals("system", decoded.defaults.tts.mode)
        assertEquals(false, decoded.serviceConfigs.tts.first { it.id == "tts-router-coming-soon" }.enabled)
        assertEquals("coming_soon", decoded.serviceConfigs.tts.first { it.id == "tts-router-coming-soon" }.status)
        assertEquals("llm-router-default", decoded.sceneSelections.agentOverrides["profile-openclaw"]?.llmConfigId)

        val encoded = encodeAiServiceSettings(decoded)
        assertTrue(encoded.contains("serviceConfigs"))
        assertTrue(encoded.contains("sceneSelections"))
        assertFalse(encoded.contains("must-not-persist"))
        assertFalse(encoded.contains("apiKey", ignoreCase = true))
    }

    @Test
    fun migratesLegacyDefaultsIntoServiceLibraryAndSceneSelections() {
        val decoded = decodeAiServiceSettings(
            """
            {
              "defaults": {
                "llm": {
                  "mode": "byok",
                  "providerId": "minimax",
                  "baseUrl": "https://api.minimax.com/v1/",
                  "model": "MiniMax-M2.7",
                  "credentialId": "llm:minimax"
                },
                "asr": { "mode": "router", "profileId": "volcengine-streaming" },
                "tts": { "mode": "system", "providerId": "system" }
              }
            }
            """.trimIndent()
        )

        assertEquals(2, decoded.version)
        assertEquals("llm-byok-minimax", decoded.sceneSelections.providerChat.llmConfigId)
        assertEquals("asr-router-volcengine-streaming", decoded.sceneSelections.recording.asrConfigId)
        assertEquals("tts-system", decoded.sceneSelections.playback.ttsConfigId)
        assertTrue(decoded.serviceConfigs.llm.any { it.id == "llm-byok-minimax" })
        assertEquals("https://api.minimaxi.com/v1", decoded.defaults.llm.baseUrl)
    }
}
