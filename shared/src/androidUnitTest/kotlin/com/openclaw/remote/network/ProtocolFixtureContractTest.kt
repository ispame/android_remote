package com.openclaw.remote.network

import java.io.File
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertTrue
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

class ProtocolFixtureContractTest {
    private val json = Json {
        ignoreUnknownKeys = false
        prettyPrint = false
    }

    @Test
    fun androidDecodesAndEncodesCanonicalV2Fixture() {
        val fixture = loadCanonicalFixture()
        val root = json.parseToJsonElement(fixture).jsonObject

        val http = root.requiredObject("http")
        assertEquals("+8613800138000", http.requiredObject("sms_request").requiredObject("request").requiredString("phone_number"))
        assertEquals("acct_abc123", http.requiredObject("sms_verify").requiredObject("response").requiredString("account_id"))

        val entries = root.requiredArray("ws")
        assertEquals(
            listOf(
                "app_register",
                "app_registered",
                "backend_register",
                "backend_registered",
                "pair_request",
                "pair_response",
                "message_text",
                "message_audio",
                "message_ack",
                "history_request",
                "history_response",
                "session_preempted",
            ),
            entries.map { it.jsonObject.requiredString("name") },
        )

        entries.forEach { entry ->
            val name = entry.jsonObject.requiredString("name")
            val frame = entry.jsonObject.requiredObject("frame")
            frame.assertNoLegacyIdentityFields(path = name)
            assertEquals(frame, json.parseToJsonElement(json.encodeToString<JsonElement>(frame)).jsonObject)
            assertFrameShape(name, frame)
        }
    }

    private fun assertFrameShape(name: String, frame: JsonObject) {
        when (frame.requiredString("type")) {
            "app_register" -> {
                frame.requiredString("access_token")
                frame.requiredString("terminal_label")
                frame.requiredString("platform")
            }
            "app_registered" -> {
                assertTrue(frame.requiredBoolean("success"))
                frame.requiredString("account_id")
                assertEquals("single_active", frame.requiredString("session_policy"))
                frame.requiredArray("paired_backends").forEach { backend ->
                    backend.jsonObject.requiredString("backend_id")
                    backend.jsonObject.requiredString("backend_label")
                    backend.jsonObject.requiredString("paired_at")
                    backend.jsonObject.requiredBoolean("connected")
                }
            }
            "backend_register" -> {
                frame.requiredString("backend_id")
                frame.requiredString("backend_label")
            }
            "backend_registered" -> {
                assertTrue(frame.requiredBoolean("success"))
                frame.requiredString("backend_id")
                frame.requiredString("backend_label")
            }
            "pair_request" -> {
                frame.requiredString("account_id")
                frame.requiredString("backend_id")
                frame.requiredString("terminal_label")
            }
            "pair_response" -> {
                frame.requiredString("account_id")
                frame.requiredString("backend_id")
                assertTrue(frame.requiredBoolean("approved"))
            }
            "message" -> {
                frame.requiredString("account_id")
                frame.requiredString("backend_id")
                frame.requiredString("message_id")
                frame.requiredString("content")
                frame.requiredString("content_type")
                frame.requiredString("timestamp")
                if (name == "message_audio") {
                    val audio = frame.requiredObject("audio")
                    assertEquals("wav", audio.requiredString("format"))
                    assertEquals("pcm_s16le", audio.requiredString("codec"))
                    assertEquals(16000, audio.requiredInt("sample_rate"))
                    assertEquals(1, audio.requiredInt("channels"))
                    assertEquals("backend", frame.requiredObject("asr").requiredString("mode"))
                }
            }
            "message_ack" -> frame.requiredString("message_id")
            "history_request" -> {
                frame.requiredString("account_id")
                frame.requiredString("backend_id")
                assertEquals("current", frame.requiredString("session_key"))
                frame.requiredString("before_timestamp")
                assertEquals(30, frame.requiredInt("limit"))
            }
            "history_response" -> {
                frame.requiredString("account_id")
                frame.requiredString("backend_id")
                assertEquals("current", frame.requiredString("session_key"))
                assertTrue(frame.requiredBoolean("has_more"))
                assertTrue(frame["error"] is JsonNull)
                assertTrue(frame.requiredArray("messages").isNotEmpty())
            }
            "session_preempted" -> {
                assertEquals("replaced_by_new_terminal", frame.requiredString("reason"))
                frame.requiredString("replaced_at")
                frame.requiredString("replacement_terminal_label")
            }
            else -> error("Unhandled fixture frame $name type=${frame["type"]}")
        }
    }
}

private val legacyIdentityFields = setOf(
    "device_id",
    "app_id",
    "client_id",
    "from_app_id",
    "target_app_id",
    "target_id",
    "from",
    "to",
)

private fun JsonObject.assertNoLegacyIdentityFields(path: String) {
    for ((key, value) in this) {
        assertFalse(key in legacyIdentityFields, "legacy identity field $path.$key must not appear in V2 fixture")
        when (value) {
            is JsonObject -> value.assertNoLegacyIdentityFields("$path.$key")
            is JsonArray -> value.forEachIndexed { index, child ->
                if (child is JsonObject) child.assertNoLegacyIdentityFields("$path.$key[$index]")
            }
            else -> {}
        }
    }
}

private fun JsonObject.requiredObject(name: String): JsonObject =
    assertNotNull(this[name] as? JsonObject, "missing object field $name")

private fun JsonObject.requiredArray(name: String): JsonArray =
    assertNotNull(this[name] as? JsonArray, "missing array field $name")

private fun JsonObject.requiredString(name: String): String =
    assertNotNull(this[name]?.jsonPrimitive?.contentOrNull?.takeIf { it.isNotBlank() }, "missing string field $name")

private fun JsonObject.requiredBoolean(name: String): Boolean =
    assertNotNull(this[name]?.jsonPrimitive?.booleanOrNull, "missing boolean field $name")

private fun JsonObject.requiredInt(name: String): Int =
    assertNotNull(this[name]?.jsonPrimitive?.intOrNull, "missing int field $name")

private fun loadCanonicalFixture(): String {
    val envPath = System.getenv("OPENCLAW_PROTOCOL_FIXTURE")
        ?.takeIf { it.isNotBlank() }
        ?.let(::File)
    if (envPath != null && envPath.isFile) return envPath.readText()

    return protocolFixtureCandidates()
        .firstOrNull { it.isFile }
        ?.readText()
        ?: error(
            "Cannot find account-scoped-session-v2.json. " +
                "Set OPENCLAW_PROTOCOL_FIXTURE or keep android_remote next to android-remote-gateway.",
        )
}

private fun protocolFixtureCandidates(): Sequence<File> {
    val fixturePath = "packages/protocol/fixtures/account-scoped-session-v2.json"
    val starts = listOf(File(System.getProperty("user.dir") ?: "."), File("."))
        .map { it.canonicalFile }
        .distinct()
    return starts.asSequence().flatMap { start ->
        generateSequence(start) { it.parentFile }.flatMap { dir ->
            sequenceOf(
                File(dir, "../android-remote-gateway/$fixturePath").canonicalFile,
                File(dir, "android-remote-gateway/$fixturePath").canonicalFile,
                File(dir, fixturePath).canonicalFile,
            )
        }
    }
}
