package com.openclaw.remote.data

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put

data class AiServiceChoice(
    val mode: String,
    val profileId: String = "",
    val providerId: String = "",
    val voiceId: String = "",
    val baseUrl: String = "",
    val model: String = "",
    val credentialId: String = "",
    val displayName: String = "",
)

data class AiServiceConfig(
    val id: String,
    val capability: String,
    val mode: String,
    val profileId: String = "",
    val providerId: String = "",
    val voiceId: String = "",
    val baseUrl: String = "",
    val model: String = "",
    val credentialId: String = "",
    val displayName: String = "",
    val enabled: Boolean = true,
    val status: String = "available",
)

data class AiServiceLibrary(
    val llm: List<AiServiceConfig> = emptyList(),
    val asr: List<AiServiceConfig> = emptyList(),
    val tts: List<AiServiceConfig> = emptyList(),
) {
    fun isEmpty(): Boolean = llm.isEmpty() && asr.isEmpty() && tts.isEmpty()
}

data class AiProviderChatSelection(
    val llmConfigId: String = "",
)

data class AiRecordingSelection(
    val asrConfigId: String = "",
)

data class AiPlaybackSelection(
    val ttsConfigId: String = "",
)

data class AiSceneAgentOverride(
    val inherit: Boolean = true,
    val llmConfigId: String = "",
    val asrConfigId: String = "",
    val ttsConfigId: String = "",
)

data class AiSceneSelections(
    val providerChat: AiProviderChatSelection = AiProviderChatSelection(),
    val recording: AiRecordingSelection = AiRecordingSelection(),
    val playback: AiPlaybackSelection = AiPlaybackSelection(),
    val agentOverrides: Map<String, AiSceneAgentOverride> = emptyMap(),
)

data class AiServiceDefaults(
    val llm: AiServiceChoice = AiServiceChoice(mode = "router", profileId = "default", providerId = "router", displayName = "Boson Router"),
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
    val version: Int = 2,
    val serviceConfigs: AiServiceLibrary = AiServiceLibrary(),
    val sceneSelections: AiSceneSelections = AiSceneSelections(),
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

data class AiProviderDescriptor(
    val id: String,
    val displayName: String,
    val mode: String,
    val baseUrl: String = "",
    val defaultModel: String = "",
    val credentialId: String = "",
)

object AiProviderCatalog {
    val llmProviders: List<AiProviderDescriptor> = listOf(
        AiProviderDescriptor(
            id = "router",
            displayName = "Boson Router",
            mode = "router",
            defaultModel = "router-default",
        ),
        AiProviderDescriptor(
            id = "openai-compatible",
            displayName = "OpenAI Compatible",
            mode = "byok",
            baseUrl = "https://api.openai.com/v1",
            defaultModel = "gpt-4o-mini",
            credentialId = "llm:openai-compatible",
        ),
        AiProviderDescriptor(
            id = "minimax",
            displayName = "MiniMax",
            mode = "byok",
            baseUrl = "https://api.minimaxi.com/v1",
            defaultModel = "MiniMax-M2.7",
            credentialId = "llm:minimax",
        ),
        AiProviderDescriptor(
            id = "kimi",
            displayName = "Kimi",
            mode = "byok",
            baseUrl = "https://api.moonshot.ai/v1",
            defaultModel = "moonshot-v1-8k",
            credentialId = "llm:kimi",
        ),
        AiProviderDescriptor(
            id = "claude",
            displayName = "Claude",
            mode = "byok",
            baseUrl = "https://api.anthropic.com/v1",
            defaultModel = "claude-sonnet-4-20250514",
            credentialId = "llm:claude",
        ),
        AiProviderDescriptor(
            id = "doubao",
            displayName = "Doubao",
            mode = "byok",
            baseUrl = "https://ark.cn-beijing.volces.com/api/v3",
            defaultModel = "doubao-seed-2-0-lite-260215",
            credentialId = "llm:doubao",
        ),
    )

    val asrProviders: List<AiProviderDescriptor> = listOf(
        AiProviderDescriptor(id = "router", displayName = "Boson Router ASR", mode = "router"),
        AiProviderDescriptor(id = "backend", displayName = "Agent Backend ASR", mode = "backend"),
        AiProviderDescriptor(
            id = "openai-compatible-asr",
            displayName = "OpenAI Compatible ASR",
            mode = "byok",
            baseUrl = "https://api.openai.com/v1",
            defaultModel = "whisper-1",
            credentialId = "asr:openai-compatible",
        ),
    )

    val ttsProviders: List<AiProviderDescriptor> = listOf(
        AiProviderDescriptor(id = "system", displayName = "System TTS", mode = "system"),
        AiProviderDescriptor(
            id = "minimax",
            displayName = "MiniMax",
            mode = "byok",
            baseUrl = "https://api.minimaxi.com/v1",
            defaultModel = "speech-2.8-hd",
            credentialId = LOCAL_TTS_MINIMAX_CREDENTIAL_ID,
        ),
    )
}

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
    if (serviceConfigs.isEmpty()) {
        migrateLegacyAiSettings(defaults, agentOverrides)
    } else {
        normalizeV2AiSettings(this)
    }

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
            credentialId = LOCAL_TTS_MINIMAX_CREDENTIAL_ID,
            displayName = "MiniMax",
        )
    } else {
        AiServiceChoice(mode = "system", providerId = "system", voiceId = "male-qn-qingse", displayName = "System TTS")
    }

fun AiServiceChoice.toLegacyTtsEngine(): String =
    if (mode == "byok" && providerId == "minimax") "minimax" else "system"

fun AiServiceSettings.llmConfigForProviderChat(): AiServiceConfig? =
    serviceConfigs.llm.configById(sceneSelections.providerChat.llmConfigId)
        ?: serviceConfigs.llm.firstSelectable()

fun AiServiceSettings.asrConfigForRecording(): AiServiceConfig? =
    serviceConfigs.asr.configById(sceneSelections.recording.asrConfigId)
        ?: serviceConfigs.asr.firstSelectable()

fun AiServiceSettings.ttsConfigForPlayback(): AiServiceConfig? =
    serviceConfigs.tts.configById(sceneSelections.playback.ttsConfigId)
        ?: serviceConfigs.tts.firstSelectable()

fun AiServiceConfig.toAiServiceChoice(): AiServiceChoice = toChoice()

fun AiServiceChoice.toAiServiceConfig(capability: String, id: String = ""): AiServiceConfig =
    toServiceConfig(capability.normalizedCapability())
        .copy(id = id.ifBlank { configIdForChoice(capability.normalizedCapability(), this) })
        .normalized(capability.normalizedCapability())

fun AiServiceConfig.isSelectableServiceConfig(): Boolean = isSelectable()

fun List<AiProviderDescriptor>.preferredBySavedCredential(
    currentProviderId: String,
    hasCredential: (String) -> Boolean,
): AiProviderDescriptor? {
    firstOrNull { provider ->
        provider.credentialId.isNotBlank() && hasCredential(provider.credentialId)
    }?.let { return it }
    return firstOrNull { it.id == currentProviderId } ?: firstOrNull()
}

fun AiServiceSettings.upsertingServiceConfig(config: AiServiceConfig): AiServiceSettings {
    val normalizedConfig = config.normalized(config.capability.normalizedCapability())
    val nextLibrary = when (normalizedConfig.capability) {
        "asr" -> serviceConfigs.copy(asr = serviceConfigs.asr.upsertById(normalizedConfig))
        "tts" -> serviceConfigs.copy(tts = serviceConfigs.tts.upsertById(normalizedConfig))
        else -> serviceConfigs.copy(llm = serviceConfigs.llm.upsertById(normalizedConfig))
    }
    return copy(serviceConfigs = nextLibrary).normalized()
}

fun AiServiceSettings.deletingServiceConfig(configId: String): AiServiceSettings {
    val nextLibrary = serviceConfigs.copy(
        llm = serviceConfigs.llm.filterNot { it.id == configId },
        asr = serviceConfigs.asr.filterNot { it.id == configId },
        tts = serviceConfigs.tts.filterNot { it.id == configId },
    )
    val nextSelections = sceneSelections.copy(
        providerChat = if (sceneSelections.providerChat.llmConfigId == configId) AiProviderChatSelection() else sceneSelections.providerChat,
        recording = if (sceneSelections.recording.asrConfigId == configId) AiRecordingSelection() else sceneSelections.recording,
        playback = if (sceneSelections.playback.ttsConfigId == configId) AiPlaybackSelection() else sceneSelections.playback,
        agentOverrides = sceneSelections.agentOverrides.mapValues { (_, override) ->
            override.copy(
                llmConfigId = override.llmConfigId.takeIf { it != configId }.orEmpty(),
                asrConfigId = override.asrConfigId.takeIf { it != configId }.orEmpty(),
                ttsConfigId = override.ttsConfigId.takeIf { it != configId }.orEmpty(),
            )
        },
    )
    return copy(serviceConfigs = nextLibrary, sceneSelections = nextSelections).normalized()
}

fun AiServiceSettings.updatingSceneSelection(
    providerChatLlmConfigId: String? = null,
    recordingAsrConfigId: String? = null,
    playbackTtsConfigId: String? = null,
): AiServiceSettings =
    copy(
        sceneSelections = sceneSelections.copy(
            providerChat = providerChatLlmConfigId?.let { AiProviderChatSelection(it) } ?: sceneSelections.providerChat,
            recording = recordingAsrConfigId?.let { AiRecordingSelection(it) } ?: sceneSelections.recording,
            playback = playbackTtsConfigId?.let { AiPlaybackSelection(it) } ?: sceneSelections.playback,
        )
    ).normalized()

private fun normalizeV2AiSettings(settings: AiServiceSettings): AiServiceSettings {
    val library = AiServiceLibrary(
        llm = settings.serviceConfigs.llm.map { it.normalized("llm") }.distinctById(),
        asr = settings.serviceConfigs.asr.map { it.normalized("asr") }.distinctById(),
        tts = settings.serviceConfigs.tts.map { it.normalized("tts") }.distinctById(),
    ).withCoreConfigs()
    val selections = settings.sceneSelections.normalized(library)
    return AiServiceSettings(
        version = 2,
        serviceConfigs = library,
        sceneSelections = selections,
        defaults = library.projectDefaults(selections),
        agentOverrides = library.projectAgentOverrides(selections),
    )
}

private fun migrateLegacyAiSettings(
    defaults: AiServiceDefaults,
    agentOverrides: Map<String, AiAgentOverride>,
): AiServiceSettings {
    val library = MutableAiServiceLibrary()
    val normalizedDefaults = AiServiceDefaults(
        llm = defaults.llm.normalized(AiServiceDefaults().llm),
        asr = defaults.asr.normalized(AiServiceDefaults().asr),
        tts = defaults.tts.normalized(AiServiceDefaults().tts),
    )
    val llmConfigId = library.add("llm", normalizedDefaults.llm)
    val asrConfigId = library.add("asr", normalizedDefaults.asr)
    val ttsConfigId = library.add("tts", normalizedDefaults.tts)
    val sceneOverrides = agentOverrides
        .filterKeys { it.isNotBlank() }
        .mapValues { (_, override) ->
            AiSceneAgentOverride(
                inherit = override.inherit,
                llmConfigId = override.llm?.let { library.add("llm", it.normalized(normalizedDefaults.llm)) }.orEmpty(),
                asrConfigId = override.asr?.let { library.add("asr", it.normalized(normalizedDefaults.asr)) }.orEmpty(),
                ttsConfigId = override.tts?.let { library.add("tts", it.normalized(normalizedDefaults.tts)) }.orEmpty(),
            )
        }
    return normalizeV2AiSettings(
        AiServiceSettings(
            version = 2,
            serviceConfigs = library.toLibrary(),
            sceneSelections = AiSceneSelections(
                providerChat = AiProviderChatSelection(llmConfigId),
                recording = AiRecordingSelection(asrConfigId),
                playback = AiPlaybackSelection(ttsConfigId),
                agentOverrides = sceneOverrides,
            ),
        )
    )
}

private class MutableAiServiceLibrary {
    private val llm = linkedMapOf<String, AiServiceConfig>()
    private val asr = linkedMapOf<String, AiServiceConfig>()
    private val tts = linkedMapOf<String, AiServiceConfig>()

    fun add(capability: String, choice: AiServiceChoice): String {
        val normalizedCapability = capability.normalizedCapability()
        val config = choice.toServiceConfig(normalizedCapability).normalized(normalizedCapability)
        when (normalizedCapability) {
            "asr" -> asr[config.id] = config
            "tts" -> tts[config.id] = config
            else -> llm[config.id] = config
        }
        return config.id
    }

    fun toLibrary(): AiServiceLibrary =
        AiServiceLibrary(llm = llm.values.toList(), asr = asr.values.toList(), tts = tts.values.toList())
}

private fun AiServiceChoice.toServiceConfig(capability: String): AiServiceConfig =
    AiServiceConfig(
        id = configIdForChoice(capability, this),
        capability = capability,
        mode = mode,
        profileId = profileId,
        providerId = providerId,
        voiceId = voiceId,
        baseUrl = baseUrl,
        model = model,
        credentialId = credentialId,
        displayName = displayName,
    )

private fun AiServiceConfig.normalized(expectedCapability: String): AiServiceConfig {
    val capability = expectedCapability.normalizedCapability()
    val normalizedMode = mode.normalizedMode(capability)
    var nextProviderId = providerId.trim()
    var nextProfileId = profileId.trim()
    var nextVoiceId = voiceId.trim()
    var nextBaseUrl = baseUrl.trim().trimEnd('/')
    var nextModel = model.trim()
    var nextCredentialId = credentialId.trim()
    var nextEnabled = enabled
    var nextStatus = status.trim().ifBlank { "available" }

    when (normalizedMode) {
        "router" -> {
            nextProviderId = "router"
            nextBaseUrl = ""
            nextModel = ""
            nextCredentialId = ""
            if (capability == "tts") {
                nextEnabled = false
                nextStatus = "coming_soon"
            }
        }
        "byok" -> {
            nextProviderId = nextProviderId.ifBlank { capability.defaultByokProviderId() }
            nextBaseUrl = normalizeProviderBaseUrl(capability, nextProviderId, nextBaseUrl)
            nextModel = nextModel.ifBlank { defaultModel(capability, nextProviderId) }
            nextCredentialId = nextCredentialId.ifBlank { "$capability:$nextProviderId" }
        }
        "backend", "agent" -> {
            nextProviderId = "agent"
            nextProfileId = ""
            nextBaseUrl = ""
            nextModel = ""
            nextCredentialId = ""
        }
        "system" -> {
            nextProviderId = "system"
            nextProfileId = ""
            nextBaseUrl = ""
            nextModel = ""
            nextCredentialId = ""
        }
    }
    if (nextStatus != "coming_soon" && nextStatus != "disabled") {
        nextStatus = if (nextEnabled) "available" else "disabled"
    }
    return copy(
        id = id.ifBlank {
            configIdForChoice(
                capability,
                AiServiceChoice(
                    mode = normalizedMode,
                    profileId = nextProfileId,
                    providerId = nextProviderId,
                    baseUrl = nextBaseUrl,
                    model = nextModel,
                    credentialId = nextCredentialId,
                )
            )
        },
        capability = capability,
        mode = if (normalizedMode == "agent") "backend" else normalizedMode,
        profileId = nextProfileId,
        providerId = nextProviderId,
        voiceId = nextVoiceId,
        baseUrl = nextBaseUrl,
        model = nextModel,
        credentialId = nextCredentialId,
        displayName = displayName.ifBlank { inferDisplayName(capability, normalizedMode, nextProviderId) },
        enabled = nextEnabled,
        status = nextStatus,
    )
}

private fun AiSceneSelections.normalized(library: AiServiceLibrary): AiSceneSelections =
    AiSceneSelections(
        providerChat = AiProviderChatSelection(
            library.llm.validSelectableId(providerChat.llmConfigId).ifBlank { library.llm.firstSelectableId() }
        ),
        recording = AiRecordingSelection(
            library.asr.validSelectableId(recording.asrConfigId).ifBlank { library.asr.firstSelectableId() }
        ),
        playback = AiPlaybackSelection(
            library.tts.validSelectableId(playback.ttsConfigId).ifBlank { library.tts.firstSelectableId() }
        ),
        agentOverrides = agentOverrides
            .filterKeys { it.isNotBlank() }
            .mapValues { (_, override) ->
                AiSceneAgentOverride(
                    inherit = override.inherit,
                    llmConfigId = library.llm.validSelectableId(override.llmConfigId),
                    asrConfigId = library.asr.validSelectableId(override.asrConfigId),
                    ttsConfigId = library.tts.validSelectableId(override.ttsConfigId),
                )
            },
    )

private fun AiServiceLibrary.withCoreConfigs(): AiServiceLibrary =
    if (tts.any { it.id == "tts-system" }) {
        this
    } else {
        copy(
            tts = listOf(
                AiServiceConfig(
                    id = "tts-system",
                    capability = "tts",
                    mode = "system",
                    providerId = "system",
                    displayName = "System TTS",
                ).normalized("tts")
            ) + tts
        )
    }

private fun AiServiceLibrary.projectDefaults(selections: AiSceneSelections): AiServiceDefaults =
    AiServiceDefaults(
        llm = llm.configById(selections.providerChat.llmConfigId)?.toChoice() ?: AiServiceDefaults().llm,
        asr = asr.configById(selections.recording.asrConfigId)?.toChoice() ?: AiServiceDefaults().asr,
        tts = tts.configById(selections.playback.ttsConfigId)?.toChoice() ?: AiServiceDefaults().tts,
    )

private fun AiServiceLibrary.projectAgentOverrides(selections: AiSceneSelections): Map<String, AiAgentOverride> =
    selections.agentOverrides.mapValues { (_, override) ->
        AiAgentOverride(
            inherit = override.inherit,
            llm = llm.configById(override.llmConfigId)?.toChoice(),
            asr = asr.configById(override.asrConfigId)?.toChoice(),
            tts = tts.configById(override.ttsConfigId)?.toChoice(),
        )
    }

private fun AiServiceConfig.toChoice(): AiServiceChoice =
    when (mode) {
        "router" -> AiServiceChoice(
            mode = "router",
            profileId = profileId,
            providerId = "router",
            displayName = displayName,
        )
        "backend", "agent" -> AiServiceChoice(
            mode = "backend",
            providerId = "agent",
            displayName = displayName,
        )
        "system" -> AiServiceChoice(
            mode = "system",
            providerId = "system",
            voiceId = voiceId,
            displayName = displayName,
        )
        else -> AiServiceChoice(
            mode = mode,
            profileId = profileId,
            providerId = providerId,
            voiceId = voiceId,
            baseUrl = baseUrl,
            model = model,
            credentialId = credentialId,
            displayName = displayName,
        )
    }

private fun List<AiServiceConfig>.configById(id: String): AiServiceConfig? =
    firstOrNull { it.id == id }

private fun List<AiServiceConfig>.firstSelectable(): AiServiceConfig? =
    firstOrNull { it.isSelectable() }

private fun List<AiServiceConfig>.firstSelectableId(): String =
    firstSelectable()?.id ?: firstOrNull()?.id.orEmpty()

private fun List<AiServiceConfig>.validSelectableId(id: String): String =
    id.takeIf { candidate -> any { it.id == candidate && it.isSelectable() } }.orEmpty()

private fun List<AiServiceConfig>.distinctById(): List<AiServiceConfig> =
    fold(linkedMapOf<String, AiServiceConfig>()) { acc, config ->
        acc[config.id] = config
        acc
    }.values.toList()

private fun List<AiServiceConfig>.upsertById(config: AiServiceConfig): List<AiServiceConfig> =
    (filterNot { it.id == config.id } + config).distinctById()

private fun AiServiceConfig.isSelectable(): Boolean =
    enabled && status != "coming_soon" && status != "disabled"

private fun String.normalizedCapability(): String =
    when (this) {
        "asr" -> "asr"
        "tts" -> "tts"
        else -> "llm"
    }

private fun String.normalizedMode(capability: String): String =
    when (this) {
        "router", "byok", "backend", "agent", "system" -> this
        else -> if (capability == "tts") "system" else "router"
    }

private fun String.defaultByokProviderId(): String =
    if (this == "tts") "minimax" else "openai-compatible"

private fun configIdForChoice(capability: String, choice: AiServiceChoice): String {
    val mode = choice.mode.normalizedMode(capability)
    return when (mode) {
        "router" -> "$capability-router-${slug(choice.profileId.ifBlank { "default" })}"
        "byok" -> "$capability-byok-${slug(choice.providerId.ifBlank { "custom" })}"
        "system" -> "$capability-system"
        else -> "$capability-agent-backend"
    }
}

private fun normalizeProviderBaseUrl(capability: String, providerId: String, baseUrl: String): String {
    val fallback = baseUrl.ifBlank { defaultBaseUrl(capability, providerId) }
    return if (providerId == "minimax" && fallback == "https://api.minimax.com/v1") {
        "https://api.minimaxi.com/v1"
    } else {
        fallback
    }
}

private fun defaultBaseUrl(capability: String, providerId: String): String =
    when {
        providerId == "minimax" -> "https://api.minimaxi.com/v1"
        providerId == "kimi" -> "https://api.moonshot.ai/v1"
        providerId == "claude" -> "https://api.anthropic.com/v1"
        providerId == "doubao" -> "https://ark.cn-beijing.volces.com/api/v3"
        capability == "asr" -> "https://api.openai.com/v1"
        else -> "https://api.openai.com/v1"
    }

private fun defaultModel(capability: String, providerId: String): String =
    when {
        capability == "tts" && providerId == "minimax" -> "speech-2.8-hd"
        capability == "asr" -> "whisper-1"
        providerId == "minimax" -> "MiniMax-M2.7"
        providerId == "kimi" -> "moonshot-v1-8k"
        providerId == "claude" -> "claude-sonnet-4-20250514"
        providerId == "doubao" -> "doubao-seed-2-0-lite-260215"
        else -> "gpt-4o-mini"
    }

private fun inferDisplayName(capability: String, mode: String, providerId: String): String =
    when (mode) {
        "router" -> if (capability == "tts") "Router TTS" else "Router ${capability.uppercase()}"
        "backend", "agent" -> "Agent 后端识别"
        "system" -> "System TTS"
        else -> providerId.ifBlank { "BYOK" }
    }

private fun slug(value: String): String =
    value.trim().lowercase().replace(Regex("[^a-z0-9]+"), "-").trim('-').ifBlank { "default" }

private fun AiServiceChoice.normalized(fallback: AiServiceChoice): AiServiceChoice =
    AiServiceChoice(
        mode = mode.ifBlank { fallback.mode },
        profileId = profileId,
        providerId = if (mode == "router") "router" else providerId.ifBlank { fallback.providerId },
        voiceId = voiceId.ifBlank { fallback.voiceId },
        baseUrl = if (mode == "router") "" else normalizeProviderBaseUrl("llm", providerId, baseUrl.ifBlank { fallback.baseUrl }),
        model = model.ifBlank { fallback.model },
        credentialId = if (mode == "router") "" else credentialId.ifBlank { fallback.credentialId },
        displayName = displayName.ifBlank { fallback.displayName },
    )

private fun encodeSettings(settings: AiServiceSettings): JsonObject =
    buildJsonObject {
        put("version", 2)
        put("serviceConfigs", encodeServiceLibrary(settings.serviceConfigs))
        put("sceneSelections", encodeSceneSelections(settings.sceneSelections))
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

private fun encodeServiceLibrary(library: AiServiceLibrary): JsonObject =
    buildJsonObject {
        put("llm", encodeConfigList(library.llm))
        put("asr", encodeConfigList(library.asr))
        put("tts", encodeConfigList(library.tts))
    }

private fun encodeConfigList(configs: List<AiServiceConfig>): JsonArray =
    buildJsonArray {
        configs.forEach { config ->
            add(
                buildJsonObject {
                    put("id", config.id)
                    put("capability", config.capability)
                    put("mode", config.mode)
                    put("profileId", config.profileId)
                    put("providerId", config.providerId)
                    put("voiceId", config.voiceId)
                    put("baseUrl", config.baseUrl)
                    put("model", config.model)
                    put("credentialId", config.credentialId)
                    put("displayName", config.displayName)
                    put("enabled", config.enabled)
                    put("status", config.status)
                }
            )
        }
    }

private fun encodeSceneSelections(selections: AiSceneSelections): JsonObject =
    buildJsonObject {
        put(
            "providerChat",
            buildJsonObject {
                put("llmConfigId", selections.providerChat.llmConfigId)
            }
        )
        put(
            "recording",
            buildJsonObject {
                put("asrConfigId", selections.recording.asrConfigId)
            }
        )
        put(
            "playback",
            buildJsonObject {
                put("ttsConfigId", selections.playback.ttsConfigId)
            }
        )
        put(
            "agentOverrides",
            buildJsonObject {
                selections.agentOverrides.forEach { (profileId, override) ->
                    put(
                        profileId,
                        buildJsonObject {
                            put("inherit", override.inherit)
                            put("llmConfigId", override.llmConfigId)
                            put("asrConfigId", override.asrConfigId)
                            put("ttsConfigId", override.ttsConfigId)
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
        put("baseUrl", choice.baseUrl)
        put("model", choice.model)
        put("credentialId", choice.credentialId)
        put("displayName", choice.displayName)
    }

private fun decodeSettings(obj: JsonObject): AiServiceSettings =
    AiServiceSettings(
        version = obj["version"]?.jsonPrimitive?.intOrNull ?: 2,
        serviceConfigs = decodeServiceLibrary(obj["serviceConfigs"]?.jsonObjectOrNull()),
        sceneSelections = decodeSceneSelections(obj["sceneSelections"]?.jsonObjectOrNull()),
        defaults = decodeDefaults(obj["defaults"]?.jsonObjectOrNull()),
        agentOverrides = obj["agentOverrides"]
            ?.jsonObjectOrNull()
            ?.mapValues { (_, value) -> decodeOverride(value.jsonObjectOrNull()) }
            .orEmpty(),
    )

private fun decodeServiceLibrary(obj: JsonObject?): AiServiceLibrary =
    AiServiceLibrary(
        llm = decodeConfigList(obj?.get("llm"), "llm"),
        asr = decodeConfigList(obj?.get("asr"), "asr"),
        tts = decodeConfigList(obj?.get("tts"), "tts"),
    )

private fun decodeConfigList(element: JsonElement?, capability: String): List<AiServiceConfig> =
    (element as? JsonArray)
        ?.mapNotNull { value ->
            value.jsonObjectOrNull()?.let { decodeConfig(it, capability) }
        }
        .orEmpty()

private fun decodeConfig(obj: JsonObject, fallbackCapability: String): AiServiceConfig =
    AiServiceConfig(
        id = obj.stringValue("id"),
        capability = obj.stringValue("capability").ifBlank { fallbackCapability },
        mode = obj.stringValue("mode"),
        profileId = obj.stringValue("profileId"),
        providerId = obj.stringValue("providerId"),
        voiceId = obj.stringValue("voiceId"),
        baseUrl = obj.stringValue("baseUrl"),
        model = obj.stringValue("model"),
        credentialId = obj.stringValue("credentialId"),
        displayName = obj.stringValue("displayName"),
        enabled = obj["enabled"]?.jsonPrimitive?.booleanOrNull ?: true,
        status = obj.stringValue("status"),
    )

private fun decodeSceneSelections(obj: JsonObject?): AiSceneSelections =
    AiSceneSelections(
        providerChat = AiProviderChatSelection(
            obj?.get("providerChat")?.jsonObjectOrNull().stringValue("llmConfigId")
        ),
        recording = AiRecordingSelection(
            obj?.get("recording")?.jsonObjectOrNull().stringValue("asrConfigId")
        ),
        playback = AiPlaybackSelection(
            obj?.get("playback")?.jsonObjectOrNull().stringValue("ttsConfigId")
        ),
        agentOverrides = obj?.get("agentOverrides")
            ?.jsonObjectOrNull()
            ?.mapValues { (_, value) -> decodeSceneOverride(value.jsonObjectOrNull()) }
            .orEmpty(),
    )

private fun decodeSceneOverride(obj: JsonObject?): AiSceneAgentOverride =
    AiSceneAgentOverride(
        inherit = obj?.get("inherit")?.jsonPrimitive?.booleanOrNull ?: true,
        llmConfigId = obj.stringValue("llmConfigId"),
        asrConfigId = obj.stringValue("asrConfigId"),
        ttsConfigId = obj.stringValue("ttsConfigId"),
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
        baseUrl = obj.stringValueOrFallback("baseUrl", fallback.baseUrl),
        model = obj.stringValueOrFallback("model", fallback.model),
        credentialId = obj.stringValueOrFallback("credentialId", fallback.credentialId),
        displayName = obj.stringValueOrFallback("displayName", fallback.displayName),
    )

private fun JsonObject?.stringValue(name: String): String =
    this?.get(name)?.jsonPrimitive?.contentOrNull.orEmpty()

private fun JsonObject?.stringValueOrFallback(name: String, fallback: String): String =
    if (this?.containsKey(name) == true) stringValue(name) else fallback

private fun JsonElement.jsonObjectOrNull(): JsonObject? =
    this as? JsonObject
