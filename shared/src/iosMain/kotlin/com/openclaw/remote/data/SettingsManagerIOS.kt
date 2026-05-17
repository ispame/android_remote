package com.openclaw.remote.data

import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import platform.Foundation.NSUserDefaults

class SettingsManagerIOS : SettingsManager {
    private val defaults = NSUserDefaults.standardUserDefaults()

    private val _configFlow = MutableStateFlow(loadConfig())
    private val _profilesFlow = MutableStateFlow(makeState(loadConfig()))
    private val _soundPlaybackEnabledFlow = MutableStateFlow(loadSoundPlaybackEnabled())

    override val configFlow: Flow<GatewayConfig> = _configFlow.asStateFlow()
    override val profilesFlow: Flow<AgentProfilesState> = _profilesFlow.asStateFlow()
    override val soundPlaybackEnabledFlow: Flow<Boolean> = _soundPlaybackEnabledFlow.asStateFlow()

    private fun loadSoundPlaybackEnabled(): Boolean {
        return if (defaults.objectForKey("sound_playback_enabled_v1") == null) {
            true
        } else {
            defaults.boolForKey("sound_playback_enabled_v1")
        }
    }

    private fun loadConfig(): GatewayConfig {
        return GatewayConfig(
            gatewayUrl = defaults.stringForKey("gateway_url") ?: "ws://192.168.1.14:8765",
            deviceId = defaults.stringForKey("device_id") ?: "",
            deviceLabel = defaults.stringForKey("device_label") ?: "",
            token = defaults.stringForKey("token") ?: "",
            pairedBackendId = defaults.stringForKey("paired_backend_id"),
            pairedBackendLabel = defaults.stringForKey("paired_backend_label"),
            asrMode = defaults.stringForKey("asr_mode") ?: "router",
            asrProfileId = defaults.stringForKey("asr_profile_id") ?: "",
        )
    }

    private fun saveConfig(config: GatewayConfig) {
        defaults.setObject(config.gatewayUrl, forKey = "gateway_url")
        defaults.setObject(config.deviceId, forKey = "device_id")
        defaults.setObject(config.deviceLabel, forKey = "device_label")
        defaults.setObject(config.token, forKey = "token")
        defaults.setObject(config.asrMode, forKey = "asr_mode")
        defaults.setObject(config.asrProfileId, forKey = "asr_profile_id")
        if (config.pairedBackendId != null) {
            defaults.setObject(config.pairedBackendId, forKey = "paired_backend_id")
        } else {
            defaults.removeObjectForKey("paired_backend_id")
        }
        if (config.pairedBackendLabel != null) {
            defaults.setObject(config.pairedBackendLabel, forKey = "paired_backend_label")
        } else {
            defaults.removeObjectForKey("paired_backend_label")
        }
        _configFlow.value = config
        _profilesFlow.value = makeState(config)
    }

    private fun makeState(config: GatewayConfig): AgentProfilesState {
        val profile = AgentProfile(
            id = config.profileId.ifBlank { "legacy-ios-profile" },
            appClientId = config.deviceId,
            platform = AgentPlatform.OPENCLAW,
            displayName = config.pairedBackendLabel ?: AgentPlatform.OPENCLAW.defaultDisplayName,
            gatewayUrl = config.gatewayUrl,
            backendId = config.pairedBackendId.orEmpty(),
            backendLabel = config.pairedBackendLabel,
            token = config.token,
            isPaired = config.pairedBackendId != null,
            asrMode = config.asrMode,
            asrProfileId = config.asrProfileId,
        )
        return AgentProfilesState(listOf(profile), profile.id)
    }

    override suspend fun updateConfig(config: GatewayConfig) {
        saveConfig(config)
    }

    override suspend fun updateDeviceId(id: String) {
        val current = _configFlow.value
        saveConfig(current.copy(deviceId = id))
    }

    override suspend fun updateDeviceLabel(label: String) {
        val current = _configFlow.value
        saveConfig(current.copy(deviceLabel = label))
    }

    override suspend fun updateGatewayUrl(url: String) {
        val current = _configFlow.value
        saveConfig(current.copy(gatewayUrl = url))
    }

    override suspend fun updatePairedBackend(backendId: String?, backendLabel: String?, profileId: String?) {
        val current = _configFlow.value
        saveConfig(current.copy(pairedBackendId = backendId, pairedBackendLabel = backendLabel))
    }

    override suspend fun selectProfile(profileId: String) = Unit

    override suspend fun saveProfile(profile: AgentProfile, select: Boolean): Boolean {
        saveConfig(
            _configFlow.value.copy(
                profileId = profile.id,
                gatewayUrl = profile.gatewayUrl,
                token = profile.token,
                pairedBackendId = profile.backendId.ifBlank { null },
                pairedBackendLabel = profile.backendLabel,
                asrMode = profile.asrMode,
                asrProfileId = profile.asrProfileId,
            )
        )
        return true
    }

    override suspend fun upsertScannedProfile(
        gatewayUrl: String,
        backendId: String,
        token: String,
        platform: AgentPlatform,
        label: String?,
    ): AgentProfile? {
        val profile = AgentProfile(
            id = _configFlow.value.profileId.ifBlank { "legacy-ios-profile" },
            appClientId = _configFlow.value.deviceId,
            platform = platform,
            displayName = label ?: platform.defaultDisplayName,
            gatewayUrl = gatewayUrl,
            backendId = backendId,
            backendLabel = label ?: backendId,
            token = token,
        )
        saveProfile(profile, true)
        return profile
    }

    override suspend fun deleteProfile(profileId: String) {
        clearConfig()
    }

    override suspend fun clearProfile(profileId: String) {
        clearConfig()
    }

    override suspend fun updateGlobalAsr(mode: String, profileId: String) {
        val normalizedMode = if (mode == "backend") "backend" else "router"
        val current = _configFlow.value
        saveConfig(current.copy(asrMode = normalizedMode, asrProfileId = if (normalizedMode == "backend") "" else profileId))
    }

    override suspend fun updateSoundPlaybackEnabled(enabled: Boolean) {
        defaults.setBool(enabled, forKey = "sound_playback_enabled_v1")
        _soundPlaybackEnabledFlow.value = enabled
    }

    override suspend fun canAcceptProfile(gatewayUrl: String, backendId: String): Boolean = true

    override suspend fun profileAcceptError(gatewayUrl: String, backendId: String): String? = null

    override suspend fun clearConfig() {
        defaults.removeObjectForKey("gateway_url")
        defaults.removeObjectForKey("device_id")
        defaults.removeObjectForKey("device_label")
        defaults.removeObjectForKey("token")
        defaults.removeObjectForKey("paired_backend_id")
        defaults.removeObjectForKey("paired_backend_label")
        defaults.removeObjectForKey("asr_mode")
        defaults.removeObjectForKey("asr_profile_id")
        defaults.removeObjectForKey("sound_playback_enabled_v1")
        _configFlow.value = GatewayConfig()
        _profilesFlow.value = makeState(_configFlow.value)
        _soundPlaybackEnabledFlow.value = true
    }
}
