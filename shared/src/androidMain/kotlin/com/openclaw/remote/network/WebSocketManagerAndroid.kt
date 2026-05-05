package com.openclaw.remote.network

actual object Base64 {
    actual fun encode(data: ByteArray): String {
        return android.util.Base64.encodeToString(data, android.util.Base64.NO_WRAP)
    }
}
