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
    val supportsAudio: Boolean = true,
) {
    OPENCLAW("openclaw", "OpenClaw", "OpenClaw Agent"),
    HERMES("hermes", "Hermes", "Hermes BosonRelay"),
    CODEX("codex", "Codex", "Codex", supportsAudio = false),
    CUSTOM("custom", "Custom", "Agent");

    companion object {
        fun fromWireValue(value: String?): AgentPlatform =
            entries.firstOrNull { it.wireValue == value?.trim()?.lowercase() } ?: OPENCLAW
    }
}

enum class AgentAvailabilityStatus(val label: String) {
    UNCONFIGURED("未配对"),
    UNPAIRED("未配对"),
    PAIRING("连接中"),
    CONNECTING("连接中"),
    AVAILABLE("可用"),
    OFFLINE("连接中"),
}

data class AgentProfile(
    val id: String,
    val platform: AgentPlatform = AgentPlatform.OPENCLAW,
    val displayName: String = "",
    val gatewayUrl: String = DEFAULT_GATEWAY_URL,
    val backendId: String,
    val backendLabel: String? = null,
    val token: String = "",
    val isPaired: Boolean = false,
    val asrMode: String = "router",
    val asrProfileId: String = "",
    val isPinned: Boolean = false,
    val sortIndex: Int = 0,
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

        fun canonicalWebSocketGatewayUrl(gatewayUrl: String): String {
            var value = gatewayUrl.trim()
            if (value.isEmpty()) return DEFAULT_GATEWAY_URL
            value = when {
                value.startsWith("https://") -> "wss://" + value.removePrefix("https://")
                value.startsWith("http://") -> "ws://" + value.removePrefix("http://")
                value.startsWith("wss://") || value.startsWith("ws://") -> value
                else -> "wss://$value"
            }
            value = value.trimEnd('/')
            if (!value.endsWith("/ws")) {
                value += "/ws"
            }
            return value
        }

        fun normalizedGatewayKey(gatewayUrl: String): String {
            if (gatewayUrl.isBlank()) return ""
            var value = canonicalWebSocketGatewayUrl(gatewayUrl)
            value = when {
                value.startsWith("wss://") -> "https://" + value.removePrefix("wss://")
                value.startsWith("ws://") -> "http://" + value.removePrefix("ws://")
                else -> value
            }
            return value.removeSuffix("/ws").lowercase()
        }
    }
}

data class AgentListActivity(
    val lastMessageText: String? = null,
    val lastMessageAt: Long? = null,
)

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
        fun default(): AgentProfilesState {
            val profile = AgentProfile(
                id = randomProfileId(),
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

fun List<AgentProfile>.sortedForAgentList(
    unreadCounts: Map<String, Int> = emptyMap(),
    activities: Map<String, AgentListActivity> = emptyMap(),
): List<AgentProfile> =
    sortedWith(
        compareByDescending<AgentProfile> { it.isPinned }
            .thenByDescending { (unreadCounts[it.id] ?: 0) > 0 }
            .thenByDescending { activities[it.id]?.lastMessageAt ?: it.updatedAt }
            .thenBy { it.sortIndex }
            .thenBy { it.resolvedDisplayName.lowercase() }
    )

internal fun encodeProfiles(profiles: List<AgentProfile>): String =
    buildJsonArray {
        profiles.forEach { profile ->
            add(
                buildJsonObject {
                    put("id", profile.id)
                    put("platform", profile.platform.wireValue)
                    put("displayName", profile.displayName)
                    put("gatewayUrl", profile.gatewayUrl)
                    put("backendId", profile.backendId)
                    profile.backendLabel?.let { put("backendLabel", it) }
                    put("token", profile.token)
                    put("isPaired", profile.isPaired)
                    put("asrMode", profile.asrMode)
                    put("asrProfileId", profile.asrProfileId)
                    put("isPinned", profile.isPinned)
                    put("sortIndex", profile.sortIndex)
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
        platform = AgentPlatform.fromWireValue(obj.stringValue("platform")),
        displayName = obj.stringValue("displayName"),
        gatewayUrl = AgentProfile.canonicalWebSocketGatewayUrl(obj.stringValue("gatewayUrl")),
        backendId = backendId,
        backendLabel = obj.optionalStringValue("backendLabel"),
        token = obj.stringValue("token"),
        isPaired = obj.booleanValue("isPaired"),
        asrMode = obj.stringValue("asrMode").ifBlank { "router" },
        asrProfileId = obj.stringValue("asrProfileId"),
        isPinned = obj.booleanValue("isPinned"),
        sortIndex = obj.intValue("sortIndex"),
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

private fun JsonObject.intValue(name: String): Int =
    get(name)?.jsonPrimitive?.contentOrNull?.toIntOrNull() ?: 0
