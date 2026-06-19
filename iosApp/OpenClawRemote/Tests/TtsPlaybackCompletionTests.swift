import Foundation

@main
struct TtsPlaybackCompletionTests {
    static func main() throws {
        try testStopButtonIsStrictlyTiedToActiveSpeech()
        try testTtsEnginesHaveCompletionWatchdogs()
        print("TtsPlaybackCompletionTests passed")
    }

    private static func testStopButtonIsStrictlyTiedToActiveSpeech() throws {
        let source = try readSource("iosApp/OpenClawRemote/Sources/MainScreenView.swift")
        let playbackControls = try extractStruct(named: "PlaybackControlsView", from: source)

        try expect(playbackControls.contains("if isPlaybackSpeaking"), "stop playback button should only render while TTS is actively speaking")
        try expect(playbackControls.contains("stop.circle.fill"), "active speech should show the red stop button")
        try expect(!playbackControls.contains(".hidden()"), "finished speech should remove the stop button instead of hiding a placeholder")
        try expect(!playbackControls.contains(".opacity(isPlaybackSpeaking"), "finished speech should not keep an invisible stop button in layout")
    }

    private static func testTtsEnginesHaveCompletionWatchdogs() throws {
        let source = try readSource("iosApp/OpenClawRemote/Sources/MessageSpeechController.swift")
        let systemEngine = try extractClass(named: "SystemTtsEngine", from: source)
        let minimaxEngine = try extractClass(named: "MiniMaxTtsEngine", from: source)

        try expect(systemEngine.contains("scheduleCompletionWatchdog"), "system TTS should clear speaking state even if AVSpeechSynthesizer misses a finish callback")
        try expect(systemEngine.contains("completeSpeech"), "system TTS finish/cancel/watchdog should share one completion path")
        try expect(minimaxEngine.contains("scheduleCompletionWatchdog"), "MiniMax TTS should clear speaking state even if AVAudioPlayer misses a finish callback")
        try expect(minimaxEngine.contains("completePlayback"), "MiniMax TTS finish/error/watchdog should share one completion path")
    }

    private static func extractStruct(named name: String, from source: String) throws -> String {
        try extractBlock(startingWith: "struct \(name):", from: source)
    }

    private static func extractClass(named name: String, from source: String) throws -> String {
        try extractBlock(startingWith: "final class \(name):", from: source)
    }

    private static func extractBlock(startingWith marker: String, from source: String) throws -> String {
        guard let markerRange = source.range(of: marker) else {
            throw TestFailure("Could not find \(marker)")
        }
        guard let openingBrace = source[markerRange.lowerBound...].firstIndex(of: "{") else {
            throw TestFailure("Could not find opening brace for \(marker)")
        }

        var depth = 0
        var index = openingBrace
        while index < source.endIndex {
            let character = source[index]
            if character == "{" {
                depth += 1
            } else if character == "}" {
                depth -= 1
                if depth == 0 {
                    return String(source[markerRange.lowerBound...index])
                }
            }
            index = source.index(after: index)
        }

        throw TestFailure("Could not find closing brace for \(marker)")
    }

    private static func readSource(_ relativePath: String) throws -> String {
        let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() {
            throw TestFailure(message)
        }
    }
}

private struct TestFailure: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}
