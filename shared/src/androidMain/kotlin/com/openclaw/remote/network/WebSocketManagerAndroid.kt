package com.openclaw.remote.network

actual fun Base64.encode(data: ByteArray): String {
    return android.util.Base64.encodeToString(data, android.util.Base64.NO_WRAP)
}
