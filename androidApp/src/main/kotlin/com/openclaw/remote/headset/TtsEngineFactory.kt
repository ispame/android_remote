package com.openclaw.remote.headset

import android.content.Context

object TtsEngineFactory {
    private const val ENGINE_SYSTEM = "system"
    private const val ENGINE_MINIMAX = "minimax"

    fun create(engine: String, context: Context): TtsEngine {
        return when (engine) {
            ENGINE_MINIMAX -> MiniMaxTtsEngine(context)
            else -> SystemTtsEngine(context)
        }
    }

    fun availableEngines(): List<Pair<String, String>> {
        return listOf(
            ENGINE_SYSTEM to "系统 TTS",
            ENGINE_MINIMAX to "MiniMax"
        )
    }
}