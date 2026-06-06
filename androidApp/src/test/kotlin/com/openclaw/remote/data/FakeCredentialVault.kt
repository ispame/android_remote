package com.openclaw.remote.data

class FakeCredentialVault : CredentialVault {
    private val secrets = mutableMapOf<String, String>()

    override suspend fun get(id: String): String? = secrets[id]

    override suspend fun set(id: String, secret: String) {
        secrets[id] = secret
    }

    override suspend fun remove(id: String) {
        secrets.remove(id)
    }
}
