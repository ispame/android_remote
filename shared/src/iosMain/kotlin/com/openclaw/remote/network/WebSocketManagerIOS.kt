package com.openclaw.remote.network

actual object Base64 {
    actual fun encode(data: ByteArray): String {
        return platform.Foundation.NSData(data.toNSData()).base64EncodedString()
    }
}

private fun ByteArray.toNSData(): platform.Foundation.NSData {
    return platform.Foundation.NSData.create(bytes = this)
}
