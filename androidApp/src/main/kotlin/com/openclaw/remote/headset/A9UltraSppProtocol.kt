package com.openclaw.remote.headset

import java.io.ByteArrayOutputStream
import java.util.UUID

object A9UltraSppProfile {
    val DEFAULT_SPP_UUID: UUID = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")
    val CUSTOM_SPP_UUID: UUID = UUID.fromString("B6632277-0642-458B-A7A0-23FB1DC92C93")
    val connectionUuids: List<UUID> = listOf(CUSTOM_SPP_UUID, DEFAULT_SPP_UUID)
}

enum class HeadsetSide {
    LEFT,
    RIGHT;

    companion object {
        fun fromAudioSource(value: Int): HeadsetSide = if (value == 1) LEFT else RIGHT
    }
}

sealed class A9UltraWakeEvent {
    data class Wake(val side: HeadsetSide?) : A9UltraWakeEvent()
    data object Sleep : A9UltraWakeEvent()
}

enum class ABMateSppCommand(val value: Int) {
    KEY_SETTINGS(0x22),
    DEVICE_INFO(0x27),
    DEVICE_INFO_NOTIFY(0x28),
    VOICE_RECOGNITION(0x34),
    OPUS_RECORDING(0x3B),
    RECORDING_DATA(0x3C),
}

enum class ABMateSppFrameType(val value: Int) {
    REQUEST(1),
    RESPONSE(2),
    NOTIFY(3);

    companion object {
        fun fromValue(value: Int): ABMateSppFrameType? = entries.firstOrNull { it.value == value }
    }
}

data class ABMateSppFrame(
    val command: Int,
    val type: ABMateSppFrameType,
    val payload: ByteArray,
) {
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is ABMateSppFrame) return false
        return command == other.command && type == other.type && payload.contentEquals(other.payload)
    }

    override fun hashCode(): Int {
        var result = command
        result = 31 * result + type.hashCode()
        result = 31 * result + payload.contentHashCode()
        return result
    }
}

class ABMateSppFrameCodec {
    private var seq = 0

    fun encodeRequest(command: ABMateSppCommand, payload: ByteArray = ByteArray(0)): ByteArray =
        encode(command.value, ABMateSppFrameType.REQUEST, payload)

    fun encode(command: Int, type: ABMateSppFrameType, payload: ByteArray = ByteArray(0)): ByteArray {
        require(payload.size <= 0xFF) { "AB Mate single-frame payload must be <= 255 bytes" }
        val currentSeq = seq and 0x0F
        seq = (seq + 1) and 0x0F
        return ByteArray(5 + payload.size).also { frame ->
            frame[0] = currentSeq.toByte()
            frame[1] = command.toByte()
            frame[2] = type.value.toByte()
            frame[3] = 0x00
            frame[4] = payload.size.toByte()
            payload.copyInto(frame, destinationOffset = 5)
        }
    }
}

class ABMateSppPacketParser(
    private val maxPayloadLength: Int = 255,
) {
    private var pending = ByteArray(0)

    fun push(data: ByteArray): List<ABMateSppFrame> {
        if (data.isEmpty()) return emptyList()
        pending += data
        val frames = mutableListOf<ABMateSppFrame>()
        while (pending.size >= HEADER_SIZE) {
            val command = pending[1].asUInt8()
            val type = ABMateSppFrameType.fromValue(pending[2].asUInt8())
            val length = pending[4].asUInt8()
            if (type == null || length > maxPayloadLength) {
                pending = pending.copyOfRange(1, pending.size)
                continue
            }
            val frameLength = HEADER_SIZE + length
            if (pending.size < frameLength) break
            val payload = pending.copyOfRange(HEADER_SIZE, frameLength)
            frames += ABMateSppFrame(command = command, type = type, payload = payload)
            pending = pending.copyOfRange(frameLength, pending.size)
        }
        return frames
    }

    companion object {
        private const val HEADER_SIZE = 5
    }
}

data class ABMateTlv(
    val type: Int,
    val value: ByteArray,
) {
    companion object {
        fun empty(type: Int): ABMateTlv = ABMateTlv(type, ByteArray(0))

        fun item(type: Int, value: ByteArray): ABMateTlv = ABMateTlv(type, value)

        fun item(type: Int, byte: Int): ABMateTlv = ABMateTlv(type, byteArrayOf(byte.toByte()))

        fun encode(vararg items: ABMateTlv): ByteArray {
            val out = ByteArrayOutputStream()
            items.forEach { item ->
                require(item.type in 0..0xFF) { "TLV type must fit in one byte" }
                require(item.value.size <= 0xFF) { "TLV value must fit in one byte length" }
                out.write(item.type)
                out.write(item.value.size)
                out.write(item.value)
            }
            return out.toByteArray()
        }

        fun parse(payload: ByteArray): List<ABMateTlv> {
            val result = mutableListOf<ABMateTlv>()
            var offset = 0
            while (offset + 1 < payload.size) {
                val type = payload[offset].asUInt8()
                val length = payload[offset + 1].asUInt8()
                val valueStart = offset + 2
                val valueEnd = valueStart + length
                if (valueEnd > payload.size) break
                result += ABMateTlv(type, payload.copyOfRange(valueStart, valueEnd))
                offset = valueEnd
            }
            return result
        }
    }
}

object A9UltraSppPolicy {
    const val TARGET_PRODUCT_ID: Int = 0x0025

    val deviceInfoRequestPayload: ByteArray = ABMateTlv.encode(
        ABMateTlv.empty(0x24),
        ABMateTlv.empty(0xFE),
        ABMateTlv.empty(0xFF),
        ABMateTlv.empty(0x05),
        ABMateTlv.empty(0x1C),
    )

    val voiceRecognitionEnablePayload: ByteArray = byteArrayOf(0x01)

    fun opusRecordingPayload(enabled: Boolean): ByteArray =
        ABMateTlv.encode(ABMateTlv.item(0x01, if (enabled) 0x01 else 0x00))

    fun successAckPayload(type: Int): ByteArray =
        ABMateTlv.encode(ABMateTlv.item(type, 0x00))

    fun acceptsDeviceInfo(payload: ByteArray): Boolean {
        val tlvs = ABMateTlv.parse(payload)
        val productId = tlvs.firstOrNull { it.type == 0x24 }?.value?.littleEndianUInt16()
        val capabilities = tlvs.firstOrNull { it.type == 0xFE }?.value?.littleEndianUInt16()
        return productId == TARGET_PRODUCT_ID && capabilities != null && (capabilities and 0x0010) != 0
    }

    fun parseWakeEvent(frame: ABMateSppFrame): A9UltraWakeEvent? {
        if (frame.command != ABMateSppCommand.DEVICE_INFO_NOTIFY.value) return null
        val wakePayload = ABMateTlv.parse(frame.payload).firstOrNull { it.type == 0x26 }?.value ?: return null
        val state = wakePayload.firstOrNull()?.asUInt8() ?: return null
        if (state == 0x01) {
            val side = wakePayload.getOrNull(1)?.asUInt8()?.let(HeadsetSide::fromAudioSource)
            return A9UltraWakeEvent.Wake(side)
        }
        return A9UltraWakeEvent.Sleep
    }

    fun parseOpusRecordingEnabled(frame: ABMateSppFrame): Boolean? {
        if (frame.command != ABMateSppCommand.OPUS_RECORDING.value) return null
        return ABMateTlv.parse(frame.payload)
            .firstOrNull { it.type == 0x01 }
            ?.value
            ?.firstOrNull()
            ?.asUInt8()
            ?.let { it == 0x01 }
    }
}

data class A9UltraOpusPacket(
    val side: HeadsetSide,
    val frameCount: Int,
    val frameSize: Int,
    val opusData: ByteArray,
) {
    companion object {
        fun parse(frame: ABMateSppFrame): A9UltraOpusPacket? {
            if (frame.command != ABMateSppCommand.RECORDING_DATA.value) return null
            val payload = frame.payload
            if (payload.size < 4 || payload[0].asUInt8() != 0x00) return null
            return A9UltraOpusPacket(
                side = HeadsetSide.fromAudioSource(payload[1].asUInt8()),
                frameCount = maxOf(1, payload[2].asUInt8()),
                frameSize = maxOf(0, payload[3].asUInt8()),
                opusData = payload.copyOfRange(4, payload.size),
            )
        }
    }
}

object HeadsetWavEncoder {
    fun encodePcm16Mono16k(pcm: ByteArray): ByteArray {
        val out = ByteArrayOutputStream()
        val dataSize = pcm.size
        val riffSize = 36 + dataSize
        out.writeAscii("RIFF")
        out.writeUInt32LE(riffSize)
        out.writeAscii("WAVE")
        out.writeAscii("fmt ")
        out.writeUInt32LE(16)
        out.writeUInt16LE(1)
        out.writeUInt16LE(1)
        out.writeUInt32LE(16_000)
        out.writeUInt32LE(16_000 * 2)
        out.writeUInt16LE(2)
        out.writeUInt16LE(16)
        out.writeAscii("data")
        out.writeUInt32LE(dataSize)
        out.write(pcm)
        return out.toByteArray()
    }
}

private fun Byte.asUInt8(): Int = toInt() and 0xFF

private fun ByteArray.littleEndianUInt16(offset: Int = 0): Int? {
    if (offset + 1 >= size) return null
    return (this[offset].asUInt8()) or (this[offset + 1].asUInt8() shl 8)
}

private fun ByteArrayOutputStream.writeAscii(value: String) {
    write(value.toByteArray(Charsets.US_ASCII))
}

private fun ByteArrayOutputStream.writeUInt16LE(value: Int) {
    write(value and 0xFF)
    write((value ushr 8) and 0xFF)
}

private fun ByteArrayOutputStream.writeUInt32LE(value: Int) {
    write(value and 0xFF)
    write((value ushr 8) and 0xFF)
    write((value ushr 16) and 0xFF)
    write((value ushr 24) and 0xFF)
}
