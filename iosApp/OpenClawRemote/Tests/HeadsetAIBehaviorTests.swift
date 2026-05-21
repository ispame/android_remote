import Foundation

@main
struct HeadsetAIBehaviorTests {
    static func main() throws {
        try testPrivateProtocolRequiresProductId()
        try testDeviceInfoRequestPayloadIncludesProductIdAndCapabilities()
        try testVoiceAssistantKeyConfigurationTargetsShortPress()
        try testWakeSleepTLVParsing()
        try testRecordingPayloadParsing()
        try testPrivateWakeStartsAndWakeOrSleepFinishes()
        try testIdleAudioDoesNotStartSession()
        try testInputDiagnosticsTracksPrivateBLESignals()
        try testInputDiagnosticsShowsRawBLESignals()
        try testInputDiagnosticsShowsVoiceAndOpusAcks()
        try testVoiceActivityWaitsForSpeechBeforeFinishing()
        try testVoiceActivityFinishesAfterSpeechAndTailSilence()
        try testVoiceActivityRequiresUsefulSpeechForASR()
        try testPromptToneChannelRendering()
        try testMessageSpeechTrimsAndSkipsBlankText()
        try testASRFailuresDropOptimisticMessage()
        print("HeadsetAIBehaviorTests passed")
    }

    private static func testPrivateProtocolRequiresProductId() throws {
        try expect(A9UltraPrivateProtocolPolicy.targetProductId == 0x0025, "A9Ultra PID should be the private-protocol gate")
        try expect(A9UltraPrivateProtocolPolicy.accepts(productId: 0x0025), "target PID should be accepted")
        try expect(!A9UltraPrivateProtocolPolicy.accepts(productId: 0x0024), "non-target PID must be rejected")
        try expect(!A9UltraPrivateProtocolPolicy.accepts(productId: nil), "missing PID must not be trusted")
        try expect(A9UltraPrivateProtocolPolicy.supportsVoiceRecognition(capabilities: 0x0010), "capability bit4 should enable private voice path")
        try expect(!A9UltraPrivateProtocolPolicy.supportsVoiceRecognition(capabilities: 0x000F), "missing capability bit4 should block private voice path")
    }

    private static func testDeviceInfoRequestPayloadIncludesProductIdAndCapabilities() throws {
        let types = ABMateTLVCodec.parse(A9UltraPrivateProtocolPolicy.deviceInfoRequestPayload).map(\.type)
        try expect(types == [0x24, 0xFE, 0xFF, 0x05, 0x1C], "startup device info request should ask for PID, capabilities, packet size, key readback, and voice state")
    }

    private static func testVoiceAssistantKeyConfigurationTargetsShortPress() throws {
        let values = Dictionary(uniqueKeysWithValues: ABMateTLVCodec.parse(A9UltraKeyConfiguration.voiceAssistantCommandPayload).compactMap { item -> (UInt8, UInt8)? in
            guard let value = item.value.first else { return nil }
            return (item.type, value)
        })

        try expect(values[0x01] == A9UltraKeyConfiguration.voiceAssistantFunction, "left short press should use private voice assistant function")
        try expect(values[0x02] == A9UltraKeyConfiguration.voiceAssistantFunction, "right short press should use private voice assistant function")
        try expect(values[0x03] == A9UltraKeyConfiguration.voiceAssistantFunction, "left double tap should use private voice assistant function")
        try expect(values[0x04] == A9UltraKeyConfiguration.voiceAssistantFunction, "right double tap should use private voice assistant function")
    }

    private static func testWakeSleepTLVParsing() throws {
        try expect(HeadsetWakeSleepEvent(value: Data([0x01])) == .wake(side: nil), "0x26 01 should be wake")
        try expect(HeadsetWakeSleepEvent(value: Data([0x01, 0x01])) == .wake(side: .left), "0x26 01 01 should be left wake")
        try expect(HeadsetWakeSleepEvent(value: Data([0x00])) == .sleep, "0x26 00 should be sleep")
    }

    private static func testRecordingPayloadParsing() throws {
        let opus = Data(repeating: 0xAB, count: 120)
        let payload = Data([0x00, 0x00, 0x03, 0x28]) + opus
        let packet = try expectNotNil(HeadsetRecordingPacket.parse(payload), "recording packet should parse")

        try expect(packet.side == .right, "audio source 0 should be right ear")
        try expect(packet.frameCount == 3, "frame count should parse from byte 2")
        try expect(packet.frameSize == 40, "frame size should parse from byte 3")
        try expect(packet.opusData.count == 120, "opus data should start after 4-byte recording payload header")
        try expect(packet.diagnosticLabel == "Opus 右耳 3x40", "diagnostic label should be compact")
    }

    private static func testPrivateWakeStartsAndWakeOrSleepFinishes() throws {
        try expect(HeadsetPrivateSessionPolicy.shouldStartSession(on: .wake(side: .right), activeSide: nil), "wake should start idle private session")
        try expect(!HeadsetPrivateSessionPolicy.shouldStartSession(on: .sleep, activeSide: nil), "sleep must not start idle private session")
        try expect(HeadsetPrivateSessionPolicy.shouldFinishSession(on: .wake(side: .left), activeSide: .right), "second wake should finish active private session")
        try expect(HeadsetPrivateSessionPolicy.shouldFinishSession(on: .sleep, activeSide: .right), "sleep should finish active private session")
    }

    private static func testIdleAudioDoesNotStartSession() throws {
        try expect(
            !HeadsetAudioRoutingPolicy.shouldAcceptAudioChunk(activeSide: nil),
            "idle residual audio must not start a headset session"
        )
        try expect(
            HeadsetAudioRoutingPolicy.shouldAcceptAudioChunk(activeSide: .left),
            "active headset session should accept audio chunks"
        )
    }

    private static func testInputDiagnosticsTracksPrivateBLESignals() throws {
        var diagnostics = HeadsetInputDiagnostics()

        diagnostics.recordBLE(.sleep, payload: Data([0x00]))
        try expect(diagnostics.label == "BLE sleep #1 00", "BLE sleep should be visible")

        diagnostics.recordBLE(.wake, payload: Data([0x01]))
        try expect(
            diagnostics.label == "BLE wake #2 01",
            "latest private BLE signal should replace the previous one"
        )
    }

    private static func testInputDiagnosticsShowsRawBLESignals() throws {
        var diagnostics = HeadsetInputDiagnostics()

        diagnostics.recordBLE(.raw("tlv 2a"), payload: Data([0x99, 0x01]))
        try expect(diagnostics.label == "BLE tlv 2a #1 99 01", "unknown BLE notify should be visible for terminal verification")
    }

    private static func testInputDiagnosticsShowsVoiceAndOpusAcks() throws {
        var diagnostics = HeadsetInputDiagnostics()

        diagnostics.recordBLE(.voiceRecognitionAck, payload: Data([0x00]))
        try expect(diagnostics.label == "BLE voice ok #1 00", "voice recognition ack should be visible")

        diagnostics.recordBLE(.opusRecordingAck, payload: Data([0x00]))
        try expect(diagnostics.label == "BLE opus ok #2 00", "opus recording ack should be visible")
    }

    private static func testVoiceActivityWaitsForSpeechBeforeFinishing() throws {
        var detector = HeadsetVoiceActivityDetector(config: .demoDefault)
        let silence = pcm16Mono(duration: 3.0, amplitude: 0)

        try expect(detector.analyze(pcm16Mono: silence) == .continueRecording, "silence without speech must not auto-finish")
        try expect(!detector.shouldSubmitForASR(pcmByteCount: silence.count, minimumPCMBytes: 16_000), "silence-only audio should not go to ASR")
    }

    private static func testVoiceActivityFinishesAfterSpeechAndTailSilence() throws {
        var detector = HeadsetVoiceActivityDetector(config: .demoDefault)

        try expect(detector.analyze(pcm16Mono: pcm16Mono(duration: 0.30, amplitude: 0)) == .continueRecording, "warmup silence should continue")
        try expect(detector.analyze(pcm16Mono: pcm16Mono(duration: 0.50, amplitude: 3_000)) == .continueRecording, "speech alone should not finish")
        try expect(detector.analyze(pcm16Mono: pcm16Mono(duration: 0.60, amplitude: 0)) == .continueRecording, "short tail silence should continue")
        try expect(detector.analyze(pcm16Mono: pcm16Mono(duration: 0.45, amplitude: 0)) == .finishRecording, "tail silence after speech should finish")
    }

    private static func testVoiceActivityRequiresUsefulSpeechForASR() throws {
        var detector = HeadsetVoiceActivityDetector(config: .demoDefault)

        _ = detector.analyze(pcm16Mono: pcm16Mono(duration: 0.30, amplitude: 0))
        _ = detector.analyze(pcm16Mono: pcm16Mono(duration: 0.08, amplitude: 3_000))
        _ = detector.analyze(pcm16Mono: pcm16Mono(duration: 1.20, amplitude: 0))

        try expect(!detector.shouldSubmitForASR(pcmByteCount: 50_000, minimumPCMBytes: 16_000), "tiny speech bursts should be dropped before ASR")
    }

    private static func testPromptToneChannelRendering() throws {
        let left = HeadsetPromptTonePlayer.renderToneSamples(
            channel: .left,
            sampleRate: 8_000,
            duration: 0.02,
            frequency: 500
        )
        let right = HeadsetPromptTonePlayer.renderToneSamples(
            channel: .right,
            sampleRate: 8_000,
            duration: 0.02,
            frequency: 500
        )
        let both = HeadsetPromptTonePlayer.renderToneSamples(
            channel: .both,
            sampleRate: 8_000,
            duration: 0.02,
            frequency: 500
        )

        try expect(left.contains { abs($0.left) > 0.001 }, "left tone should contain left channel signal")
        try expect(left.allSatisfy { abs($0.right) < 0.0001 }, "left tone should mute right channel")
        try expect(right.contains { abs($0.right) > 0.001 }, "right tone should contain right channel signal")
        try expect(right.allSatisfy { abs($0.left) < 0.0001 }, "right tone should mute left channel")
        try expect(both.contains { abs($0.left) > 0.001 && abs($0.right) > 0.001 }, "both tone should contain stereo signal")
    }

    private static func testMessageSpeechTrimsAndSkipsBlankText() throws {
        try expect(MessageSpeechController.normalizedText("  朗读这条消息 \n") == "朗读这条消息", "manual message speech should trim outer whitespace")
        try expect(MessageSpeechController.normalizedText(" \n\t ") == nil, "manual message speech should skip blank text")
    }

    private static func testASRFailuresDropOptimisticMessage() throws {
        try expect(shouldDropAsrFailureMessage("ASR_AUDIO_EMPTY"), "empty audio should remove the optimistic voice placeholder")
        try expect(shouldDropAsrFailureMessage("ASR_EMPTY_TRANSCRIPT"), "empty transcript should remove the optimistic voice placeholder")
        try expect(shouldDropAsrFailureMessage("ASR_PROVIDER_CLOSED"), "provider closures should remove the optimistic voice placeholder")
        try expect(shouldDropAsrFailureMessage(nil), "unknown ASR failure should remove the optimistic voice placeholder")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() {
            throw TestFailure(message)
        }
    }

    private static func expectNotNil<T>(_ value: T?, _ message: String) throws -> T {
        guard let value else {
            throw TestFailure(message)
        }
        return value
    }

    private static func pcm16Mono(duration: TimeInterval, amplitude: Int16, sampleRate: Int = 16_000) -> Data {
        let sampleCount = Int(duration * Double(sampleRate))
        return (0..<sampleCount).reduce(into: Data(capacity: sampleCount * 2)) { data, sampleIndex in
            let value: Int16 = amplitude == 0
                ? 0
                : (sampleIndex % 2 == 0 ? amplitude : -amplitude)
            data.append(UInt8(bitPattern: Int8(truncatingIfNeeded: value & 0x00FF)))
            data.append(UInt8(bitPattern: Int8(truncatingIfNeeded: (value >> 8) & 0x00FF)))
        }
    }
}

private struct TestFailure: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}
