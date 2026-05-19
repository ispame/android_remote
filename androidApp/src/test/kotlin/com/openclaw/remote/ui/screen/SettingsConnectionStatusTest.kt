package com.openclaw.remote.ui.screen

import com.openclaw.remote.domain.ConnectionState
import com.openclaw.remote.domain.PairingState
import org.junit.Assert.assertEquals
import org.junit.Test

class SettingsConnectionStatusTest {
    @Test
    fun pairedSocketShowsPairedInsteadOfReconnecting() {
        assertEquals(
            "已配对：OpenClaw",
            settingsConnectionStatusText(
                connectionState = ConnectionState.PAIRED,
                pairingState = PairingState.PAIRED,
                pairedBackendLabel = "OpenClaw",
            ),
        )
    }
}
