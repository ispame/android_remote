package com.openclaw.remote.data

import kotlinx.coroutines.flow.Flow

/**
 * Settings Manager - cross-platform abstraction for persistent settings.
 */
interface SettingsManager {
    companion object {
        const val MAX_AGENT_PROFILES = 3
    }

    val configFlow: Flow<GatewayConfig>
    val profilesFlow: Flow<AgentProfilesState>
    val soundPlaybackEnabledFlow: Flow<Boolean>

    suspend fun updateConfig(config: GatewayConfig)
    suspend fun updateDeviceId(id: String)
    suspend fun updateDeviceLabel(label: String)
    suspend fun updateGatewayUrl(url: String)
    suspend fun updatePairedBackend(backendId: String?, backendLabel: String?, profileId: String? = null)
    suspend fun selectProfile(profileId: String)
    suspend fun saveProfile(profile: AgentProfile, select: Boolean = true): Boolean
    suspend fun upsertScannedProfile(
        gatewayUrl: String,
        backendId: String,
        token: String,
        platform: AgentPlatform,
        label: String?,
    ): AgentProfile?
    suspend fun deleteProfile(profileId: String)
    suspend fun clearProfile(profileId: String)
    suspend fun updateGlobalAsr(mode: String, profileId: String)
    suspend fun updateSoundPlaybackEnabled(enabled: Boolean)
    suspend fun canAcceptProfile(gatewayUrl: String, backendId: String): Boolean
    suspend fun profileAcceptError(gatewayUrl: String, backendId: String): String?
    suspend fun clearConfig()
}
