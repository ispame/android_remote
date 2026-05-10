import Foundation

enum HeadsetAudioError: Error {
    case decoderUnavailable(String)
    case decodeFailed(String)
}

final class HeadsetOpusDecoder {
    private var bridge: OpusDecoderBridge

    init(sampleRate: Int32 = 16_000, channels: Int32 = 1) throws {
        bridge = OpusDecoderBridge(sampleRate: sampleRate, channels: channels)
        if let error = bridge.lastError {
            throw HeadsetAudioError.decoderUnavailable(error)
        }
    }

    func reset() {
        bridge.reset()
    }

    func decodePackets(_ opusData: Data, frameCount: Int, frameSize: Int) throws -> Data {
        var packets: [Data] = []
        if frameSize > 0, opusData.count >= frameSize {
            var offset = 0
            for _ in 0..<max(1, frameCount) {
                guard offset < opusData.count else { break }
                let end = min(opusData.count, offset + frameSize)
                packets.append(opusData.subdata(in: offset..<end))
                offset = end
            }
            if offset < opusData.count, packets.isEmpty {
                packets.append(opusData)
            }
        } else {
            packets.append(opusData)
        }

        var pcm = Data()
        for packet in packets where !packet.isEmpty {
            guard let decoded = bridge.decodePacket(packet) else {
                throw HeadsetAudioError.decodeFailed(bridge.lastError ?? "Opus decode failed")
            }
            pcm.append(decoded)
        }
        return pcm
    }
}

enum WAVEncoder {
    static func encodePCM16Mono16k(_ pcm: Data) -> Data {
        let sampleRate: UInt32 = 16_000
        let channels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let byteRate = sampleRate * UInt32(channels) * UInt32(bitsPerSample / 8)
        let blockAlign = channels * (bitsPerSample / 8)

        var data = Data()
        data.appendASCII("RIFF")
        data.appendUInt32LE(UInt32(36 + pcm.count))
        data.appendASCII("WAVE")
        data.appendASCII("fmt ")
        data.appendUInt32LE(16)
        data.appendUInt16LE(1)
        data.appendUInt16LE(channels)
        data.appendUInt32LE(sampleRate)
        data.appendUInt32LE(byteRate)
        data.appendUInt16LE(blockAlign)
        data.appendUInt16LE(bitsPerSample)
        data.appendASCII("data")
        data.appendUInt32LE(UInt32(pcm.count))
        data.append(pcm)
        return data
    }
}

private extension Data {
    mutating func appendASCII(_ value: String) {
        append(value.data(using: .ascii) ?? Data())
    }

    mutating func appendUInt16LE(_ value: UInt16) {
        append(UInt8(value & 0x00FF))
        append(UInt8((value >> 8) & 0x00FF))
    }

    mutating func appendUInt32LE(_ value: UInt32) {
        append(UInt8(value & 0x000000FF))
        append(UInt8((value >> 8) & 0x000000FF))
        append(UInt8((value >> 16) & 0x000000FF))
        append(UInt8((value >> 24) & 0x000000FF))
    }
}
