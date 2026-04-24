package com.openclaw.remote.ui.screen

import kotlinx.serialization.json.*

sealed class QRParseResult {
    data class Success(val gatewayUrl: String, val backendId: String, val token: String) : QRParseResult()
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
            var agentId = ""
            var token = ""
            parts.forEach { part ->
                val keyValue = part.split("=")
                if (keyValue.size == 2) {
                    when (keyValue[0]) {
                        "gateway" -> gateway = keyValue[1].decodeURLComponent()
                        "agentId" -> agentId = keyValue[1].decodeURLComponent()
                        "token" -> token = keyValue[1].decodeURLComponent()
                    }
                }
            }
            if (gateway.isEmpty() || agentId.isEmpty()) {
                onResult(QRParseResult.Error("缺少 gateway 或 agentId 参数"))
                return
            }
            onResult(QRParseResult.Success(gateway, agentId, token))
            return
        }

        if (scannedText.trimStart().startsWith("{")) {
            val json = Json.parseToJsonElement(scannedText).jsonObject
            val gateway = json["gateway"]?.jsonPrimitive?.content ?: ""
            val agentId = json["agentId"]?.jsonPrimitive?.content
                ?: json["backendId"]?.jsonPrimitive?.content ?: ""
            val token = json["token"]?.jsonPrimitive?.content ?: ""
            if (gateway.isEmpty() || agentId.isEmpty()) {
                onResult(QRParseResult.Error("缺少 gateway 或 agentId 字段"))
                return
            }
            onResult(QRParseResult.Success(gateway, agentId, token))
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
