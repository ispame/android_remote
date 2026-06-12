package com.openclaw.remote.data

import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import platform.Foundation.NSUserDefaults

class SettingsManagerIOS : SettingsManager {
    private val defaults = NSUserDefaults.standardUserDefaults()

    private val _configFlow = MutableStateFlow(loadConfig())
    private val _profilesFlow = MutableStateFlow(makeState(loadConfig()))
    private val _aiSettingsFlow = MutableStateFlow(loadAiSettings())
    private val _soundPlaybackEnabledFlow = MutableStateFlow(loadSoundPlaybackEnabled())

    override val configFlow: Flow<GatewayConfig> = _configFlow.asStateFlow()
    override val profilesFlow: Flow<AgentProfilesState> = _profilesFlow.asStateFlow()
    override val aiSettingsFlow: Flow<AiServiceSettings> = _aiSettingsFlow.asStateFlow()
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
            accountId = defaults.stringForKey("account_id") ?: "",
            accessToken = defaults.stringForKey("access_token") ?: "",
            refreshToken = defaults.stringForKey("refresh_token") ?: "",
            accessExpiresAt = defaults.stringForKey("access_expires_at") ?: "",
            refreshExpiresAt = defaults.stringForKey("refresh_expires_at") ?: "",
            deviceLabel = defaults.stringForKey("device_label") ?: "",
            token = defaults.stringForKey("token") ?: "",
            pairedBackendId = defaults.stringForKey("paired_backend_id"),
            pairedBackendLabel = defaults.stringForKey("paired_backend_label"),
            asrMode = defaults.stringForKey("asr_mode") ?: "router",
            asrProfileId = defaults.stringForKey("asr_profile_id") ?: "",
        )
    }

    private fun loadAiSettings(): AiServiceSettings =
        decodeAiServiceSettings(defaults.stringForKey("ai_service_settings_v1"))

    private fun saveConfig(config: GatewayConfig) {
        defaults.setObject(config.gatewayUrl, forKey = "gateway_url")
        defaults.setObject(config.accountId, forKey = "account_id")
        defaults.setObject(config.accessToken, forKey = "access_token")
        defaults.setObject(config.refreshToken, forKey = "refresh_token")
        defaults.setObject(config.accessExpiresAt, forKey = "access_expires_at")
        defaults.setObject(config.refreshExpiresAt, forKey = "refresh_expires_at")
        defaults.setObject(config.deviceLabel, forKey = "device_label")
        defaults.setObject(config.token, forKey = "token")
        defaults.setObject(config.asrMode, forKey = "asr_mode")
        defaults.setObject(config.asrProfileId, forKey = "asr_profile_id")
        saveAiSettings(aiSettingsFromLegacyConfig(config), updateConfigFlow = false)
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

    private fun saveAiSettings(settings: AiServiceSettings, updateConfigFlow: Boolean = true) {
        val normalized = settings.normalized()
        defaults.setObject(encodeAiServiceSettings(normalized), forKey = "ai_service_settings_v1")
        _aiSettingsFlow.value = normalized
        if (updateConfigFlow) {
            val current = _configFlow.value
            _configFlow.value = current.copy(
                asrMode = normalized.defaults.asr.mode,
                asrProfileId = normalized.defaults.asr.profileId,
                ttsEngine = normalized.defaults.tts.toLegacyTtsEngine(),
                minimaxVoiceId = normalized.defaults.tts.voiceId,
            )
        }
    }

    private fun makeState(config: GatewayConfig): AgentProfilesState {
        val profile = AgentProfile(
            id = config.profileId.ifBlank { "legacy-ios-profile" },
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

    override suspend fun setProfilePinned(profileId: String, pinned: Boolean) {
        _profilesFlow.value = _profilesFlow.value.copy(
            profiles = _profilesFlow.value.profiles.map { profile ->
                if (profile.id == profileId) profile.copy(isPinned = pinned) else profile
            }
        )
    }

    override suspend fun updateAiSettings(settings: AiServiceSettings) {
        saveAiSettings(settings)
    }

    override suspend fun updateLocalCredential(id: String, apiKey: String) = Unit

    override suspend fun localCredential(id: String): String? = null

    override suspend fun updateLocalTtsCredential(providerId: String, apiKey: String) =
        updateLocalCredential(if (providerId == "minimax") LOCAL_TTS_MINIMAX_CREDENTIAL_ID else providerId, apiKey)

    override suspend fun localTtsCredential(providerId: String): String? =
        localCredential(if (providerId == "minimax") LOCAL_TTS_MINIMAX_CREDENTIAL_ID else providerId)

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
        defaults.removeObjectForKey("account_id")
        defaults.removeObjectForKey("access_token")
        defaults.removeObjectForKey("refresh_token")
        defaults.removeObjectForKey("access_expires_at")
        defaults.removeObjectForKey("refresh_expires_at")
        defaults.removeObjectForKey("device_label")
        defaults.removeObjectForKey("token")
        defaults.removeObjectForKey("paired_backend_id")
        defaults.removeObjectForKey("paired_backend_label")
        defaults.removeObjectForKey("asr_mode")
        defaults.removeObjectForKey("asr_profile_id")
        defaults.removeObjectForKey("ai_service_settings_v1")
        defaults.removeObjectForKey("sound_playback_enabled_v1")
        _configFlow.value = GatewayConfig()
        _profilesFlow.value = makeState(_configFlow.value)
        _aiSettingsFlow.value = AiServiceSettings()
        _soundPlaybackEnabledFlow.value = true
    }
}
