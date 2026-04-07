package com.openclaw.remote

import android.content.Context

class DeviceAuthStore(context: Context) {
    private val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    fun loadToken(deviceId: String, role: String): String? {
        return prefs.getString(tokenKey(deviceId, role), null)?.trim()?.takeIf { it.isNotEmpty() }
    }

    fun saveToken(deviceId: String, role: String, token: String) {
        prefs.edit()
            .putString(tokenKey(deviceId, role), token.trim())
            .apply()
    }

    fun clearToken(deviceId: String, role: String) {
        prefs.edit()
            .remove(tokenKey(deviceId, role))
            .apply()
    }

    private fun tokenKey(deviceId: String, role: String): String {
        val normalizedDevice = deviceId.trim().lowercase()
        val normalizedRole = role.trim().lowercase()
        return "gateway.deviceToken.$normalizedDevice.$normalizedRole"
    }

    private companion object {
        const val PREFS_NAME = "openclaw_remote.device_auth"
    }
}
