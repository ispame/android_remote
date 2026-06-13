package com.openclaw.remote.data

/**
 * App configuration for connecting to Gateway Router.
 */
data class GatewayConfig(
    val profileId: String = "",
    val gatewayUrl: String = "ws://192.168.1.14:8765",
    val accountId: String = "",
    val accessToken: String = "",
    val refreshToken: String = "",
    val accessExpiresAt: String = "",
    val refreshExpiresAt: String = "",
    val deviceLabel: String = "",
    val token: String = "",
    val pairedBackendId: String? = null,
    val pairedBackendLabel: String? = null,
    val asrMode: String = "router",
    val asrProfileId: String = "",
    val ttsEngine: String = "system",
    val minimaxApiKey: String = "",
    val minimaxVoiceId: String = "male-qn-qingse",
    val lastLoginMode: String = "",
    val lastPhoneNumber: String = "",
)
