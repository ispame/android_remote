package com.openclaw.remote.viewmodel

import com.openclaw.remote.data.GatewayConfig
import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertNotEquals
import kotlin.test.assertTrue

class ChatViewModelConfigTest {
    @Test
    fun connectionKeyIgnoresPairingLabelAndTtsSettings() {
        val base = GatewayConfig(
            gatewayUrl = "wss://boson-tech.top",
            deviceId = "device-a",
            deviceLabel = "phone",
            token = "token",
            pairedBackendId = "bk_openclaw",
            pairedBackendLabel = "OpenClaw",
            asrMode = "router",
            asrProfileId = "profile-a",
            ttsEngine = "system",
            minimaxApiKey = "",
        )
        val changedNonConnectionSettings = base.copy(
            pairedBackendLabel = "OpenClaw Agent",
            ttsEngine = "minimax",
            minimaxApiKey = "test-key",
        )

        assertFalse(
            shouldReconnectForConfig(
                previous = base.toChatConnectionKey(effectiveDeviceId = base.deviceId),
                next = changedNonConnectionSettings.toChatConnectionKey(
                    effectiveDeviceId = changedNonConnectionSettings.deviceId,
                ),
            ),
        )
    }

    @Test
    fun connectionKeyChangesWhenConfiguredBackendChanges() {
        val base = GatewayConfig(deviceId = "device-a", pairedBackendId = "bk_openclaw")
        val changedBackend = base.copy(pairedBackendId = "bk_other")

        assertNotEquals(
            base.toChatConnectionKey(effectiveDeviceId = base.deviceId),
            changedBackend.toChatConnectionKey(effectiveDeviceId = changedBackend.deviceId),
        )
    }

    @Test
    fun pairedBackendPersistenceSkipsUnchangedValues() {
        val config = GatewayConfig(
            pairedBackendId = "bk_openclaw",
            pairedBackendLabel = "OpenClaw",
        )

        assertFalse(shouldPersistPairedBackend(config, "bk_openclaw", "OpenClaw"))
        assertTrue(shouldPersistPairedBackend(config, "bk_openclaw", "OpenClaw Agent"))
    }
}
