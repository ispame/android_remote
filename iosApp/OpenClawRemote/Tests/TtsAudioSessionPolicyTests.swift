import Foundation

@main
struct TtsAudioSessionPolicyTests {
    static func main() throws {
        try testBuiltInOutputsUseMediaPlaybackSession()
        try testBluetoothHfpKeepsDuplexVoiceSession()
        try testMediaExternalOutputsUseMediaPlaybackSession()
        print("TtsAudioSessionPolicyTests passed")
    }

    private static func testBuiltInOutputsUseMediaPlaybackSession() throws {
        for route in [[], ["BuiltInReceiver"], ["BuiltInSpeaker"]] {
            let config = TtsAudioSessionPolicy.configuration(outputPortTypes: route)
            try expect(config.categoryName == "playback", "built-in TTS route \(route) should use media playback category")
            try expect(config.modeName == "spokenAudio", "built-in TTS route \(route) should use spokenAudio mode instead of voiceChat")
            try expect(config.optionNames.contains("allowBluetoothA2DP"), "media playback should allow Bluetooth A2DP")
            try expect(!config.optionNames.contains("allowBluetoothHFP"), "built-in media playback should not use Bluetooth HFP phone-call routing")
            try expect(!config.optionNames.contains("defaultToSpeaker"), "playback category already routes built-in audio through the speaker")
            try expect(!config.shouldOverrideToSpeaker, "media playback should not need a speaker override")
        }
    }

    private static func testBluetoothHfpKeepsDuplexVoiceSession() throws {
        let config = TtsAudioSessionPolicy.configuration(outputPortTypes: ["BluetoothHFP"])
        try expect(config.categoryName == "playAndRecord", "Bluetooth HFP should keep duplex playAndRecord")
        try expect(config.modeName == "voiceChat", "Bluetooth HFP should keep voiceChat for headset compatibility")
        try expect(config.optionNames.contains("allowBluetoothHFP"), "Bluetooth HFP route should remain available")
        try expect(config.optionNames.contains("allowBluetoothA2DP"), "Bluetooth A2DP route should remain available")
        try expect(!config.shouldOverrideToSpeaker, "external headset route should not force speaker")
    }

    private static func testMediaExternalOutputsUseMediaPlaybackSession() throws {
        for route in ["Headphones", "BluetoothA2DPOutput", "BluetoothLE", "AirPlay", "CarAudio", "HDMI", "LineOut", "USBAudio"] {
            let config = TtsAudioSessionPolicy.configuration(outputPortTypes: [route])
            try expect(config.categoryName == "playback", "external media route \(route) should use media playback")
            try expect(config.modeName == "spokenAudio", "external media route \(route) should not use voiceChat")
            try expect(!config.shouldOverrideToSpeaker, "external media route \(route) should keep TTS on the connected output")
        }
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() {
            throw TestFailure(message)
        }
    }
}

struct GatewayAccountAgentProfile: Codable {
    var agentProfileId: String
    var platform: String
    var displayName: String
    var gatewayUrl: String
    var backendId: String
    var backendLabel: String?
    var isPaired: Bool
    var asrMode: String
    var pinned: Bool
    var sortOrder: Int
}

private struct TestFailure: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}
