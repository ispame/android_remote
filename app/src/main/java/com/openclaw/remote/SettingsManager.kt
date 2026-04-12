package com.openclaw.remote

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.*
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

private val Context.dataStore: DataStore<Preferences> by preferencesDataStore(name = "settings")

/**
 * App configuration for connecting to Gateway Router.
 * Phase 3: Replaces old deviceToken+backendType with pairedBackendId.
 */
data class GatewayConfig(
    val gatewayUrl: String = "ws://192.168.1.14:8765",
    val deviceId: String = "",        // 设备唯一 ID（自动生成）
    val deviceLabel: String = "",       // 显示名称
    val token: String = "",             // 配对 Token
    val pairedBackendId: String? = null,    // 已配对的 backend ID（null=未配对）
    val pairedBackendLabel: String? = null,  // 已配对的 backend 显示名
)

class SettingsManager(private val context: Context) {

    companion object {
        private val GATEWAY_URL = stringPreferencesKey("gateway_url")
        private val DEVICE_ID = stringPreferencesKey("device_id")
        private val DEVICE_LABEL = stringPreferencesKey("device_label")
        private val TOKEN = stringPreferencesKey("token")
        private val PAIRED_BACKEND_ID = stringPreferencesKey("paired_backend_id")
        private val PAIRED_BACKEND_LABEL = stringPreferencesKey("paired_backend_label")
    }

    val configFlow: Flow<GatewayConfig> = context.dataStore.data.map { prefs ->
        GatewayConfig(
            gatewayUrl = prefs[GATEWAY_URL] ?: "ws://192.168.1.14:8765",
            deviceId = prefs[DEVICE_ID] ?: "",
            deviceLabel = prefs[DEVICE_LABEL] ?: "",
            token = prefs[TOKEN] ?: "",
            pairedBackendId = prefs[PAIRED_BACKEND_ID],
            pairedBackendLabel = prefs[PAIRED_BACKEND_LABEL],
        )
    }

    suspend fun updateConfig(config: GatewayConfig) {
        context.dataStore.edit { prefs ->
            prefs[GATEWAY_URL] = config.gatewayUrl
            prefs[DEVICE_ID] = config.deviceId
            prefs[DEVICE_LABEL] = config.deviceLabel
            prefs[TOKEN] = config.token
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

    suspend fun updateGatewayUrl(url: String) {
        context.dataStore.edit { prefs ->
            prefs[GATEWAY_URL] = url
        }
    }

    suspend fun updateDeviceId(id: String) {
        context.dataStore.edit { prefs ->
            prefs[DEVICE_ID] = id
        }
    }

    suspend fun updateDeviceLabel(label: String) {
        context.dataStore.edit { prefs ->
            prefs[DEVICE_LABEL] = label
        }
    }

    suspend fun updatePairedBackend(backendId: String?, backendLabel: String?) {
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

    suspend fun clearConfig() {
        context.dataStore.edit { it.clear() }
    }
}
