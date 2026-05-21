package com.openclaw.remote.headset

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.UUID

class A9UltraSppProtocolTest {
    @Test
    fun sppUuidsPreferVendorCustomThenDefaultSerialPort() {
        assertEquals(
            UUID.fromString("B6632277-0642-458B-A7A0-23FB1DC92C93"),
            A9UltraSppProfile.CUSTOM_SPP_UUID,
        )
        assertEquals(
            UUID.fromString("00001101-0000-1000-8000-00805F9B34FB"),
            A9UltraSppProfile.DEFAULT_SPP_UUID,
        )
        assertEquals(
            listOf(A9UltraSppProfile.CUSTOM_SPP_UUID, A9UltraSppProfile.DEFAULT_SPP_UUID),
            A9UltraSppProfile.connectionUuids,
        )
    }

    @Test
    fun deviceInfoRequestAsksForPidCapabilitiesAndVoiceStatus() {
        val codec = ABMateSppFrameCodec()
        val bytes = codec.encodeRequest(
            command = ABMateSppCommand.DEVICE_INFO,
            payload = A9UltraSppPolicy.deviceInfoRequestPayload,
        )
        val frame = ABMateSppPacketParser().push(bytes).single()

        assertEquals(ABMateSppCommand.DEVICE_INFO.value, frame.command)
        assertEquals(ABMateSppFrameType.REQUEST, frame.type)
        assertEquals(
            listOf(0x24, 0xFE, 0xFF, 0x05, 0x1C, 0x0F),
            ABMateTlv.parse(frame.payload).map { it.type },
        )
    }

    @Test
    fun ledLightCommandUsesAbMateLedSwitchProtocol() {
        assertEquals(0x2E, ABMateSppCommand.LED_LIGHT.value)
        assertArrayEquals(byteArrayOf(0x00), A9UltraSppPolicy.ledLightPayload(enabled = false))
        assertArrayEquals(byteArrayOf(0x01), A9UltraSppPolicy.ledLightPayload(enabled = true))
    }

    @Test
    fun ledLightStatusParsesFromDeviceInfoTlv() {
        val enabledFrame = ABMateSppFrame(
            command = ABMateSppCommand.DEVICE_INFO.value,
            type = ABMateSppFrameType.RESPONSE,
            payload = ABMateTlv.encode(ABMateTlv.item(0x0F, 0x01)),
        )
        val disabledNotify = ABMateSppFrame(
            command = ABMateSppCommand.DEVICE_INFO_NOTIFY.value,
            type = ABMateSppFrameType.NOTIFY,
            payload = ABMateTlv.encode(ABMateTlv.item(0x0F, 0x00)),
        )

        assertEquals(true, A9UltraSppPolicy.parseLedLightEnabled(enabledFrame))
        assertEquals(false, A9UltraSppPolicy.parseLedLightEnabled(disabledNotify))
    }

    @Test
    fun pidAndVoiceCapabilityGateA9Ultra() {
        val accepted = ABMateTlv.encode(
            ABMateTlv.item(0x24, byteArrayOf(0x25, 0x00)),
            ABMateTlv.item(0xFE, byteArrayOf(0x10, 0x00)),
        )
        val wrongPid = ABMateTlv.encode(
            ABMateTlv.item(0x24, byteArrayOf(0x24, 0x00)),
            ABMateTlv.item(0xFE, byteArrayOf(0x10, 0x00)),
        )
        val missingCapability = ABMateTlv.encode(
            ABMateTlv.item(0x24, byteArrayOf(0x25, 0x00)),
            ABMateTlv.item(0xFE, byteArrayOf(0x0F, 0x00)),
        )

        assertTrue(A9UltraSppPolicy.acceptsDeviceInfo(accepted))
        assertFalse(A9UltraSppPolicy.acceptsDeviceInfo(wrongPid))
        assertFalse(A9UltraSppPolicy.acceptsDeviceInfo(missingCapability))
    }

    @Test
    fun sppCompatibilityAllowsKnownA9WhenPidIsMissingFromClassicSppResponse() {
        val classicSppResponse = ABMateTlv.encode(
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

        assertTrue(A9UltraSppPolicy.acceptsSppDeviceInfo(classicSppResponse, "A9 Ultra"))
        assertFalse(A9UltraSppPolicy.acceptsSppDeviceInfo(classicSppResponse, "iLucy"))
    }

    @Test
    fun wakeNotifyParsesFromAbMateFrame() {
        val bytes = byteArrayOf(0x03, 0x28, 0x03, 0x00, 0x03, 0x26, 0x01, 0x01)
        val frame = ABMateSppPacketParser().push(bytes).single()
        val event = A9UltraSppPolicy.parseWakeEvent(frame)

        assertEquals(A9UltraWakeEvent.Wake(side = null), event)
    }

    @Test
    fun recordingNotifyParsesOpusMetadataAndPayload() {
        val opus = ByteArray(120) { index -> index.toByte() }
        val payload = byteArrayOf(0x00, 0x00, 0x03, 0x28) + opus
        val frame = ABMateSppFrame(
            command = ABMateSppCommand.RECORDING_DATA.value,
            type = ABMateSppFrameType.NOTIFY,
            payload = payload,
        )
        val packet = A9UltraOpusPacket.parse(frame)

        assertEquals(HeadsetSide.RIGHT, packet?.side)
        assertEquals(3, packet?.frameCount)
        assertEquals(40, packet?.frameSize)
        assertArrayEquals(opus, packet?.opusData)
    }

    @Test
    fun commandSuccessAckUsesOriginalTlvType() {
        assertArrayEquals(
            byteArrayOf(0x01, 0x01, 0x00),
            A9UltraSppPolicy.successAckPayload(0x01),
        )
    }

    @Test
    fun wavEncoderWrapsPcmAs16kMonoPcmS16le() {
        val wav = HeadsetWavEncoder.encodePcm16Mono16k(byteArrayOf(0x01, 0x00, 0x02, 0x00))

        assertEquals(48, wav.size)
        assertEquals("RIFF", wav.copyOfRange(0, 4).toString(Charsets.US_ASCII))
        assertEquals("WAVE", wav.copyOfRange(8, 12).toString(Charsets.US_ASCII))
        assertEquals("fmt ", wav.copyOfRange(12, 16).toString(Charsets.US_ASCII))
        assertEquals("data", wav.copyOfRange(36, 40).toString(Charsets.US_ASCII))
        assertEquals(16_000, wav.readUInt32LE(24))
        assertEquals(1, wav.readUInt16LE(22))
        assertEquals(16, wav.readUInt16LE(34))
        assertEquals(4, wav.readUInt32LE(40))
    }

    @Test
    fun pcmVoiceActivityDetectsSpeechLikePcm() {
        val silence = pcm16Le(samples = 1_600, value = 0)
        val speech = pcm16Le(samples = 1_600, value = 1_000)

        assertFalse(A9UltraPcmVoiceActivity.analyzePcm16Le(silence).isVoice)
        assertTrue(A9UltraPcmVoiceActivity.analyzePcm16Le(speech).isVoice)
        assertEquals(100, A9UltraPcmVoiceActivity.analyzePcm16Le(speech).durationMs)
    }

    @Test
    fun postStopRecoveryIgnoresTailThenStartsOnLaterVoice() {
        val gate = A9UltraOpusRecoveryGate(postStopDrainMs = 900)
        gate.enterPostStopDrain(nowMs = 1_000)

        assertEquals(A9UltraStandbyMode.CONTINUOUS, gate.standbyMode)
        assertEquals(
            A9UltraOpusRecoveryDecision.IgnoreDrain,
            gate.onSuppressedOpus(nowMs = 1_500, level = voiceLevel()),
        )
        assertEquals(
            A9UltraOpusRecoveryDecision.IgnoreSilence,
            gate.onSuppressedOpus(nowMs = 2_000, level = silenceLevel()),
        )
        assertEquals(
            A9UltraOpusRecoveryDecision.StartRecovery,
            gate.onSuppressedOpus(nowMs = 2_100, level = voiceLevel()),
        )
        assertEquals(A9UltraStandbyMode.CONTINUOUS, gate.standbyMode)
        assertFalse(gate.isSuppressing)
    }

    @Test
    fun awaitingWakeDoesNotRecoverFromOpusVoice() {
        val gate = A9UltraOpusRecoveryGate(postStopDrainMs = 900)
        gate.enterAwaitingWake(nowMs = 1_000)

        assertEquals(A9UltraStandbyMode.WAKE_WORD_REQUIRED, gate.standbyMode)
        assertEquals(
            A9UltraOpusRecoveryDecision.IgnoreAwaitingWake,
            gate.onSuppressedOpus(nowMs = 5_000, level = voiceLevel()),
        )
        assertEquals(A9UltraStandbyMode.WAKE_WORD_REQUIRED, gate.standbyMode)
        assertTrue(gate.isSuppressing)
    }

    @Test
    fun openGateReportsContinuousStandbyMode() {
        val gate = A9UltraOpusRecoveryGate(postStopDrainMs = 900)

        assertEquals(A9UltraStandbyMode.CONTINUOUS, gate.standbyMode)
        assertEquals(
            A9UltraOpusRecoveryDecision.StartRecovery,
            gate.onSuppressedOpus(nowMs = 5_000, level = voiceLevel()),
        )
    }

    @Test
    fun postStopRecoveryKeepsSilenceSuppressedAfterDrain() {
        val gate = A9UltraOpusRecoveryGate(postStopDrainMs = 900)
        gate.enterPostStopDrain(nowMs = 1_000)

        repeat(5) { index ->
            assertEquals(
                A9UltraOpusRecoveryDecision.IgnoreSilence,
                gate.onSuppressedOpus(nowMs = 2_000 + index * 100L, level = silenceLevel()),
            )
        }
        assertTrue(gate.isSuppressing)
    }
}

private fun ByteArray.readUInt16LE(offset: Int): Int =
    (this[offset].toInt() and 0xFF) or ((this[offset + 1].toInt() and 0xFF) shl 8)

private fun ByteArray.readUInt32LE(offset: Int): Int =
    (this[offset].toInt() and 0xFF) or
        ((this[offset + 1].toInt() and 0xFF) shl 8) or
        ((this[offset + 2].toInt() and 0xFF) shl 16) or
        ((this[offset + 3].toInt() and 0xFF) shl 24)

private fun pcm16Le(samples: Int, value: Int): ByteArray =
    ByteArray(samples * 2).also { bytes ->
        repeat(samples) { index ->
            bytes[index * 2] = (value.toInt() and 0xFF).toByte()
            bytes[index * 2 + 1] = ((value.toInt() ushr 8) and 0xFF).toByte()
        }
    }

private fun silenceLevel(): A9UltraPcmLevel = A9UltraPcmLevel(averageAbs = 0, peakAbs = 0, durationMs = 100)

private fun voiceLevel(): A9UltraPcmLevel = A9UltraPcmLevel(averageAbs = 1_000, peakAbs = 2_000, durationMs = 100)
