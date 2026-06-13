package com.openclaw.remote.auth

import com.openclaw.remote.data.AiServiceChoice
import io.ktor.client.HttpClient
import io.ktor.client.call.body
import io.ktor.client.plugins.contentnegotiation.ContentNegotiation
import io.ktor.client.request.header
import io.ktor.client.request.post
import io.ktor.client.request.setBody
import io.ktor.client.statement.HttpResponse
import io.ktor.http.ContentType
import io.ktor.http.HttpHeaders
import io.ktor.http.contentType
import io.ktor.serialization.kotlinx.json.json
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put

data class AiChatMessage(
    val role: String,
    val content: String,
)

class OpenAICompatibleChatClient(
    private val client: HttpClient = defaultAiHttpClient(),
) {
    suspend fun chat(
        baseUrl: String,
        apiKey: String,
        model: String,
        messages: List<AiChatMessage>,
    ): String {
        val response = client.post("${baseUrl.trimEnd('/')}/chat/completions") {
            header(HttpHeaders.Authorization, "Bearer ${apiKey.trim()}")
            contentType(ContentType.Application.Json)
            setBody(
                buildJsonObject {
                    put("model", model.ifBlank { "gpt-4o-mini" })
                    put("messages", messages.toOpenAiMessages())
                }.toString()
            )
        }
        return parseOpenAiChatText(response)
    }
}

class AnthropicChatClient(
    private val client: HttpClient = defaultAiHttpClient(),
) {
    suspend fun chat(
        baseUrl: String,
        apiKey: String,
        model: String,
        messages: List<AiChatMessage>,
    ): String {
        val system = messages.firstOrNull { it.role == "system" }?.content
        val userMessages = messages.filterNot { it.role == "system" }
        val response = client.post("${baseUrl.trimEnd('/')}/messages") {
            header("x-api-key", apiKey.trim())
            header("anthropic-version", "2023-06-01")
            contentType(ContentType.Application.Json)
            setBody(
                buildJsonObject {
                    put("model", model.ifBlank { "claude-sonnet-4-20250514" })
                    put("max_tokens", 2048)
                    system?.let { put("system", it) }
                    put("messages", userMessages.toAnthropicMessages())
                }.toString()
            )
        }
        return parseAnthropicChatText(response)
    }
}

fun AiServiceChoice.resolvedCredentialId(): String =
    credentialId.ifBlank {
        when (providerId) {
            "claude" -> "llm:claude"
            "minimax" -> "llm:minimax"
            "kimi" -> "llm:kimi"
            "doubao" -> "llm:doubao"
            "openai-compatible" -> "llm:openai-compatible"
            else -> providerId.takeIf { it.isNotBlank() }?.let { "llm:$it" }.orEmpty()
        }
    }

private fun defaultAiHttpClient(): HttpClient =
    HttpClient {
        install(ContentNegotiation) {
            json(Json { ignoreUnknownKeys = true })
        }
    }

private fun List<AiChatMessage>.toOpenAiMessages(): JsonArray =
    buildJsonArray {
        forEach { message ->
            add(
                buildJsonObject {
                    put("role", message.role)
                    put("content", message.content)
                }
            )
        }
    }

private fun List<AiChatMessage>.toAnthropicMessages(): JsonArray =
    buildJsonArray {
        forEach { message ->
            add(
                buildJsonObject {
                    put("role", if (message.role == "assistant") "assistant" else "user")
                    put("content", message.content)
                }
            )
        }
    }

private suspend fun parseOpenAiChatText(response: HttpResponse): String {
    val obj = Json.parseToJsonElement(response.body<String>()).jsonObject
    return obj["choices"]?.jsonArray?.firstOrNull()
        ?.jsonObject?.get("message")
        ?.jsonObject?.get("content")
        ?.jsonPrimitive?.contentOrNull
        .orEmpty()
}

private suspend fun parseAnthropicChatText(response: HttpResponse): String {
    val obj = Json.parseToJsonElement(response.body<String>()).jsonObject
    return obj["content"]?.jsonArray
        ?.mapNotNull { item ->
            item.jsonObject["text"]?.jsonPrimitive?.contentOrNull
        }
        ?.joinToString("\n")
        .orEmpty()
}
