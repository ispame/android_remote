package com.openclaw.remote.data

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.longOrNull
import kotlinx.serialization.json.put

enum class AgentPlatform(
    val wireValue: String,
    val label: String,
    val defaultDisplayName: String,
) {
    OPENCLAW("openclaw", "OpenClaw", "OpenClaw Agent"),
    HERMES("hermes", "Hermes", "Hermes BosonRelay"),
    CUSTOM("custom", "Custom", "Agent");

    companion object {
        fun fromWireValue(value: String?): AgentPlatform =
            entries.firstOrNull { it.wireValue == value?.trim()?.lowercase() } ?: OPENCLAW
    }
}

enum class AgentAvailabilityStatus(val label: String) {
    UNCONFIGURED("未配置"),
    UNPAIRED("未配对"),
    PAIRING("连接中"),
    CONNECTING("连接中"),
    AVAILABLE("在线"),
    OFFLINE("离线"),
}

data class AgentProfile(
    val id: String,
    val appClientId: String,
    val platform: AgentPlatform = AgentPlatform.OPENCLAW,
    val displayName: String = "",
    val gatewayUrl: String = DEFAULT_GATEWAY_URL,
    val backendId: String,
    val backendLabel: String? = null,
    val token: String = "",
    val isPaired: Boolean = false,
    val asrMode: String = "router",
    val asrProfileId: String = "",
    val createdAt: Long = currentTimestampMillis(),
    val updatedAt: Long = currentTimestampMillis(),
) {
    val resolvedDisplayName: String
        get() = displayName.trim().ifEmpty {
            backendLabel?.takeIf { it.isNotBlank() } ?: platform.defaultDisplayName
        }

    val uniqueBackendKey: String
        get() = "${normalizedGatewayKey(gatewayUrl)}|$backendId"

    companion object {
        const val DEFAULT_GATEWAY_URL = "wss://boson-tech.top/ws"

        fun normalizedGatewayKey(gatewayUrl: String): String =
            gatewayUrl.trim().lowercase()
    }
}

data class AgentProfilesState(
    val profiles: List<AgentProfile>,
    val selectedProfileId: String,
) {
    val selectedProfile: AgentProfile
        get() = profiles.firstOrNull { it.id == selectedProfileId } ?: profiles.first()

    val hasMultipleProfiles: Boolean
        get() = profiles.size >= 2

    val canAddProfile: Boolean
        get() = profiles.size < SettingsManager.MAX_AGENT_PROFILES

    companion object {
        fun default(appClientId: String = ""): AgentProfilesState {
            val profile = AgentProfile(
                id = randomProfileId(),
                appClientId = appClientId,
                backendId = "",
                displayName = AgentPlatform.OPENCLAW.defaultDisplayName,
            )
            return AgentProfilesState(listOf(profile), profile.id)
        }
    }
}

fun randomProfileId(): String =
    "profile_${randomUuid().take(8)}"

expect fun randomUuid(): String

expect fun currentTimestampMillis(): Long

internal fun encodeProfiles(profiles: List<AgentProfile>): String =
    buildJsonArray {
        profiles.forEach { profile ->
            add(
                buildJsonObject {
                    put("id", profile.id)
                    put("appClientId", profile.appClientId)
                    put("platform", profile.platform.wireValue)
                    put("displayName", profile.displayName)
                    put("gatewayUrl", profile.gatewayUrl)
                    put("backendId", profile.backendId)
                    profile.backendLabel?.let { put("backendLabel", it) }
                    put("token", profile.token)
                    put("isPaired", profile.isPaired)
                    put("asrMode", profile.asrMode)
                    put("asrProfileId", profile.asrProfileId)
                    put("createdAt", profile.createdAt)
                    put("updatedAt", profile.updatedAt)
                }
            )
        }
    }.toString()

internal fun decodeProfiles(raw: String?): List<AgentProfile> {
    if (raw.isNullOrBlank()) return emptyList()
    return runCatching {
        Json.parseToJsonElement(raw).jsonArray.mapNotNull(::decodeProfile)
    }.getOrDefault(emptyList())
}

private fun decodeProfile(element: JsonElement): AgentProfile? {
    val obj = element as? JsonObject ?: return null
    val id = obj.stringValue("id").ifBlank { randomProfileId() }
    val backendId = obj.stringValue("backendId")
    return AgentProfile(
        id = id,
        appClientId = obj.stringValue("appClientId"),
        platform = AgentPlatform.fromWireValue(obj.stringValue("platform")),
        displayName = obj.stringValue("displayName"),
        gatewayUrl = obj.stringValue("gatewayUrl").ifBlank { AgentProfile.DEFAULT_GATEWAY_URL },
        backendId = backendId,
        backendLabel = obj.optionalStringValue("backendLabel"),
        token = obj.stringValue("token"),
        isPaired = obj.booleanValue("isPaired"),
        asrMode = obj.stringValue("asrMode").ifBlank { "router" },
        asrProfileId = obj.stringValue("asrProfileId"),
        createdAt = obj.longValue("createdAt"),
        updatedAt = obj.longValue("updatedAt"),
    )
}

private fun JsonObject.stringValue(name: String): String =
    get(name)?.jsonPrimitive?.contentOrNull.orEmpty()

private fun JsonObject.optionalStringValue(name: String): String? =
    get(name)?.jsonPrimitive?.contentOrNull

private fun JsonObject.booleanValue(name: String): Boolean =
    get(name)?.jsonPrimitive?.booleanOrNull ?: false

private fun JsonObject.longValue(name: String): Long =
    get(name)?.jsonPrimitive?.longOrNull ?: currentTimestampMillis()
