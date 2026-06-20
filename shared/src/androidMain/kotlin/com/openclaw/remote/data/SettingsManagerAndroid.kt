package com.openclaw.remote.data

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.MutablePreferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map

private val Context.dataStore: DataStore<Preferences> by preferencesDataStore(name = "settings")

class SettingsManagerAndroid(
    private val context: Context,
    private val credentialVault: CredentialVault = AndroidCredentialVault(context),
) : SettingsManager {

    companion object {
        private const val LEGACY_PROFILE_ID = "legacy-android-profile"
        private val GATEWAY_URL = stringPreferencesKey("gateway_url")
        private val ACCOUNT_ID = stringPreferencesKey("account_id")
        private val ACCESS_TOKEN = stringPreferencesKey("access_token")
        private val REFRESH_TOKEN = stringPreferencesKey("refresh_token")
        private val ACCESS_EXPIRES_AT = stringPreferencesKey("access_expires_at")
        private val REFRESH_EXPIRES_AT = stringPreferencesKey("refresh_expires_at")
        private val DEVICE_LABEL = stringPreferencesKey("device_label")
        private val TOKEN = stringPreferencesKey("token")
        private val PAIRED_BACKEND_ID = stringPreferencesKey("paired_backend_id")
        private val PAIRED_BACKEND_LABEL = stringPreferencesKey("paired_backend_label")
        private val ASR_MODE = stringPreferencesKey("asr_mode")
        private val ASR_PROFILE_ID = stringPreferencesKey("asr_profile_id")
        private val TTS_ENGINE = stringPreferencesKey("tts_engine")
        private val MINIMAX_API_KEY = stringPreferencesKey("minimax_api_key")
        private val MINIMAX_VOICE_ID = stringPreferencesKey("minimax_voice_id")
        private val LAST_LOGIN_MODE = stringPreferencesKey("last_login_mode")
        private val LAST_PHONE_NUMBER = stringPreferencesKey("last_phone_number")
        private val AI_SERVICE_SETTINGS = stringPreferencesKey("ai_service_settings_v1")
        private val AGENT_PROFILES = stringPreferencesKey("agent_profiles_v1")
        private val SELECTED_AGENT_PROFILE_ID = stringPreferencesKey("selected_agent_profile_id")
        private val SOUND_PLAYBACK_ENABLED = booleanPreferencesKey("sound_playback_enabled_v1")
    }

    override val profilesFlow: Flow<AgentProfilesState> = context.dataStore.data.map { prefs ->
        prefs.toProfilesState()
    }

    override val soundPlaybackEnabledFlow: Flow<Boolean> = context.dataStore.data.map { prefs ->
        prefs[SOUND_PLAYBACK_ENABLED] ?: true
    }

    override val aiSettingsFlow: Flow<AiServiceSettings> = context.dataStore.data.map { prefs ->
        prefs.toAiSettings()
    }

    override val configFlow: Flow<GatewayConfig> = context.dataStore.data.map { prefs ->
        prefs.toGatewayConfig(localMiniMaxApiKey = migrateMiniMaxCredentialIfNeeded(prefs))
    }

    override suspend fun updateConfig(config: GatewayConfig) {
        val localMiniMaxApiKey = config.minimaxApiKey.trim()
        if (localMiniMaxApiKey.isNotEmpty()) {
            credentialVault.set(LOCAL_TTS_MINIMAX_CREDENTIAL_ID, localMiniMaxApiKey)
        } else if (config.ttsEngine == "minimax") {
            credentialVault.remove(LOCAL_TTS_MINIMAX_CREDENTIAL_ID)
        }
        context.dataStore.edit { prefs ->
            val previousAccountId = prefs[ACCOUNT_ID].orEmpty()
            val accountChanged = previousAccountId.isNotBlank() && previousAccountId != config.accountId
            val state = if (accountChanged) {
                val resetProfile = AgentProfilesState.default().selectedProfile.copy(
                    gatewayUrl = config.gatewayUrl.ifBlank { AgentProfile.DEFAULT_GATEWAY_URL },
                    asrMode = config.asrMode.normalizedAsrMode(),
                    asrProfileId = if (config.asrMode == "backend") "" else config.asrProfileId,
                    updatedAt = currentTimestampMillis(),
                )
                AgentProfilesState(listOf(resetProfile), resetProfile.id)
            } else {
                prefs.toProfilesState()
            }
            val selectedId = config.profileId.ifBlank { state.selectedProfileId }
            val index = state.profiles.indexOfFirst { it.id == selectedId }
                .takeIf { it >= 0 }
                ?: state.profiles.indexOfFirst { it.id == state.selectedProfileId }.coerceAtLeast(0)
            val now = currentTimestampMillis()
            val profiles = state.profiles.toMutableList()
            val current = profiles[index]
            profiles[index] = current.copy(
                gatewayUrl = config.gatewayUrl.ifBlank { current.gatewayUrl },
                token = config.token,
                backendId = config.pairedBackendId ?: current.backendId,
                backendLabel = config.pairedBackendLabel,
                isPaired = config.pairedBackendId != null,
                asrMode = config.asrMode.normalizedAsrMode(),
                asrProfileId = config.asrProfileId.takeIf { config.asrMode != "backend" }.orEmpty(),
                updatedAt = now,
            )
            prefs[DEVICE_LABEL] = config.deviceLabel.ifEmpty { "我的设备" }
            prefs[ACCOUNT_ID] = config.accountId
            prefs[ACCESS_TOKEN] = config.accessToken
            prefs[REFRESH_TOKEN] = config.refreshToken
            prefs[ACCESS_EXPIRES_AT] = config.accessExpiresAt
            prefs[REFRESH_EXPIRES_AT] = config.refreshExpiresAt
            prefs[ASR_MODE] = config.asrMode.normalizedAsrMode()
            prefs[ASR_PROFILE_ID] = if (config.asrMode == "backend") "" else config.asrProfileId
            prefs[TTS_ENGINE] = config.ttsEngine.normalizedTtsEngine()
            prefs.remove(MINIMAX_API_KEY)
            prefs[MINIMAX_VOICE_ID] = config.minimaxVoiceId.normalizedMiniMaxVoiceId()
            prefs[LAST_LOGIN_MODE] = config.lastLoginMode
            prefs[LAST_PHONE_NUMBER] = config.lastPhoneNumber
            prefs[AI_SERVICE_SETTINGS] = encodeAiServiceSettings(
                prefs.toAiSettings().copy(
                    defaults = prefs.toAiSettings().defaults.copy(
                        asr = AiServiceChoice(
                            mode = config.asrMode.normalizedAsrMode(),
                            profileId = if (config.asrMode == "backend") "" else config.asrProfileId,
                        ),
                        tts = legacyTtsChoice(config.ttsEngine.normalizedTtsEngine(), config.minimaxVoiceId),
                    )
                )
            )
            persistProfiles(prefs, profiles, profiles[index].id)
        }
    }

    override suspend fun updateDeviceLabel(label: String) {
        context.dataStore.edit { prefs ->
            prefs[DEVICE_LABEL] = label.trim().ifEmpty { "我的设备" }
            prefs.mirrorSelectedProfile(prefs.toProfilesState())
        }
    }

    override suspend fun updateGatewayUrl(url: String) {
        context.dataStore.edit { prefs ->
            val state = prefs.toProfilesState()
            val profiles = state.profiles.map { profile ->
                if (profile.id == state.selectedProfileId) {
                    profile.copy(
                        gatewayUrl = AgentProfile.canonicalWebSocketGatewayUrl(url),
                        updatedAt = currentTimestampMillis(),
                    )
                } else {
                    profile
                }
            }
            persistProfiles(prefs, profiles, state.selectedProfileId)
        }
    }

    override suspend fun updatePairedBackend(backendId: String?, backendLabel: String?, profileId: String?) {
        context.dataStore.edit { prefs ->
            val state = prefs.toProfilesState()
            val targetId = profileId ?: state.selectedProfileId
            val profiles = state.profiles.map { profile ->
                if (profile.id == targetId) {
                    profile.copy(
                        backendId = backendId ?: profile.backendId,
                        backendLabel = backendLabel,
                        isPaired = backendId != null,
                        updatedAt = currentTimestampMillis(),
                    )
                } else {
                    profile
                }
            }
            persistProfiles(prefs, profiles, state.selectedProfileId)
        }
    }

    override suspend fun selectProfile(profileId: String) {
        context.dataStore.edit { prefs ->
            val state = prefs.toProfilesState()
            if (state.profiles.any { it.id == profileId }) {
                persistProfiles(prefs, state.profiles, profileId)
            }
        }
    }

    override suspend fun saveProfile(profile: AgentProfile, select: Boolean): Boolean {
        var saved = false
        context.dataStore.edit { prefs ->
            val state = prefs.toProfilesState()
            val normalized = profile.normalizedForSave(
                asrMode = prefs.globalAsrMode(),
                asrProfileId = prefs.globalAsrProfileId(),
            )
            val profiles = state.profiles.toMutableList()
            val existingIndex = profiles.indexOfFirst { it.id == normalized.id }
            if (existingIndex >= 0) {
                profiles[existingIndex] = normalized.clearPairingIfConnectionIdentityChanged(profiles[existingIndex])
                persistProfiles(prefs, profiles, if (select) normalized.id else state.selectedProfileId)
                saved = true
            } else if (
                profiles.size < SettingsManager.MAX_AGENT_PROFILES &&
                isGatewayCompatible(profiles, normalized.gatewayUrl)
            ) {
                profiles += normalized.copy(isPaired = false)
                persistProfiles(prefs, profiles, if (select) normalized.id else state.selectedProfileId)
                saved = true
            }
        }
        return saved
    }

    override suspend fun upsertScannedProfile(
        gatewayUrl: String,
        backendId: String,
        token: String,
        platform: AgentPlatform,
        label: String?,
    ): AgentProfile? {
        var saved: AgentProfile? = null
        context.dataStore.edit { prefs ->
            val state = prefs.toProfilesState()
            val normalizedGateway = AgentProfile.canonicalWebSocketGatewayUrl(gatewayUrl)
            if (!canAcceptProfile(state.profiles, normalizedGateway, backendId)) {
                return@edit
            }
            val displayName = resolvedProfileName(platform, label, backendId)
            val backendKey = "${AgentProfile.normalizedGatewayKey(normalizedGateway)}|$backendId"
            val now = currentTimestampMillis()
            val profiles = state.profiles.toMutableList()
            val existingIndex = profiles.indexOfFirst { it.uniqueBackendKey == backendKey }
            val emptyInitialIndex = profiles
                .indexOfFirst { profiles.size == 1 && it.backendId.isBlank() }
                .takeIf { it >= 0 }
            val targetIndex = existingIndex.takeIf { it >= 0 } ?: emptyInitialIndex

            val profile = if (targetIndex != null) {
                val previousProfile = profiles[targetIndex]
                val scannedProfile = previousProfile.copy(
                    platform = platform,
                    displayName = displayName,
                    gatewayUrl = normalizedGateway,
                    backendId = backendId,
                    backendLabel = label ?: backendId,
                    token = token,
                    asrMode = prefs.globalAsrMode(),
                    asrProfileId = prefs.globalAsrProfileId(),
                    updatedAt = now,
                )
                val preservePairing = existingIndex >= 0 && !connectionIdentityChanged(previousProfile, scannedProfile)
                scannedProfile.copy(
                    isPaired = if (preservePairing) previousProfile.isPaired else false,
                ).also { profiles[targetIndex] = it }
            } else {
                AgentProfile(
                    id = randomProfileId(),
                    platform = platform,
                    displayName = displayName,
                    gatewayUrl = normalizedGateway,
                    backendId = backendId,
                    backendLabel = label ?: backendId,
                    token = token,
                    isPaired = false,
                    asrMode = prefs.globalAsrMode(),
                    asrProfileId = prefs.globalAsrProfileId(),
                    createdAt = now,
                    updatedAt = now,
                ).also { profiles += it }
            }
            persistProfiles(prefs, profiles, profile.id)
            saved = profile
        }
        return saved
    }

    override suspend fun deleteProfile(profileId: String) {
        context.dataStore.edit { prefs ->
            val state = prefs.toProfilesState()
            if (state.profiles.size <= 1) return@edit
            val profiles = state.profiles.filterNot { it.id == profileId }
            val selectedId = if (state.selectedProfileId == profileId) profiles.first().id else state.selectedProfileId
            persistProfiles(prefs, profiles, selectedId)
        }
    }

    override suspend fun clearProfile(profileId: String) {
        context.dataStore.edit { prefs ->
            val state = prefs.toProfilesState()
            val profiles = state.profiles.map { profile ->
                if (profile.id == profileId) {
                    profile.copy(
                        platform = AgentPlatform.OPENCLAW,
                        displayName = AgentPlatform.OPENCLAW.defaultDisplayName,
                        gatewayUrl = AgentProfile.DEFAULT_GATEWAY_URL,
                        backendId = "",
                        backendLabel = null,
                        token = "",
                        isPaired = false,
                        asrMode = prefs.globalAsrMode(),
                        asrProfileId = prefs.globalAsrProfileId(),
                        updatedAt = currentTimestampMillis(),
                    )
                } else {
                    profile
                }
            }
            persistProfiles(prefs, profiles, state.selectedProfileId)
        }
    }

    override suspend fun setProfilePinned(profileId: String, pinned: Boolean) {
        context.dataStore.edit { prefs ->
            val state = prefs.toProfilesState()
            val profiles = state.profiles.map { profile ->
                if (profile.id == profileId) {
                    profile.copy(isPinned = pinned, updatedAt = currentTimestampMillis())
                } else {
                    profile
                }
            }
            persistProfiles(prefs, profiles, state.selectedProfileId)
        }
    }

    override suspend fun updateAiSettings(settings: AiServiceSettings) {
        val normalized = settings.normalized()
        context.dataStore.edit { prefs ->
            prefs[AI_SERVICE_SETTINGS] = encodeAiServiceSettings(normalized)
            prefs[ASR_MODE] = normalized.defaults.asr.mode.normalizedAsrMode()
            prefs[ASR_PROFILE_ID] = if (normalized.defaults.asr.mode == "backend") "" else normalized.defaults.asr.profileId
            prefs[TTS_ENGINE] = normalized.defaults.tts.toLegacyTtsEngine()
            prefs[MINIMAX_VOICE_ID] = normalized.defaults.tts.voiceId.normalizedMiniMaxVoiceId()
            prefs.remove(MINIMAX_API_KEY)
        }
    }

    override suspend fun upsertAiServiceConfig(config: AiServiceConfig) {
        updateAiSettings(aiSettingsFlow.first().upsertingServiceConfig(config))
    }

    override suspend fun deleteAiServiceConfig(configId: String) {
        updateAiSettings(aiSettingsFlow.first().deletingServiceConfig(configId))
    }

    override suspend fun updateAiSceneSelection(
        providerChatLlmConfigId: String?,
        recordingAsrConfigId: String?,
        playbackTtsConfigId: String?,
    ) {
        updateAiSettings(
            aiSettingsFlow.first().updatingSceneSelection(
                providerChatLlmConfigId = providerChatLlmConfigId,
                recordingAsrConfigId = recordingAsrConfigId,
                playbackTtsConfigId = playbackTtsConfigId,
            )
        )
    }

    override suspend fun updateLocalCredential(id: String, apiKey: String) {
        val normalizedId = id.trim()
        if (normalizedId.isBlank()) return
        val trimmed = apiKey.trim()
        if (trimmed.isEmpty()) {
            credentialVault.remove(normalizedId)
        } else {
            credentialVault.set(normalizedId, trimmed)
        }
        if (normalizedId == LOCAL_TTS_MINIMAX_CREDENTIAL_ID) {
            context.dataStore.edit { prefs -> prefs.remove(MINIMAX_API_KEY) }
        }
    }

    override suspend fun localCredential(id: String): String? =
        id.trim().takeIf { it.isNotBlank() }?.let { credentialVault.get(it) }

    override suspend fun updateLocalTtsCredential(providerId: String, apiKey: String) {
        if (providerId != "minimax") return
        updateLocalCredential(LOCAL_TTS_MINIMAX_CREDENTIAL_ID, apiKey)
    }

    override suspend fun localTtsCredential(providerId: String): String? =
        if (providerId == "minimax") localCredential(LOCAL_TTS_MINIMAX_CREDENTIAL_ID) else null

    override suspend fun updateGlobalAsr(mode: String, profileId: String) {
        context.dataStore.edit { prefs ->
            val normalizedMode = mode.normalizedAsrMode()
            val normalizedProfileId = if (normalizedMode == "backend") "" else profileId
            prefs[ASR_MODE] = normalizedMode
            prefs[ASR_PROFILE_ID] = normalizedProfileId
            prefs[AI_SERVICE_SETTINGS] = encodeAiServiceSettings(
                prefs.toAiSettings().copy(
                    defaults = prefs.toAiSettings().defaults.copy(
                        asr = AiServiceChoice(mode = normalizedMode, profileId = normalizedProfileId),
                    )
                )
            )
            val state = prefs.toProfilesState()
            persistProfiles(
                prefs = prefs,
                profiles = state.profiles.map {
                    it.copy(
                        asrMode = normalizedMode,
                        asrProfileId = normalizedProfileId,
                        updatedAt = currentTimestampMillis(),
                    )
                },
                selectedProfileId = state.selectedProfileId,
            )
        }
    }

    override suspend fun updateSoundPlaybackEnabled(enabled: Boolean) {
        context.dataStore.edit { prefs ->
            prefs[SOUND_PLAYBACK_ENABLED] = enabled
        }
    }

    override suspend fun canAcceptProfile(gatewayUrl: String, backendId: String): Boolean =
        canAcceptProfile(context.dataStore.data.first().toProfilesState().profiles, gatewayUrl, backendId)

    override suspend fun profileAcceptError(gatewayUrl: String, backendId: String): String? {
        val profiles = context.dataStore.data.first().toProfilesState().profiles
        if (canAcceptProfile(profiles, gatewayUrl, backendId)) return null
        if (profiles.size >= SettingsManager.MAX_AGENT_PROFILES) return "最多支持 ${SettingsManager.MAX_AGENT_PROFILES} 个 Agent"
        if (!isGatewayCompatible(profiles, gatewayUrl)) {
            return "当前版本仅支持同一 Gateway 下最多 ${SettingsManager.MAX_AGENT_PROFILES} 个 Agent"
        }
        return "无法新增 Agent"
    }

    override suspend fun clearConfig() {
        context.dataStore.edit { it.clear() }
    }

    suspend fun replaceAccountProfiles(profiles: List<AgentProfile>, selectedProfileId: String? = null) {
        context.dataStore.edit { prefs ->
            val currentState = prefs.toProfilesState()
            val normalizedRemoteProfiles = profiles
                .take(SettingsManager.MAX_AGENT_PROFILES)
                .map { profile ->
                    profile.normalizedForSave(
                        asrMode = profile.asrMode.normalizedAsrMode(),
                        asrProfileId = if (profile.asrMode == "backend") "" else profile.asrProfileId,
                    )
                }
            val remoteKeys = normalizedRemoteProfiles.map { it.uniqueBackendKey }.toSet()
            val localOnlyProfiles = currentState.profiles
                .filter { it.backendId.isNotBlank() && it.uniqueBackendKey !in remoteKeys }
            val normalizedProfiles = (normalizedRemoteProfiles + localOnlyProfiles)
                .take(SettingsManager.MAX_AGENT_PROFILES)
                .ifEmpty {
                    val profile = AgentProfilesState.default().selectedProfile.copy(
                        asrMode = prefs.globalAsrMode(),
                        asrProfileId = prefs.globalAsrProfileId(),
                    )
                    listOf(profile)
                }
            val selectedId = selectedProfileId
                ?.takeIf { id -> normalizedProfiles.any { it.id == id } }
                ?: currentState.selectedProfileId.takeIf { id -> normalizedProfiles.any { it.id == id } }
                ?: normalizedProfiles.first().id
            persistProfiles(prefs, normalizedProfiles, selectedId)
        }
    }

    private fun Preferences.toProfilesState(): AgentProfilesState {
        val loaded = decodeProfiles(this[AGENT_PROFILES])
        val profiles = if (loaded.isEmpty()) {
            listOf(makeLegacyProfile())
        } else {
            loaded
        }
        val selectedId = this[SELECTED_AGENT_PROFILE_ID]
            ?.takeIf { id -> profiles.any { it.id == id } }
            ?: profiles.first().id
        return AgentProfilesState(profiles, selectedId)
    }

    private fun Preferences.toGatewayConfig(localMiniMaxApiKey: String): GatewayConfig {
        val state = toProfilesState()
        val selected = state.selectedProfile
        val pairedBackendId = selected.backendId.takeIf { selected.isPaired && it.isNotBlank() }
        val aiSettings = toAiSettings()
        val ttsChoice = aiSettings.defaults.tts
        return GatewayConfig(
            profileId = selected.id,
            gatewayUrl = selected.gatewayUrl,
            accountId = this[ACCOUNT_ID] ?: "",
            accessToken = this[ACCESS_TOKEN] ?: "",
            refreshToken = this[REFRESH_TOKEN] ?: "",
            accessExpiresAt = this[ACCESS_EXPIRES_AT] ?: "",
            refreshExpiresAt = this[REFRESH_EXPIRES_AT] ?: "",
            deviceLabel = this[DEVICE_LABEL] ?: "我的设备",
            token = selected.token,
            pairedBackendId = pairedBackendId,
            pairedBackendLabel = pairedBackendId?.let { selected.backendLabel ?: selected.resolvedDisplayName },
            asrMode = selected.asrMode.normalizedAsrMode(),
            asrProfileId = selected.asrProfileId,
            ttsEngine = ttsChoice.toLegacyTtsEngine(),
            minimaxApiKey = localMiniMaxApiKey,
            minimaxVoiceId = ttsChoice.voiceId.normalizedMiniMaxVoiceId(),
            lastLoginMode = this[LAST_LOGIN_MODE] ?: "",
            lastPhoneNumber = this[LAST_PHONE_NUMBER] ?: "",
        )
    }

    private suspend fun migrateMiniMaxCredentialIfNeeded(prefs: Preferences): String {
        val legacyPlaintextKey = prefs[MINIMAX_API_KEY].orEmpty().trim()
        if (legacyPlaintextKey.isNotEmpty()) {
            credentialVault.set(LOCAL_TTS_MINIMAX_CREDENTIAL_ID, legacyPlaintextKey)
            context.dataStore.edit { it.remove(MINIMAX_API_KEY) }
            return legacyPlaintextKey
        }
        return credentialVault.get(LOCAL_TTS_MINIMAX_CREDENTIAL_ID).orEmpty()
    }

    private fun Preferences.toAiSettings(): AiServiceSettings {
        val saved = this[AI_SERVICE_SETTINGS]
        if (!saved.isNullOrBlank()) return decodeAiServiceSettings(saved)
        return aiSettingsFromLegacyConfig(
            GatewayConfig(
                asrMode = globalAsrMode(),
                asrProfileId = globalAsrProfileId(),
                ttsEngine = (this[TTS_ENGINE] ?: "system").normalizedTtsEngine(),
                minimaxVoiceId = (this[MINIMAX_VOICE_ID] ?: "male-qn-qingse").normalizedMiniMaxVoiceId(),
            )
        )
    }

    private fun Preferences.makeLegacyProfile(): AgentProfile =
        AgentProfile(
            id = this[SELECTED_AGENT_PROFILE_ID] ?: LEGACY_PROFILE_ID,
            platform = AgentPlatform.OPENCLAW,
            displayName = this[PAIRED_BACKEND_LABEL] ?: AgentPlatform.OPENCLAW.defaultDisplayName,
            gatewayUrl = this[GATEWAY_URL] ?: "ws://192.168.1.14:8765",
            backendId = this[PAIRED_BACKEND_ID].orEmpty(),
            backendLabel = this[PAIRED_BACKEND_LABEL],
            token = this[TOKEN] ?: "",
            isPaired = this[PAIRED_BACKEND_ID] != null,
            asrMode = globalAsrMode(),
            asrProfileId = globalAsrProfileId(),
        )

    private fun Preferences.globalAsrMode(): String =
        (this[ASR_MODE] ?: "router").normalizedAsrMode()

    private fun Preferences.globalAsrProfileId(): String =
        if (globalAsrMode() == "backend") "" else (this[ASR_PROFILE_ID] ?: "")

    private fun AgentProfile.normalizedForSave(asrMode: String, asrProfileId: String): AgentProfile =
        copy(
            gatewayUrl = AgentProfile.canonicalWebSocketGatewayUrl(gatewayUrl),
            backendId = backendId.trim(),
            token = token.trim(),
            displayName = displayName.trim().ifEmpty { platform.defaultDisplayName },
            backendLabel = backendLabel?.trim()?.ifEmpty { null },
            asrMode = asrMode.normalizedAsrMode(),
            asrProfileId = if (asrMode == "backend") "" else asrProfileId,
            updatedAt = currentTimestampMillis(),
        )

    private fun AgentProfile.clearPairingIfConnectionIdentityChanged(previous: AgentProfile): AgentProfile {
        if (!connectionIdentityChanged(previous, this)) return this
        val previousBackendId = previous.backendId.trim()
        val nextBackendId = backendId.trim()
        return copy(
            isPaired = false,
            backendLabel = if (previousBackendId != nextBackendId) nextBackendId.ifBlank { null } else backendLabel,
        )
    }

    private fun connectionIdentityChanged(previous: AgentProfile, next: AgentProfile): Boolean =
        AgentProfile.normalizedGatewayKey(previous.gatewayUrl) != AgentProfile.normalizedGatewayKey(next.gatewayUrl) ||
            previous.backendId.trim() != next.backendId.trim() ||
            previous.token.trim() != next.token.trim()

    private fun persistProfiles(
        prefs: MutablePreferences,
        profiles: List<AgentProfile>,
        selectedProfileId: String,
    ) {
        val safeProfiles = profiles.ifEmpty { AgentProfilesState.default().profiles }
        val safeSelectedId = selectedProfileId.takeIf { id -> safeProfiles.any { it.id == id } }
            ?: safeProfiles.first().id
        prefs[AGENT_PROFILES] = encodeProfiles(safeProfiles)
        prefs[SELECTED_AGENT_PROFILE_ID] = safeSelectedId
        prefs.mirrorSelectedProfile(AgentProfilesState(safeProfiles, safeSelectedId))
    }

    private fun MutablePreferences.mirrorSelectedProfile(state: AgentProfilesState) {
        val selected = state.selectedProfile
        this[GATEWAY_URL] = selected.gatewayUrl
        this[TOKEN] = selected.token
        if (selected.backendId.isNotBlank() && selected.isPaired) {
            this[PAIRED_BACKEND_ID] = selected.backendId
        } else {
            remove(PAIRED_BACKEND_ID)
        }
        selected.backendLabel?.let { this[PAIRED_BACKEND_LABEL] = it } ?: remove(PAIRED_BACKEND_LABEL)
    }

    private fun canAcceptProfile(profiles: List<AgentProfile>, gatewayUrl: String, backendId: String): Boolean {
        val normalizedKey = "${AgentProfile.normalizedGatewayKey(gatewayUrl)}|$backendId"
        if (profiles.any { it.uniqueBackendKey == normalizedKey }) return true
        if (profiles.size == 1 && profiles.first().backendId.isBlank()) return true
        if (profiles.size >= SettingsManager.MAX_AGENT_PROFILES) return false
        return isGatewayCompatible(profiles, gatewayUrl)
    }

    private fun isGatewayCompatible(profiles: List<AgentProfile>, gatewayUrl: String): Boolean {
        val target = AgentProfile.normalizedGatewayKey(gatewayUrl)
        val configuredGateways = profiles
            .filter { it.backendId.isNotBlank() }
            .map { AgentProfile.normalizedGatewayKey(it.gatewayUrl) }
        val first = configuredGateways.firstOrNull() ?: return true
        return configuredGateways.all { it == first } && first == target
    }

    private fun resolvedProfileName(platform: AgentPlatform, label: String?, backendId: String): String {
        val trimmedLabel = label?.trim().orEmpty()
        if (trimmedLabel.isNotEmpty()) return trimmedLabel
        if (platform != AgentPlatform.CUSTOM) return platform.defaultDisplayName
        return backendId
    }

    private fun String.normalizedAsrMode(): String =
        if (this == "backend") "backend" else "router"

    private fun String.normalizedTtsEngine(): String =
        if (this == "minimax") "minimax" else "system"

    private fun String.normalizedMiniMaxVoiceId(): String =
        trim().ifEmpty { "male-qn-qingse" }
}
