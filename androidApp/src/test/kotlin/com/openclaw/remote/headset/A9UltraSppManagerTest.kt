package com.openclaw.remote.headset

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

@RunWith(RobolectricTestRunner::class)
class A9UltraSppManagerTest {
    @Test
    fun toggleStandbyModeSwitchesBetweenWakeWordAndContinuousConversation() {
        val manager = A9UltraSppManager(
            context = ApplicationProvider.getApplicationContext<Context>(),
            onAudioReady = {},
        )

        assertEquals(A9UltraStandbyMode.WAKE_WORD_REQUIRED, manager.standbyMode.value)

        manager.toggleStandbyMode()
        assertEquals(A9UltraStandbyMode.CONTINUOUS, manager.standbyMode.value)

        manager.toggleStandbyMode()
        assertEquals(A9UltraStandbyMode.WAKE_WORD_REQUIRED, manager.standbyMode.value)
    }

    @Test
    fun toggleFromContinuousToWakeWordRearmsHeadsetWakeRecognition() {
        val sentCommands = mutableListOf<RecordedCommand>()
        val manager = A9UltraSppManager(
            context = ApplicationProvider.getApplicationContext<Context>(),
            onAudioReady = {},
            observeCommand = { command, payload ->
                sentCommands += RecordedCommand(command, payload)
            },
        )

        manager.setStandbyMode(A9UltraStandbyMode.CONTINUOUS)
        sentCommands.clear()

        manager.toggleStandbyMode()

        assertEquals(A9UltraStandbyMode.WAKE_WORD_REQUIRED, manager.standbyMode.value)
        assertEquals(
            listOf(ABMateSppCommand.OPUS_RECORDING, ABMateSppCommand.VOICE_RECOGNITION),
            sentCommands.map { it.command },
        )
        assertTrue(sentCommands[0].payload.contentEquals(A9UltraSppPolicy.opusRecordingPayload(false)))
        assertTrue(sentCommands[1].payload.contentEquals(A9UltraSppPolicy.voiceRecognitionEnablePayload))
    }

    @Test
    fun deviceVerificationDoesNotRearmWakeRecognitionByDefault() {
        val sentCommands = mutableListOf<RecordedCommand>()
        val manager = A9UltraSppManager(
            context = ApplicationProvider.getApplicationContext<Context>(),
            onAudioReady = {},
            observeCommand = { command, payload ->
                sentCommands += RecordedCommand(command, payload)
            },
        )

        manager.handleFrameForTest(
            ABMateSppFrame(
                command = ABMateSppCommand.DEVICE_INFO.value,
                type = ABMateSppFrameType.RESPONSE,
                payload = classicSppDeviceInfoPayload(),
            )
        )

        assertEquals(A9UltraStandbyMode.WAKE_WORD_REQUIRED, manager.standbyMode.value)
        assertTrue(sentCommands.isEmpty())
    }
}

private data class RecordedCommand(
    val command: ABMateSppCommand,
    val payload: ByteArray,
)

private fun A9UltraSppManager.handleFrameForTest(frame: ABMateSppFrame) {
    val method = A9UltraSppManager::class.java.getDeclaredMethod("handleFrame", ABMateSppFrame::class.java)
    method.isAccessible = true
    method.invoke(this, frame)
}

private fun classicSppDeviceInfoPayload(): ByteArray = ABMateTlv.encode(
    ABMateTlv.item(0xFE, byteArrayOf(0x01, 0x00)),
    ABMateTlv.item(0xFF, byteArrayOf(0xFF.toByte())),
    ABMateTlv.item(
        0x05,
        byteArrayOf(
            0x01, 0x01, 0x07,
            0x02, 0x01, 0x07,
            0x03, 0x01, 0x03,
            0x04, 0x01, 0x04,
        ),
    ),
)
