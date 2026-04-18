package com.openclaw.remote.data

import kotlinx.coroutines.flow.Flow

/**
 * Settings Manager - cross-platform abstraction for persistent settings.
 */
expect class SettingsManager() {
    val configFlow: Flow<GatewayConfig>
    suspend fun updateConfig(config: GatewayConfig)
    suspend fun updateDeviceId(id: String)
    suspend fun updateDeviceLabel(label: String)
    suspend fun updateGatewayUrl(url: String)
    suspend fun updatePairedBackend(backendId: String?, backendLabel: String?)
    suspend fun clearConfig()
}
