package com.openclaw.remote.data

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.*
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

private val Context.dataStore: DataStore<Preferences> by preferencesDataStore(name = "settings")

class SettingsManagerAndroid(private val context: Context) : SettingsManager {

    companion object {
        private val GATEWAY_URL = stringPreferencesKey("gateway_url")
        private val DEVICE_ID = stringPreferencesKey("device_id")
        private val DEVICE_LABEL = stringPreferencesKey("device_label")
        private val TOKEN = stringPreferencesKey("token")
        private val PAIRED_BACKEND_ID = stringPreferencesKey("paired_backend_id")
        private val PAIRED_BACKEND_LABEL = stringPreferencesKey("paired_backend_label")
        private val ASR_MODE = stringPreferencesKey("asr_mode")
        private val ASR_PROFILE_ID = stringPreferencesKey("asr_profile_id")
        private val TTS_ENGINE = stringPreferencesKey("tts_engine")
        private val MINIMAX_API_KEY = stringPreferencesKey("minimax_api_key")
        private val MINIMAX_VOICE_ID = stringPreferencesKey("minimax_voice_id")
    }

    override val configFlow: Flow<GatewayConfig> = context.dataStore.data.map { prefs ->
        GatewayConfig(
            gatewayUrl = prefs[GATEWAY_URL] ?: "ws://192.168.1.14:8765",
            deviceId = prefs[DEVICE_ID] ?: "",
            deviceLabel = prefs[DEVICE_LABEL] ?: "",
            token = prefs[TOKEN] ?: "",
            pairedBackendId = prefs[PAIRED_BACKEND_ID],
            pairedBackendLabel = prefs[PAIRED_BACKEND_LABEL],
            asrMode = prefs[ASR_MODE] ?: "router",
            asrProfileId = prefs[ASR_PROFILE_ID] ?: "",
            ttsEngine = prefs[TTS_ENGINE] ?: "system",
            minimaxApiKey = prefs[MINIMAX_API_KEY] ?: "",
            minimaxVoiceId = prefs[MINIMAX_VOICE_ID] ?: "female_sunny_zh",
        )
    }

    override suspend fun updateConfig(config: GatewayConfig) {
        context.dataStore.edit { prefs ->
            prefs[GATEWAY_URL] = config.gatewayUrl
            prefs[DEVICE_ID] = config.deviceId
            prefs[DEVICE_LABEL] = config.deviceLabel
            prefs[TOKEN] = config.token
            prefs[ASR_MODE] = config.asrMode
            prefs[ASR_PROFILE_ID] = config.asrProfileId
            prefs[TTS_ENGINE] = config.ttsEngine
            prefs[MINIMAX_API_KEY] = config.minimaxApiKey
            prefs[MINIMAX_VOICE_ID] = config.minimaxVoiceId
            if (config.pairedBackendId != null) {
                prefs[PAIRED_BACKEND_ID] = config.pairedBackendId
            } else {
                prefs.remove(PAIRED_BACKEND_ID)
            }
            if (config.pairedBackendLabel != null) {
                prefs[PAIRED_BACKEND_LABEL] = config.pairedBackendLabel
            } else {
                prefs.remove(PAIRED_BACKEND_LABEL)
            }
        }
    }

    override suspend fun updateDeviceId(id: String) {
        context.dataStore.edit { prefs ->
            prefs[DEVICE_ID] = id
        }
    }

    override suspend fun updateDeviceLabel(label: String) {
        context.dataStore.edit { prefs ->
            prefs[DEVICE_LABEL] = label
        }
    }

    override suspend fun updateGatewayUrl(url: String) {
        context.dataStore.edit { prefs ->
            prefs[GATEWAY_URL] = url
        }
    }

    override suspend fun updatePairedBackend(backendId: String?, backendLabel: String?) {
        context.dataStore.edit { prefs ->
            if (backendId != null) {
                prefs[PAIRED_BACKEND_ID] = backendId
            } else {
                prefs.remove(PAIRED_BACKEND_ID)
            }
            if (backendLabel != null) {
                prefs[PAIRED_BACKEND_LABEL] = backendLabel
            } else {
                prefs.remove(PAIRED_BACKEND_LABEL)
            }
        }
    }

    override suspend fun clearConfig() {
        context.dataStore.edit { it.clear() }
    }
}
