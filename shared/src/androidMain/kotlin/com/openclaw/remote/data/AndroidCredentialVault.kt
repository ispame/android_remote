package com.openclaw.remote.data

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

class AndroidCredentialVault(context: Context) : CredentialVault {
    private val appContext = context.applicationContext
    private val prefs = appContext.getSharedPreferences("credential_vault_v1", Context.MODE_PRIVATE)

    override suspend fun get(id: String): String? = withContext(Dispatchers.IO) {
        val payload = prefs.getString(storageKey(id), null) ?: return@withContext null
        runCatching { decrypt(payload) }.getOrNull()
    }

    override suspend fun set(id: String, secret: String) {
        withContext(Dispatchers.IO) {
            val trimmed = secret.trim()
            if (trimmed.isEmpty()) {
                prefs.edit().remove(storageKey(id)).apply()
            } else {
                prefs.edit().putString(storageKey(id), encrypt(trimmed)).apply()
            }
        }
    }

    override suspend fun remove(id: String) {
        withContext(Dispatchers.IO) {
            prefs.edit().remove(storageKey(id)).apply()
        }
    }

    private fun encrypt(value: String): String {
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, secretKey())
        val ciphertext = cipher.doFinal(value.toByteArray(Charsets.UTF_8))
        return "${Base64.encodeToString(cipher.iv, Base64.NO_WRAP)}:${Base64.encodeToString(ciphertext, Base64.NO_WRAP)}"
    }

    private fun decrypt(payload: String): String {
        val parts = payload.split(":", limit = 2)
        require(parts.size == 2)
        val iv = Base64.decode(parts[0], Base64.NO_WRAP)
        val ciphertext = Base64.decode(parts[1], Base64.NO_WRAP)
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.DECRYPT_MODE, secretKey(), GCMParameterSpec(128, iv))
        return cipher.doFinal(ciphertext).toString(Charsets.UTF_8)
    }

    private fun secretKey(): SecretKey {
        val keyStore = KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }
        (keyStore.getEntry(KEY_ALIAS, null) as? KeyStore.SecretKeyEntry)?.secretKey?.let { return it }

        val keyGenerator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, ANDROID_KEYSTORE)
        keyGenerator.init(
            KeyGenParameterSpec.Builder(
                KEY_ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setRandomizedEncryptionRequired(true)
                .build()
        )
        return keyGenerator.generateKey()
    }

    private fun storageKey(id: String): String =
        "credential_" + Base64.encodeToString(id.toByteArray(Charsets.UTF_8), Base64.NO_WRAP)

    private companion object {
        const val ANDROID_KEYSTORE = "AndroidKeyStore"
        const val KEY_ALIAS = "bosonrelay_local_ai_credentials_v1"
        const val TRANSFORMATION = "AES/GCM/NoPadding"
    }
}
