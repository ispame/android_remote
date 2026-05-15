import Foundation

enum HeadsetSide: String, CaseIterable {
    case left
    case right

    var displayName: String {
        switch self {
        case .left: return "左耳"
        case .right: return "右耳"
        }
    }

    var agentIndex: Int {
        switch self {
        case .left: return 0
        case .right: return 1
        }
    }

    static func fromAudioSource(_ source: UInt8) -> HeadsetSide {
        source == 1 ? .left : .right
    }
}

enum HeadsetWakeSleepEvent: Equatable {
    case wake(side: HeadsetSide?)
    case sleep

    init?(value: Data) {
        guard let state = value.first else { return nil }
        if state == 0x01 {
            let side = value.count >= 2 ? HeadsetSide.fromAudioSource(value[1]) : nil
            self = .wake(side: side)
        } else {
            self = .sleep
        }
    }
}

struct HeadsetRecordingPacket: Equatable {
    let side: HeadsetSide
    let frameCount: Int
    let frameSize: Int
    let opusData: Data

    var diagnosticLabel: String {
        "Opus \(side.displayName) \(frameCount)x\(frameSize)"
    }

    static func parse(_ payload: Data) -> HeadsetRecordingPacket? {
        guard payload.count >= 4, payload[0] == 0 else { return nil }
        return HeadsetRecordingPacket(
            side: HeadsetSide.fromAudioSource(payload[1]),
            frameCount: max(1, Int(payload[2])),
            frameSize: max(0, Int(payload[3])),
            opusData: payload.subdata(in: 4..<payload.count)
        )
    }
}

enum HeadsetPrivateSessionPolicy {
    static func shouldStartSession(on event: HeadsetWakeSleepEvent, activeSide: HeadsetSide?) -> Bool {
        guard activeSide == nil else { return false }
        if case .wake = event { return true }
        return false
    }

    static func shouldFinishSession(on event: HeadsetWakeSleepEvent, activeSide: HeadsetSide?) -> Bool {
        guard activeSide != nil else { return false }
        switch event {
        case .wake, .sleep:
            return true
        }
    }

    static func side(for event: HeadsetWakeSleepEvent, fallback: HeadsetSide = .right) -> HeadsetSide {
        if case .wake(let side) = event {
            return side ?? fallback
        }
        return fallback
    }
}

enum HeadsetBLESignalKind: Equatable {
    case wake
    case sleep
    case voiceRecognitionAck
    case opusRecordingAck
    case keySettingsAck
    case keyConfiguration
    case raw(String)

    var label: String {
        switch self {
        case .wake: return "wake"
        case .sleep: return "sleep"
        case .voiceRecognitionAck: return "voice ok"
        case .opusRecordingAck: return "opus ok"
        case .keySettingsAck: return "key ack"
        case .keyConfiguration: return "key cfg"
        case .raw(let label): return label
        }
    }
}

struct HeadsetInputDiagnostics: Equatable {
    private(set) var bleSignalCount = 0
    private var lastBLESignal: HeadsetBLESignalKind?
    private var lastBLEPayload = Data()

    mutating func recordBLE(_ signal: HeadsetBLESignalKind, payload: Data) {
        bleSignalCount += 1
        lastBLESignal = signal
        lastBLEPayload = payload
    }

    mutating func reset() {
        bleSignalCount = 0
        lastBLESignal = nil
        lastBLEPayload.removeAll(keepingCapacity: true)
    }

    var label: String? {
        guard let lastBLESignal else { return nil }
        let payload = lastBLEPayload.headsetHexPrefix(8)
        return "BLE \(lastBLESignal.label) #\(bleSignalCount)\(payload.isEmpty ? "" : " \(payload)")"
    }
}

private extension Data {
    func headsetHexPrefix(_ maxBytes: Int) -> String {
        prefix(maxBytes)
            .map { String(format: "%02x", $0) }
            .joined(separator: " ")
    }
}

enum HeadsetAudioRoutingPolicy {
    static func shouldAcceptAudioChunk(activeSide: HeadsetSide?) -> Bool {
        activeSide != nil
    }

    static func sessionSide(activeSide: HeadsetSide, reportedAudioSide _: HeadsetSide) -> HeadsetSide {
        activeSide
    }
}

enum HeadsetVoiceActivityDecision: Equatable {
    case continueRecording
    case finishRecording
}

struct HeadsetVoiceActivityConfig {
    let sampleRate: Int
    let frameDuration: TimeInterval
    let warmupDuration: TimeInterval
    let minimumRecordingDuration: TimeInterval
    let minimumSpeechDuration: TimeInterval
    let silenceEndDuration: TimeInterval
    let noiseCalibrationDuration: TimeInterval
    let speechMarginDB: Double
    let absoluteSpeechDB: Double
    let speechStartFrameCount: Int

    static let demoDefault = HeadsetVoiceActivityConfig(
        sampleRate: 16_000,
        frameDuration: 0.02,
        warmupDuration: 0.60,
        minimumRecordingDuration: 1.20,
        minimumSpeechDuration: 0.25,
        silenceEndDuration: 0.90,
        noiseCalibrationDuration: 0.40,
        speechMarginDB: 10,
        absoluteSpeechDB: -42,
        speechStartFrameCount: 3
    )

    var frameByteCount: Int {
        max(1, Int(Double(sampleRate) * frameDuration)) * 2
    }
}

struct HeadsetVoiceActivityDetector {
    private let config: HeadsetVoiceActivityConfig
    private var pendingPCM = Data()
    private var noiseFloorDB: Double = -70
    private var hasNoiseFloor = false
    private var consecutiveSpeechFrames = 0
    private var hasFinished = false

    private(set) var elapsedDuration: TimeInterval = 0
    private(set) var speechDuration: TimeInterval = 0
    private(set) var silenceAfterSpeechDuration: TimeInterval = 0
    private(set) var speechSeen = false

    init(config: HeadsetVoiceActivityConfig = .demoDefault) {
        self.config = config
    }

    mutating func reset() {
        pendingPCM.removeAll(keepingCapacity: true)
        noiseFloorDB = -70
        hasNoiseFloor = false
        consecutiveSpeechFrames = 0
        hasFinished = false
        elapsedDuration = 0
        speechDuration = 0
        silenceAfterSpeechDuration = 0
        speechSeen = false
    }

    mutating func analyze(pcm16Mono data: Data) -> HeadsetVoiceActivityDecision {
        guard !hasFinished else { return .finishRecording }
        pendingPCM.append(data)

        while pendingPCM.count >= config.frameByteCount {
            let frame = pendingPCM.prefix(config.frameByteCount)
            consumeFrame(frame)
            pendingPCM.removeFirst(config.frameByteCount)

            if shouldFinish {
                hasFinished = true
                return .finishRecording
            }
        }

        return .continueRecording
    }

    func shouldSubmitForASR(pcmByteCount: Int, minimumPCMBytes: Int) -> Bool {
        pcmByteCount >= minimumPCMBytes
            && speechSeen
            && speechDuration >= config.minimumSpeechDuration
    }

    private mutating func consumeFrame(_ frame: Data.SubSequence) {
        elapsedDuration += config.frameDuration
        let db = Self.rmsDBFS(frame)

        if elapsedDuration <= config.noiseCalibrationDuration {
            if hasNoiseFloor {
                noiseFloorDB = min(noiseFloorDB, db)
            } else {
                noiseFloorDB = db
                hasNoiseFloor = true
            }
        }

        let speechThreshold = max(noiseFloorDB + config.speechMarginDB, config.absoluteSpeechDB)
        let isSpeech = db >= speechThreshold
        if isSpeech {
            consecutiveSpeechFrames += 1
        } else {
            consecutiveSpeechFrames = 0
        }

        if consecutiveSpeechFrames >= config.speechStartFrameCount {
            speechSeen = true
        }

        guard speechSeen else { return }
        if isSpeech {
            speechDuration += config.frameDuration
            silenceAfterSpeechDuration = 0
        } else {
            silenceAfterSpeechDuration += config.frameDuration
        }
    }

    private var shouldFinish: Bool {
        elapsedDuration >= config.warmupDuration
            && elapsedDuration >= config.minimumRecordingDuration
            && speechSeen
            && speechDuration >= config.minimumSpeechDuration
            && silenceAfterSpeechDuration >= config.silenceEndDuration
    }

    private static func rmsDBFS(_ frame: Data.SubSequence) -> Double {
        var offset = frame.startIndex
        var sumSquares = 0.0
        var samples = 0

        while offset < frame.endIndex {
            let next = frame.index(after: offset)
            guard next < frame.endIndex else { break }
            let raw = UInt16(frame[offset]) | (UInt16(frame[next]) << 8)
            let sample = Double(Int16(bitPattern: raw)) / 32_768.0
            sumSquares += sample * sample
            samples += 1
            offset = frame.index(after: next)
        }

        guard samples > 0, sumSquares > 0 else { return -120 }
        let rms = sqrt(sumSquares / Double(samples))
        return max(-120, 20 * log10(rms))
    }
}

enum ABMateCommand: UInt8 {
    case keySettings = 0x22
    case deviceInfo = 0x27
    case deviceInfoNotify = 0x28
    case voiceRecognition = 0x34
    case opusRecording = 0x3B
    case recordingData = 0x3C
}

enum ABMateCommandType: UInt8 {
    case request = 0x01
    case response = 0x02
    case notify = 0x03
}

struct ABMateFrame {
    let sequence: UInt8
    let command: UInt8
    let type: ABMateCommandType
    let payload: Data
}

struct ABMateTLV {
    let type: UInt8
    let value: Data
}

final class ABMateFrameCodec {
    private var nextSequence: UInt8 = 0
    private var pendingFrames: [String: PendingFrameSet] = [:]
    var maxPacketLength = 120

    func makeRequest(command: ABMateCommand, payload: Data = Data()) -> [Data] {
        makeFrames(command: command.rawValue, type: .request, payload: payload)
    }

    func makeFrames(command: UInt8, type: ABMateCommandType, payload: Data = Data()) -> [Data] {
        let sequence = nextSequence & 0x0F
        nextSequence = (nextSequence + 1) & 0x0F

        let payloadLimit = max(1, maxPacketLength - 5)
        let frameCount = max(1, Int(ceil(Double(payload.count) / Double(payloadLimit))))
        return (0..<frameCount).map { index in
            let start = index * payloadLimit
            let end = min(payload.count, start + payloadLimit)
            let chunk = payload.isEmpty ? Data() : payload.subdata(in: start..<end)
            var data = Data()
            data.append(sequence)
            data.append(command)
            data.append(type.rawValue)
            data.append(UInt8(((frameCount - 1) & 0x0F) << 4 | (index & 0x0F)))
            data.append(UInt8(chunk.count))
            data.append(chunk)
            return data
        }
    }

    func parse(_ data: Data) -> [ABMateFrame] {
        guard data.count >= 5 else { return [] }
        let sequence = data[0] & 0x0F
        let command = data[1]
        guard let type = ABMateCommandType(rawValue: data[2]) else { return [] }
        let frameInfo = data[3]
        let frameIndex = Int(frameInfo & 0x0F)
        let totalFrames = Int(frameInfo >> 4) + 1
        let length = min(Int(data[4]), data.count - 5)
        let payload = data.subdata(in: 5..<(5 + length))

        guard totalFrames > 1 else {
            return [ABMateFrame(sequence: sequence, command: command, type: type, payload: payload)]
        }

        let key = "\(sequence)-\(command)-\(type.rawValue)"
        var pending = pendingFrames[key] ?? PendingFrameSet(total: totalFrames)
        pending.chunks[frameIndex] = payload
        pendingFrames[key] = pending

        guard pending.isComplete else { return [] }
        pendingFrames.removeValue(forKey: key)
        let fullPayload = (0..<pending.total).reduce(into: Data()) { result, index in
            result.append(pending.chunks[index] ?? Data())
        }
        return [ABMateFrame(sequence: sequence, command: command, type: type, payload: fullPayload)]
    }

    private struct PendingFrameSet {
        let total: Int
        var chunks: [Int: Data] = [:]

        var isComplete: Bool {
            chunks.count == total && (0..<total).allSatisfy { chunks[$0] != nil }
        }
    }
}

enum ABMateTLVCodec {
    static func encode(_ items: [ABMateTLV]) -> Data {
        items.reduce(into: Data()) { result, item in
            result.append(item.type)
            result.append(UInt8(min(item.value.count, 255)))
            result.append(contentsOf: item.value.prefix(255))
        }
    }

    static func item(_ type: UInt8, byte: UInt8) -> ABMateTLV {
        ABMateTLV(type: type, value: Data([byte]))
    }

    static func empty(_ type: UInt8) -> ABMateTLV {
        ABMateTLV(type: type, value: Data())
    }

    static func parse(_ payload: Data) -> [ABMateTLV] {
        var offset = 0
        var result: [ABMateTLV] = []
        while offset + 2 <= payload.count {
            let type = payload[offset]
            let length = Int(payload[offset + 1])
            offset += 2
            guard offset + length <= payload.count else { break }
            result.append(ABMateTLV(type: type, value: payload.subdata(in: offset..<(offset + length))))
            offset += length
        }
        return result
    }
}

enum A9UltraKeyConfiguration {
    static let previousTrackFunction: UInt8 = 0x03
    static let nextTrackFunction: UInt8 = 0x04
    static let playPauseFunction: UInt8 = 0x07
    static let disabledFunction: UInt8 = 0x00
    /// 语音助手功能码（Value=2）→ 触发 0x26 01 01 私有唤醒 Notify，不走 AVRCP
    static let voiceAssistantFunction: UInt8 = 0x02

    static var mediaRemoteCommandPayload: Data {
        ABMateTLVCodec.encode([
            ABMateTLVCodec.item(0x01, byte: playPauseFunction),
            ABMateTLVCodec.item(0x02, byte: playPauseFunction),
            ABMateTLVCodec.item(0x03, byte: playPauseFunction),
            ABMateTLVCodec.item(0x04, byte: playPauseFunction),
            ABMateTLVCodec.item(0x05, byte: playPauseFunction),
            ABMateTLVCodec.item(0x06, byte: playPauseFunction),
            ABMateTLVCodec.item(0x07, byte: playPauseFunction),
            ABMateTLVCodec.item(0x08, byte: playPauseFunction)
        ])
    }

    /// 左/右耳短按和双击 → 语音助手 → 触发 0x26 01 01 私有唤醒 Notify
    static var voiceAssistantCommandPayload: Data {
        ABMateTLVCodec.encode([
            ABMateTLVCodec.item(0x01, byte: voiceAssistantFunction),
            ABMateTLVCodec.item(0x02, byte: voiceAssistantFunction),
            ABMateTLVCodec.item(0x03, byte: voiceAssistantFunction),
            ABMateTLVCodec.item(0x04, byte: voiceAssistantFunction),
            ABMateTLVCodec.item(0x05, byte: playPauseFunction),
            ABMateTLVCodec.item(0x06, byte: playPauseFunction),
            ABMateTLVCodec.item(0x07, byte: playPauseFunction),
            ABMateTLVCodec.item(0x08, byte: playPauseFunction)
        ])
    }

    static func isSuccessfulAck(_ payload: Data) -> Bool {
        let tlvs = ABMateTLVCodec.parse(payload)
        guard !tlvs.isEmpty else { return false }
        return tlvs.allSatisfy { $0.value.first == 0x00 }
    }

    static func summary(_ payload: Data) -> String {
        let values = Dictionary(uniqueKeysWithValues: ABMateTLVCodec.parse(payload).compactMap { item -> (UInt8, UInt8)? in
            guard item.value.count == 1, let value = item.value.first else { return nil }
            return (item.type, value)
        })
        let importantTypes: [UInt8] = [0x01, 0x02, 0x03, 0x04, 0x07, 0x08]
        let parts = importantTypes.compactMap { type -> String? in
            guard let value = values[type] else { return nil }
            return String(format: "%02x=%02x", type, value)
        }
        return parts.isEmpty ? payload.headsetProtocolHexPrefix(16) : parts.joined(separator: " ")
    }
}

enum A9UltraPrivateProtocolPolicy {
    static let targetProductId: UInt16 = 0x0025
    static let requiredDeviceInfoTypes: [UInt8] = [0x24, 0xFE, 0xFF, 0x05, 0x1C]
    static let voiceRecognitionEnablePayload = Data([0x01])

    static var deviceInfoRequestPayload: Data {
        ABMateTLVCodec.encode(requiredDeviceInfoTypes.map { ABMateTLVCodec.empty($0) })
    }

    static func accepts(productId: UInt16?) -> Bool {
        productId == targetProductId
    }

    static func supportsVoiceRecognition(capabilities: UInt16?) -> Bool {
        guard let capabilities else { return false }
        return (capabilities & 0x0010) != 0
    }
}

extension Data {
    func littleEndianUInt16(at offset: Int) -> UInt16? {
        guard offset + 1 < count else { return nil }
        return UInt16(self[offset]) | (UInt16(self[offset + 1]) << 8)
    }

    func headsetProtocolHexPrefix(_ maxBytes: Int) -> String {
        prefix(maxBytes)
            .map { String(format: "%02x", $0) }
            .joined(separator: " ")
    }
}
