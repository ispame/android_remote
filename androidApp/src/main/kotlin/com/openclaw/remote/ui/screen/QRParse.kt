package com.openclaw.remote.ui.screen

import com.openclaw.remote.data.AgentPlatform
import kotlinx.serialization.json.*

sealed class QRParseResult {
    data class Success(
        val gatewayUrl: String,
        val backendId: String,
        val token: String,
        val platform: AgentPlatform = AgentPlatform.OPENCLAW,
        val label: String? = null,
    ) : QRParseResult()
    data class Error(val message: String) : QRParseResult()
}

fun parseQRPack(
    scannedText: String,
    onResult: (QRParseResult) -> Unit
) {
    try {
        if (scannedText.startsWith("openclaw://connect")) {
            val parts = scannedText.removePrefix("openclaw://connect?").split("&")
            var gateway = ""
            var backendId = ""
            var token = ""
            var platform = AgentPlatform.OPENCLAW
            var label: String? = null
            parts.forEach { part ->
                val keyValue = part.split("=", limit = 2)
                if (keyValue.size == 2) {
                    when (keyValue[0]) {
                        "gateway" -> gateway = keyValue[1].decodeURLComponent()
                        "agentId", "backendId" -> backendId = keyValue[1].decodeURLComponent()
                        "token" -> token = keyValue[1].decodeURLComponent()
                        "platform" -> platform = AgentPlatform.fromWireValue(keyValue[1].decodeURLComponent())
                        "label", "backendLabel" -> label = keyValue[1].decodeURLComponent()
                    }
                }
            }
            if (gateway.isEmpty() || backendId.isEmpty()) {
                onResult(QRParseResult.Error("缺少 gateway 或 backendId 参数"))
                return
            }
            onResult(QRParseResult.Success(gateway, backendId, token, platform, label))
            return
        }

        if (scannedText.trimStart().startsWith("{")) {
            val json = Json.parseToJsonElement(scannedText).jsonObject
            val gateway = json["gateway"]?.jsonPrimitive?.content ?: ""
            val agentId = json["agentId"]?.jsonPrimitive?.content
                ?: json["backendId"]?.jsonPrimitive?.content ?: ""
            val token = json["token"]?.jsonPrimitive?.content ?: ""
            val platform = AgentPlatform.fromWireValue(json["platform"]?.jsonPrimitive?.content)
            val label = json["label"]?.jsonPrimitive?.contentOrNull
                ?: json["backendLabel"]?.jsonPrimitive?.contentOrNull
            if (gateway.isEmpty() || agentId.isEmpty()) {
                onResult(QRParseResult.Error("缺少 gateway 或 backendId 字段"))
                return
            }
            onResult(QRParseResult.Success(gateway, agentId, token, platform, label))
            return
        }

        onResult(QRParseResult.Error("不支持的二维码格式"))
    } catch (e: Exception) {
        onResult(QRParseResult.Error("解析失败: ${e.message}"))
    }
}

private fun String.decodeURLComponent(): String {
    return java.net.URLDecoder.decode(this, "UTF-8")
}
