package com.openclaw.remote.domain

/**
 * Connection states for WebSocket connection to Gateway.
 */
enum class ConnectionState {
    DISCONNECTED,
    CONNECTING,
    CONNECTED,
    REGISTERED,
    PAIRED,
}
