package com.openclaw.remote.data

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put

data class AiServiceChoice(
    val mode: String,
    val profileId: String = "",
    val providerId: String = "",
    val voiceId: String = "",
)

data class AiServiceDefaults(
    val llm: AiServiceChoice = AiServiceChoice(mode = "router", profileId = "default"),
    val asr: AiServiceChoice = AiServiceChoice(mode = "router", profileId = ""),
    val tts: AiServiceChoice = AiServiceChoice(mode = "system", providerId = "system", voiceId = "male-qn-qingse"),
)

data class AiAgentOverride(
    val inherit: Boolean = true,
    val llm: AiServiceChoice? = null,
    val asr: AiServiceChoice? = null,
    val tts: AiServiceChoice? = null,
)

data class AiServiceSettings(
    val defaults: AiServiceDefaults = AiServiceDefaults(),
    val agentOverrides: Map<String, AiAgentOverride> = emptyMap(),
) {
    fun resolvedForAgent(profileId: String): AiServiceDefaults {
        val override = agentOverrides[profileId] ?: return defaults
        if (override.inherit) return defaults
        return AiServiceDefaults(
            llm = override.llm ?: defaults.llm,
            asr = override.asr ?: defaults.asr,
            tts = override.tts ?: defaults.tts,
        )
    }
}

interface CredentialVault {
    suspend fun get(id: String): String?
    suspend fun set(id: String, secret: String)
    suspend fun remove(id: String)
}

const val LOCAL_TTS_MINIMAX_CREDENTIAL_ID = "tts:minimax"

private val aiSettingsJson = Json {
    ignoreUnknownKeys = true
}

fun encodeAiServiceSettings(settings: AiServiceSettings): String =
    encodeSettings(settings.normalized()).toString()

fun decodeAiServiceSettings(raw: String?): AiServiceSettings =
    runCatching {
        if (raw.isNullOrBlank()) {
            AiServiceSettings()
        } else {
            decodeSettings(aiSettingsJson.parseToJsonElement(raw).jsonObject)
        }.normalized()
    }.getOrDefault(AiServiceSettings())

fun AiServiceSettings.normalized(): AiServiceSettings =
    copy(
        defaults = AiServiceDefaults(
            llm = defaults.llm.normalized(fallback = AiServiceDefaults().llm),
            asr = defaults.asr.normalized(fallback = AiServiceDefaults().asr),
            tts = defaults.tts.normalized(fallback = AiServiceDefaults().tts),
        ),
        agentOverrides = agentOverrides
            .filterKeys { it.isNotBlank() }
            .mapValues { (_, value) ->
                value.copy(
                    llm = value.llm?.normalized(defaults.llm),
                    asr = value.asr?.normalized(defaults.asr),
                    tts = value.tts?.normalized(defaults.tts),
                )
            },
    )

fun aiSettingsFromLegacyConfig(config: GatewayConfig): AiServiceSettings =
    AiServiceSettings(
        defaults = AiServiceDefaults(
            llm = AiServiceChoice(mode = "router", profileId = "default"),
            asr = AiServiceChoice(
                mode = if (config.asrMode == "backend") "backend" else "router",
                profileId = if (config.asrMode == "backend") "" else config.asrProfileId,
            ),
            tts = legacyTtsChoice(config.ttsEngine, config.minimaxVoiceId),
        ),
    ).normalized()

fun legacyTtsChoice(engine: String, voiceId: String): AiServiceChoice =
    if (engine == "minimax") {
        AiServiceChoice(
            mode = "byok",
            providerId = "minimax",
            voiceId = voiceId.ifBlank { "male-qn-qingse" },
        )
    } else {
        AiServiceChoice(mode = "system", providerId = "system", voiceId = "male-qn-qingse")
    }

fun AiServiceChoice.toLegacyTtsEngine(): String =
    if (mode == "byok" && providerId == "minimax") "minimax" else "system"

private fun AiServiceChoice.normalized(fallback: AiServiceChoice): AiServiceChoice =
    AiServiceChoice(
        mode = mode.ifBlank { fallback.mode },
        profileId = profileId,
        providerId = providerId.ifBlank { fallback.providerId },
        voiceId = voiceId.ifBlank { fallback.voiceId },
    )

private fun encodeSettings(settings: AiServiceSettings): JsonObject =
    buildJsonObject {
        put("defaults", encodeDefaults(settings.defaults))
        put(
            "agentOverrides",
            buildJsonObject {
                settings.agentOverrides.forEach { (profileId, override) ->
                    put(
                        profileId,
                        buildJsonObject {
                            put("inherit", override.inherit)
                            override.llm?.let { put("llm", encodeChoice(it)) }
                            override.asr?.let { put("asr", encodeChoice(it)) }
                            override.tts?.let { put("tts", encodeChoice(it)) }
                        }
                    )
                }
            }
        )
    }

private fun encodeDefaults(defaults: AiServiceDefaults): JsonObject =
    buildJsonObject {
        put("llm", encodeChoice(defaults.llm))
        put("asr", encodeChoice(defaults.asr))
        put("tts", encodeChoice(defaults.tts))
    }

private fun encodeChoice(choice: AiServiceChoice): JsonObject =
    buildJsonObject {
        put("mode", choice.mode)
        put("profileId", choice.profileId)
        put("providerId", choice.providerId)
        put("voiceId", choice.voiceId)
    }

private fun decodeSettings(obj: JsonObject): AiServiceSettings =
    AiServiceSettings(
        defaults = decodeDefaults(obj["defaults"]?.jsonObjectOrNull()),
        agentOverrides = obj["agentOverrides"]
            ?.jsonObjectOrNull()
            ?.mapValues { (_, value) -> decodeOverride(value.jsonObjectOrNull()) }
            .orEmpty(),
    )

private fun decodeDefaults(obj: JsonObject?): AiServiceDefaults =
    AiServiceDefaults(
        llm = decodeChoice(obj?.get("llm")?.jsonObjectOrNull(), AiServiceDefaults().llm),
        asr = decodeChoice(obj?.get("asr")?.jsonObjectOrNull(), AiServiceDefaults().asr),
        tts = decodeChoice(obj?.get("tts")?.jsonObjectOrNull(), AiServiceDefaults().tts),
    )

private fun decodeOverride(obj: JsonObject?): AiAgentOverride =
    AiAgentOverride(
        inherit = obj?.get("inherit")?.jsonPrimitive?.booleanOrNull ?: true,
        llm = obj?.get("llm")?.jsonObjectOrNull()?.let { decodeChoice(it, AiServiceDefaults().llm) },
        asr = obj?.get("asr")?.jsonObjectOrNull()?.let { decodeChoice(it, AiServiceDefaults().asr) },
        tts = obj?.get("tts")?.jsonObjectOrNull()?.let { decodeChoice(it, AiServiceDefaults().tts) },
    )

private fun decodeChoice(obj: JsonObject?, fallback: AiServiceChoice): AiServiceChoice =
    AiServiceChoice(
        mode = obj.stringValue("mode").ifBlank { fallback.mode },
        profileId = obj.stringValueOrFallback("profileId", fallback.profileId),
        providerId = obj.stringValueOrFallback("providerId", fallback.providerId),
        voiceId = obj.stringValueOrFallback("voiceId", fallback.voiceId),
    )

private fun JsonObject?.stringValue(name: String): String =
    this?.get(name)?.jsonPrimitive?.contentOrNull.orEmpty()

private fun JsonObject?.stringValueOrFallback(name: String, fallback: String): String =
    if (this?.containsKey(name) == true) stringValue(name) else fallback

private fun JsonElement.jsonObjectOrNull(): JsonObject? =
    this as? JsonObject
