package com.openclaw.remote.data

import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import platform.Foundation.NSUserDefaults

actual class SettingsManager {
    private val defaults = NSUserDefaults.standardUserDefaults()

    private val _configFlow = MutableStateFlow(loadConfig())

    actual val configFlow: Flow<GatewayConfig> = _configFlow.asStateFlow()

    private fun loadConfig(): GatewayConfig {
        return GatewayConfig(
            gatewayUrl = defaults.stringForKey("gateway_url") ?: "ws://192.168.1.14:8765",
            deviceId = defaults.stringForKey("device_id") ?: "",
            deviceLabel = defaults.stringForKey("device_label") ?: "",
            token = defaults.stringForKey("token") ?: "",
            pairedBackendId = defaults.stringForKey("paired_backend_id"),
            pairedBackendLabel = defaults.stringForKey("paired_backend_label"),
        )
    }

    private fun saveConfig(config: GatewayConfig) {
        defaults.setObject(config.gatewayUrl, forKey = "gateway_url")
        defaults.setObject(config.deviceId, forKey = "device_id")
        defaults.setObject(config.deviceLabel, forKey = "device_label")
        defaults.setObject(config.token, forKey = "token")
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
    }

    actual suspend fun updateConfig(config: GatewayConfig) {
        saveConfig(config)
    }

    actual suspend fun updateDeviceId(id: String) {
        val current = _configFlow.value
        saveConfig(current.copy(deviceId = id))
    }

    actual suspend fun updateDeviceLabel(label: String) {
        val current = _configFlow.value
        saveConfig(current.copy(deviceLabel = label))
    }

    actual suspend fun updateGatewayUrl(url: String) {
        val current = _configFlow.value
        saveConfig(current.copy(gatewayUrl = url))
    }

    actual suspend fun updatePairedBackend(backendId: String?, backendLabel: String?) {
        val current = _configFlow.value
        saveConfig(current.copy(pairedBackendId = backendId, pairedBackendLabel = backendLabel))
    }

    actual suspend fun clearConfig() {
        defaults.removeObjectForKey("gateway_url")
        defaults.removeObjectForKey("device_id")
        defaults.removeObjectForKey("device_label")
        defaults.removeObjectForKey("token")
        defaults.removeObjectForKey("paired_backend_id")
        defaults.removeObjectForKey("paired_backend_label")
        _configFlow.value = GatewayConfig()
    }
}
