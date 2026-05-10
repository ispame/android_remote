import AVFoundation
import Foundation

enum HeadsetPromptToneChannel {
    case left
    case right
    case both
}

struct HeadsetPromptToneSample {
    let left: Float
    let right: Float
}

final class HeadsetPromptTonePlayer {
    private var player: AVAudioPlayer?

    func play(channel: HeadsetPromptToneChannel, frequency: Double = 880, duration: TimeInterval = 0.12) {
        let data = Self.makeWAVData(channel: channel, sampleRate: 44_100, duration: duration, frequency: frequency)
        do {
            player = try AVAudioPlayer(data: data)
            player?.prepareToPlay()
            player?.play()
        } catch {}
    }

    static func renderToneSamples(
        channel: HeadsetPromptToneChannel,
        sampleRate: Double,
        duration: TimeInterval,
        frequency: Double
    ) -> [HeadsetPromptToneSample] {
        let frameCount = max(1, Int(sampleRate * duration))
        return (0..<frameCount).map { index in
            let progress = Double(index) / Double(max(frameCount - 1, 1))
            let envelope = sin(Double.pi * progress)
            let sample = Float(sin((2.0 * Double.pi * frequency * Double(index)) / sampleRate) * envelope * 0.35)
            switch channel {
            case .left:
                return HeadsetPromptToneSample(left: sample, right: 0)
            case .right:
                return HeadsetPromptToneSample(left: 0, right: sample)
            case .both:
                return HeadsetPromptToneSample(left: sample, right: sample)
            }
        }
    }

    private static func makeWAVData(
        channel: HeadsetPromptToneChannel,
        sampleRate: UInt32,
        duration: TimeInterval,
        frequency: Double
    ) -> Data {
        let samples = renderToneSamples(
            channel: channel,
            sampleRate: Double(sampleRate),
            duration: duration,
            frequency: frequency
        )
        let channels: UInt16 = 2
        let bitsPerSample: UInt16 = 16
        let byteRate = sampleRate * UInt32(channels) * UInt32(bitsPerSample / 8)
        let blockAlign = channels * (bitsPerSample / 8)
        var pcm = Data()
        for sample in samples {
            pcm.appendInt16LE(Self.pcmValue(sample.left))
            pcm.appendInt16LE(Self.pcmValue(sample.right))
        }

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

    private static func pcmValue(_ sample: Float) -> Int16 {
        let clamped = max(-1, min(1, sample))
        return Int16(clamped * Float(Int16.max))
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

    mutating func appendInt16LE(_ value: Int16) {
        let unsigned = UInt16(bitPattern: value)
        appendUInt16LE(unsigned)
    }
}
