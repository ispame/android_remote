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
            listOf(0x24, 0xFE, 0xFF, 0x05, 0x1C),
            ABMateTlv.parse(frame.payload).map { it.type },
        )
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
}

private fun ByteArray.readUInt16LE(offset: Int): Int =
    (this[offset].toInt() and 0xFF) or ((this[offset + 1].toInt() and 0xFF) shl 8)

private fun ByteArray.readUInt32LE(offset: Int): Int =
    (this[offset].toInt() and 0xFF) or
        ((this[offset + 1].toInt() and 0xFF) shl 8) or
        ((this[offset + 2].toInt() and 0xFF) shl 16) or
        ((this[offset + 3].toInt() and 0xFF) shl 24)
