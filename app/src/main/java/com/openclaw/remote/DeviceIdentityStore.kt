package com.openclaw.remote

import android.content.Context
import android.util.Base64
import java.io.File
import java.security.MessageDigest
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import org.bouncycastle.asn1.DEROctetString
import org.bouncycastle.asn1.pkcs.PrivateKeyInfo
import org.bouncycastle.crypto.generators.Ed25519KeyPairGenerator
import org.bouncycastle.crypto.params.Ed25519KeyGenerationParameters
import org.bouncycastle.crypto.params.Ed25519PrivateKeyParameters
import org.bouncycastle.crypto.params.Ed25519PublicKeyParameters
import org.bouncycastle.crypto.signers.Ed25519Signer
import org.bouncycastle.crypto.util.PrivateKeyInfoFactory

@Serializable
data class DeviceIdentity(
    val deviceId: String,
    val publicKeyRawBase64: String,
    val privateKeyPkcs8Base64: String,
    val createdAtMs: Long,
)

class DeviceIdentityStore(context: Context) {
    private val json = Json { ignoreUnknownKeys = true }
    private val identityFile = File(context.filesDir, "openclaw/identity/device.json")
    @Volatile
    private var cachedIdentity: DeviceIdentity? = null

    @Synchronized
    fun loadOrCreate(): DeviceIdentity {
        cachedIdentity?.let { return it }
        val existing = load()
        if (existing != null) {
            val derived = deriveDeviceId(existing.publicKeyRawBase64)
            if (derived != null && derived != existing.deviceId) {
                val updated = existing.copy(deviceId = derived)
                save(updated)
                cachedIdentity = updated
                return updated
            }
            cachedIdentity = existing
            return existing
        }

        val fresh = generate()
        save(fresh)
        cachedIdentity = fresh
        return fresh
    }

    fun signPayload(payload: String, identity: DeviceIdentity): String? {
        return try {
            val privateKeyBytes = Base64.decode(identity.privateKeyPkcs8Base64, Base64.DEFAULT)
            val pkInfo = PrivateKeyInfo.getInstance(privateKeyBytes)
            val parsed = pkInfo.parsePrivateKey()
            val rawPrivate = DEROctetString.getInstance(parsed).octets
            val privateKey = Ed25519PrivateKeyParameters(rawPrivate, 0)
            val signer = Ed25519Signer()
            signer.init(true, privateKey)
            val payloadBytes = payload.toByteArray(Charsets.UTF_8)
            signer.update(payloadBytes, 0, payloadBytes.size)
            base64UrlEncode(signer.generateSignature())
        } catch (_: Throwable) {
            null
        }
    }

    fun publicKeyBase64Url(identity: DeviceIdentity): String? {
        return try {
            val raw = Base64.decode(identity.publicKeyRawBase64, Base64.DEFAULT)
            base64UrlEncode(raw)
        } catch (_: Throwable) {
            null
        }
    }

    private fun load(): DeviceIdentity? {
        return try {
            if (!identityFile.exists()) {
                return null
            }
            val raw = identityFile.readText(Charsets.UTF_8)
            json.decodeFromString(DeviceIdentity.serializer(), raw)
        } catch (_: Throwable) {
            null
        }
    }

    private fun save(identity: DeviceIdentity) {
        try {
            identityFile.parentFile?.mkdirs()
            val encoded = json.encodeToString(DeviceIdentity.serializer(), identity)
            identityFile.writeText(encoded, Charsets.UTF_8)
        } catch (_: Throwable) {
            // best effort
        }
    }

    private fun generate(): DeviceIdentity {
        val generator = Ed25519KeyPairGenerator()
        generator.init(Ed25519KeyGenerationParameters(java.security.SecureRandom()))
        val keyPair = generator.generateKeyPair()
        val publicKey = keyPair.public as Ed25519PublicKeyParameters
        val privateKey = keyPair.private as Ed25519PrivateKeyParameters
        val rawPublic = publicKey.encoded
        val deviceId = sha256Hex(rawPublic)
        val pkcs8Bytes = PrivateKeyInfoFactory.createPrivateKeyInfo(privateKey).encoded
        return DeviceIdentity(
            deviceId = deviceId,
            publicKeyRawBase64 = Base64.encodeToString(rawPublic, Base64.NO_WRAP),
            privateKeyPkcs8Base64 = Base64.encodeToString(pkcs8Bytes, Base64.NO_WRAP),
            createdAtMs = System.currentTimeMillis(),
        )
    }

    private fun deriveDeviceId(publicKeyRawBase64: String): String? {
        return try {
            val raw = Base64.decode(publicKeyRawBase64, Base64.DEFAULT)
            sha256Hex(raw)
        } catch (_: Throwable) {
            null
        }
    }

    private fun sha256Hex(data: ByteArray): String {
        val digest = MessageDigest.getInstance("SHA-256").digest(data)
        val out = CharArray(digest.size * 2)
        var index = 0
        for (byte in digest) {
            val value = byte.toInt() and 0xff
            out[index++] = HEX[value ushr 4]
            out[index++] = HEX[value and 0x0f]
        }
        return String(out)
    }

    private fun base64UrlEncode(data: ByteArray): String {
        return Base64.encodeToString(data, Base64.URL_SAFE or Base64.NO_WRAP or Base64.NO_PADDING)
    }

    private companion object {
        val HEX = "0123456789abcdef".toCharArray()
    }
}
