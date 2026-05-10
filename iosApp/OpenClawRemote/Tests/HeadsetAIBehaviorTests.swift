import Foundation

@main
struct HeadsetAIBehaviorTests {
    static func main() throws {
        try testWakeWordUsesVoiceRecognitionWithoutKeyOverride()
        try testWakeSleepTLVParsing()
        try testRecordingPayloadParsing()
        try testWakeWordSessionPolicy()
        try testMediaCommandsOnlyDiagnoseDuringWakeWordMode()
        try testIdleAudioDoesNotStartSession()
        try testNonDirectionalMediaCommandsOnlyDiagnose()
        try testInputDiagnosticsKeepsMediaAndBLESignals()
        try testInputDiagnosticsShowsRawBLESignals()
        try testInputDiagnosticsShowsVoiceAndOpusAcks()
        try testLegacyRemoteControlEventsMapToCommands()
        try testMediaOwnershipStartsOnlyAfterHeadsetReady()
        try testNowPlayingMetadataAdvertisesPlayableQueue()
        try testVoiceActivityWaitsForSpeechBeforeFinishing()
        try testVoiceActivityFinishesAfterSpeechAndTailSilence()
        try testVoiceActivityRequiresUsefulSpeechForASR()
        try testPromptToneChannelRendering()
        print("HeadsetAIBehaviorTests passed")
    }

    private static func testWakeWordUsesVoiceRecognitionWithoutKeyOverride() throws {
        try expect(A9UltraStartupConfiguration.shouldWriteKeySettings == false, "wake-word mode must not override headset keys at startup")
        try expect(A9UltraStartupConfiguration.voiceRecognitionPayload == Data([0x01]), "startup should enable headset voice recognition")
    }

    private static func testWakeSleepTLVParsing() throws {
        try expect(HeadsetWakeSleepEvent(value: Data([0x01])) == .wake, "0x26 01 should be wake")
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

    private static func testWakeWordSessionPolicy() throws {
        try expect(HeadsetWakeWordSessionPolicy.agentSide == .left, "wake-word v1 should use Agent1")
        try expect(HeadsetWakeWordSessionPolicy.shouldStartSession(on: .wake, activeSide: nil), "wake should start idle session")
        try expect(HeadsetWakeWordSessionPolicy.shouldFinishSession(on: .sleep, activeSide: .left), "sleep should finish active session")
        try expect(!HeadsetWakeWordSessionPolicy.shouldStartSession(on: .sleep, activeSide: nil), "sleep must not start session")
    }

    private static func testMediaCommandsOnlyDiagnoseDuringWakeWordMode() throws {
        try expect(HeadsetRemoteCommandKind.previousTrack.activationSide == nil, "previous should diagnose only")
        try expect(HeadsetRemoteCommandKind.nextTrack.activationSide == nil, "next should diagnose only")
        try expect(HeadsetRemoteCommandKind.play.activationSide == nil, "play should diagnose only")
        try expect(HeadsetRemoteCommandKind.pause.activationSide == nil, "pause should diagnose only")
        try expect(HeadsetRemoteCommandKind.togglePlayPause.activationSide == nil, "toggle should diagnose only")
        try expect(
            HeadsetAudioRoutingPolicy.sessionSide(activeSide: .right, reportedAudioSide: .left) == .right,
            "reported audio source must not override an explicitly active right session"
        )
        try expect(
            HeadsetAudioRoutingPolicy.sessionSide(activeSide: .left, reportedAudioSide: .right) == .left,
            "reported audio source must not override an explicitly active left session"
        )
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

    private static func testNonDirectionalMediaCommandsOnlyDiagnose() throws {
        try expect(HeadsetRemoteCommandKind.play.activationSide == nil, "play should not activate an Agent")
        try expect(HeadsetRemoteCommandKind.pause.activationSide == nil, "pause should not activate an Agent")
        try expect(HeadsetRemoteCommandKind.togglePlayPause.activationSide == nil, "toggle should not activate an Agent")
        try expect(HeadsetRemoteCommandKind.nextTrack.diagnosticLabel == "收到 next", "next diagnostic label should be compact")
        try expect(HeadsetRemoteCommandKind.togglePlayPause.diagnosticLabel == "收到 toggle", "toggle diagnostic label should be compact")
    }

    private static func testInputDiagnosticsKeepsMediaAndBLESignals() throws {
        var diagnostics = HeadsetInputDiagnostics()

        diagnostics.recordBLE(.sleep, payload: Data([0x00]))
        try expect(diagnostics.label == "BLE sleep #1 00", "BLE sleep should be visible")

        diagnostics.recordMedia(.nextTrack)
        try expect(
            diagnostics.label == "媒体 next #1 | BLE sleep #1 00",
            "media command must stay visible even if BLE sleep was also received"
        )

        diagnostics.recordBLE(.wake, payload: Data([0x01]))
        try expect(
            diagnostics.label == "媒体 next #1 | BLE wake #2 01",
            "latest BLE signal should update without hiding media command"
        )

        diagnostics.recordMedia(.togglePlayPause, source: .legacyResponder)
        try expect(
            diagnostics.label == "legacy toggle #2 | BLE wake #2 01",
            "legacy remote-control events should be distinguishable from command-center events"
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

    private static func testLegacyRemoteControlEventsMapToCommands() throws {
        try expect(HeadsetLegacyRemoteControlEvent.previousTrack.commandKind == .previousTrack, "legacy previous should map to previous")
        try expect(HeadsetLegacyRemoteControlEvent.nextTrack.commandKind == .nextTrack, "legacy next should map to next")
        try expect(HeadsetLegacyRemoteControlEvent.togglePlayPause.commandKind == .togglePlayPause, "legacy toggle should map to toggle")
    }

    private static func testMediaOwnershipStartsOnlyAfterHeadsetReady() throws {
        try expect(!HeadsetMediaActivationPolicy.shouldOwnMedia(headsetReady: false), "media ownership should not start while BLE is still scanning")
        try expect(HeadsetMediaActivationPolicy.shouldOwnMedia(headsetReady: true), "media ownership should start after A9Ultra is ready")
    }

    private static func testNowPlayingMetadataAdvertisesPlayableQueue() throws {
        try expect(HeadsetNowPlayingMetadata.playbackDuration >= 3_600, "now playing should look like a long-lived audio stream")
        try expect(HeadsetNowPlayingMetadata.playbackQueueCount > 1, "previous/next requires a playable queue")
        try expect(
            HeadsetNowPlayingMetadata.playbackQueueIndex > 0
                && HeadsetNowPlayingMetadata.playbackQueueIndex < HeadsetNowPlayingMetadata.playbackQueueCount,
            "queue index should leave both previous and next available"
        )
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
