package com.openclaw.remote.data

import java.util.UUID

actual fun randomUuid(): String = UUID.randomUUID().toString()

actual fun currentTimestampMillis(): Long = System.currentTimeMillis()
