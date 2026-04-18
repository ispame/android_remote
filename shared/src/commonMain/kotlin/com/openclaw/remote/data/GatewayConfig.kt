package com.openclaw.remote.data

/**
 * App configuration for connecting to Gateway Router.
 */
data class GatewayConfig(
    val gatewayUrl: String = "ws://192.168.1.14:8765",
    val deviceId: String = "",
    val deviceLabel: String = "",
    val token: String = "",
    val pairedBackendId: String? = null,
    val pairedBackendLabel: String? = null,
)
