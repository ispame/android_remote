package com.openclaw.remote.data

import platform.Foundation.NSDate
import platform.Foundation.NSUUID

actual fun randomUuid(): String = NSUUID().UUIDString()

actual fun currentTimestampMillis(): Long =
    (NSDate().timeIntervalSince1970 * 1000).toLong()
