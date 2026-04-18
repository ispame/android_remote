package com.openclaw.remote.data

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.*
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

private val Context.dataStore: DataStore<Preferences> by preferencesDataStore(name = "settings")

actual class SettingsManager(private val context: Context) {

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

    actual suspend fun updateConfig(config: GatewayConfig) {
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

    actual suspend fun updateDeviceId(id: String) {
        context.dataStore.edit { prefs ->
            prefs[DEVICE_ID] = id
        }
    }

    actual suspend fun updateDeviceLabel(label: String) {
        context.dataStore.edit { prefs ->
            prefs[DEVICE_LABEL] = label
        }
    }

    actual suspend fun updateGatewayUrl(url: String) {
        context.dataStore.edit { prefs ->
            prefs[GATEWAY_URL] = url
        }
    }

    actual suspend fun updatePairedBackend(backendId: String?, backendLabel: String?) {
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

    actual suspend fun clearConfig() {
        context.dataStore.edit { it.clear() }
    }
}
