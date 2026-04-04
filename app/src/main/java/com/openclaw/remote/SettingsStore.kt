package com.openclaw.remote

import android.content.Context

class SettingsStore(context: Context) {
    private val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    fun load(): RemoteSettings {
        val backend = runCatching {
            BackendKind.valueOf(prefs.getString(KEY_BACKEND, BackendKind.NANOBOT.name).orEmpty())
        }.getOrDefault(BackendKind.NANOBOT)

        return RemoteSettings(
            backend = backend,
            host = prefs.getString(KEY_HOST, "192.168.1.14").orEmpty(),
            portText = prefs.getString(KEY_PORT, defaultPortFor(backend)).orEmpty(),
            useTls = prefs.getBoolean(KEY_USE_TLS, false),
            nanobotPath = prefs.getString(KEY_NANOBOT_PATH, "/ws").orEmpty(),
            openClawSharedToken = prefs.getString(KEY_OPENCLAW_SHARED_TOKEN, "").orEmpty(),
            openClawBootstrapToken = prefs.getString(KEY_OPENCLAW_BOOTSTRAP_TOKEN, "").orEmpty(),
            openClawPassword = prefs.getString(KEY_OPENCLAW_PASSWORD, "").orEmpty(),
            openClawSessionKey = prefs.getString(KEY_OPENCLAW_SESSION_KEY, "main").orEmpty(),
        )
    }

    fun save(settings: RemoteSettings) {
        prefs.edit()
            .putString(KEY_BACKEND, settings.backend.name)
            .putString(KEY_HOST, settings.host)
            .putString(KEY_PORT, settings.portText)
            .putBoolean(KEY_USE_TLS, settings.useTls)
            .putString(KEY_NANOBOT_PATH, settings.nanobotPath)
            .putString(KEY_OPENCLAW_SHARED_TOKEN, settings.openClawSharedToken)
            .putString(KEY_OPENCLAW_BOOTSTRAP_TOKEN, settings.openClawBootstrapToken)
            .putString(KEY_OPENCLAW_PASSWORD, settings.openClawPassword)
            .putString(KEY_OPENCLAW_SESSION_KEY, settings.openClawSessionKey)
            .apply()
    }

    private companion object {
        const val PREFS_NAME = "openclaw_remote.settings"
        const val KEY_BACKEND = "backend"
        const val KEY_HOST = "host"
        const val KEY_PORT = "port"
        const val KEY_USE_TLS = "use_tls"
        const val KEY_NANOBOT_PATH = "nanobot_path"
        const val KEY_OPENCLAW_SHARED_TOKEN = "openclaw_shared_token"
        const val KEY_OPENCLAW_BOOTSTRAP_TOKEN = "openclaw_bootstrap_token"
        const val KEY_OPENCLAW_PASSWORD = "openclaw_password"
        const val KEY_OPENCLAW_SESSION_KEY = "openclaw_session_key"
    }
}
