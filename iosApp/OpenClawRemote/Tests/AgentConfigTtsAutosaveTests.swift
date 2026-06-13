import Foundation

@main
struct AgentConfigTtsAutosaveTests {
    static func main() throws {
        try testAgentListExposesAiProviderVirtualConversation()
        try testAgentConfigShowsAiServiceSummaryInsteadOfEditingTtsInline()
        try testSettingsTabExposesAiServicePage()
        try testMainScreenByokAsrTranscribesLocallyBeforeSendingText()
        print("AgentConfigTtsAutosaveTests passed")
    }

    private static func testAgentListExposesAiProviderVirtualConversation() throws {
        let source = try readSource("iosApp/OpenClawRemote/Sources/Views/AgentsTabView.swift")
        let agentsTabView = try extractStruct(named: "AgentsTabView", from: source)
        let providerChatScreen = try extractStruct(named: "ProviderChatScreen", from: source)

        try expect(agentsTabView.contains("AI Provider"), "Agent list should show a visible AI Provider virtual conversation")
        try expect(agentsTabView.contains("ProviderChatScreen("), "Agent list should navigate to a Provider chat screen")
        try expect(agentsTabView.contains("AiProviderConversationRow"), "Agent list should render a dedicated Provider row")
        try expect(providerChatScreen.contains("GatewayAuthClient.aiChat"), "Provider chat should call Router AI chat in router mode")
        try expect(providerChatScreen.contains("OpenAICompatibleChatClient().chat"), "Provider chat should call local BYOK chat in OpenAI-compatible mode")
        try expect(providerChatScreen.contains("AnthropicChatClient().chat"), "Provider chat should call local BYOK chat in Anthropic mode")
        try expect(providerChatScreen.contains("InputAreaView("), "Provider chat should reuse the Agent chat input UI")
        try expect(providerChatScreen.contains("inputMode: $inputMode"), "Provider chat should support switching between voice and text input")
        try expect(providerChatScreen.contains("audioRecorder.startRecording()"), "Provider chat should support press-and-hold recording")
        try expect(providerChatScreen.contains("sendAudioUsingSelectedAsr"), "Provider chat should run ASR before sending voice input to the Provider")
        try expect(providerChatScreen.contains("OpenAICompatibleAsrClient().transcribe"), "Provider chat should support local BYOK ASR")
        try expect(providerChatScreen.contains("messageSpeechController.speakManualText"), "Provider chat should support manual TTS playback")
        try expect(providerChatScreen.contains("messageSpeechController.enqueueAssistantReplies"), "Provider chat should support automatic assistant reply TTS")
        try expect(!providerChatScreen.contains("wsManager.sendText"), "Provider chat must not send through the Agent WebSocket")
    }

    private static func testAgentConfigShowsAiServiceSummaryInsteadOfEditingTtsInline() throws {
        let source = try readSource("iosApp/OpenClawRemote/Sources/Views/AgentsTabView.swift")
        let agentConfigView = try extractStruct(named: "AgentConfigView", from: source)

        try expect(agentConfigView.contains("AI 服务"), "Agent config view should keep an AI service summary")
        try expect(agentConfigView.contains("AIServiceNavigationLink"), "Agent config view should navigate to the unified AI service page")
        try expect(agentConfigView.contains("AiServiceInfoRow(label: \"LLM\""), "Agent config view should summarize resolved LLM")
        try expect(agentConfigView.contains("AiServiceInfoRow(label: \"ASR\""), "Agent config view should summarize resolved ASR")
        try expect(agentConfigView.contains("AiServiceInfoRow(label: \"TTS\""), "Agent config view should summarize resolved TTS")
        try expect(!agentConfigView.contains("SecureField(\"MiniMax API Key\""), "Agent config view should not edit MiniMax keys inline")
        try expect(!agentConfigView.contains("Picker(\"TTS 引擎\""), "Agent config view should not edit TTS inline")
        try expect(!agentConfigView.contains("persistTtsConfigurationIfChanged"), "Agent config view should not autosave distributed TTS settings")
    }

    private static func testSettingsTabExposesAiServicePage() throws {
        let source = try readSource("iosApp/OpenClawRemote/Sources/Views/SimpleSettingsTabView.swift")
        let settingsTab = try extractStruct(named: "SimpleSettingsTabView", from: source)
        let aiServiceView = try extractStruct(named: "AiServiceSettingsView", from: source)

        try expect(settingsTab.contains("AiServiceSettingsView("), "Settings tab should navigate to a dedicated AI service page")
        try expect(settingsTab.contains("Label(\"AI 服务\", systemImage: \"sparkles\")"), "Settings tab should show a visible AI service entry")

        for requiredText in [
            "LLM",
            "AiProviderCatalog.llmByokProviders",
            "LLM API Key",
            "测试 LLM",
            "ASR",
            "ASR API Key",
            "测试 ASR",
            "TTS 引擎",
            "本机 Key",
            "MiniMax API Key",
            "MiniMax 音色",
            "从 MiniMax 刷新可用音色"
        ] {
            try expect(aiServiceView.contains(requiredText), "AI service page should contain \(requiredText)")
        }

        try expect(aiServiceView.contains("WalletAndPlanView("), "AI service page should preserve a wallet and plan link")
        try expect(aiServiceView.contains("settingsManager.updateLocalCredential"), "AI service page should save BYOK keys through the credential vault")
        try expect(aiServiceView.contains("settingsManager.updateAiSettings"), "AI service page should persist unified AI settings")
        try expect(aiServiceView.contains("OpenAICompatibleChatClient"), "AI service page should test BYOK LLM directly from the app")
        try expect(aiServiceView.contains("OpenAICompatibleAsrClient"), "AI service page should test BYOK ASR directly from the app")
    }

    private static func testMainScreenByokAsrTranscribesLocallyBeforeSendingText() throws {
        let source = try readSource("iosApp/OpenClawRemote/Sources/MainScreenView.swift")
        let sendFunction = try extractFunction(named: "sendAudioUsingSelectedAsr", from: source)

        try expect(sendFunction.contains("settingsManager.aiSettings.resolved(for: selectedProfile.id).asr"), "main chat should resolve ASR from unified AI settings")
        try expect(sendFunction.contains("guard asr.mode == \"byok\" else"), "main chat should keep Router/Agent ASR on the existing audio path")
        try expect(sendFunction.contains("OpenAICompatibleAsrClient().transcribe"), "BYOK ASR should transcribe locally from the app")
        try expect(sendFunction.contains("settingsManager.localCredential"), "BYOK ASR should read the local Keychain credential")
        try expect(sendFunction.contains("wsManager.sendText(text)"), "BYOK ASR should send the transcript as text to the Agent")
        try expect(sendFunction.contains("请先在 AI 服务中保存 ASR API Key"), "missing BYOK ASR key should be shown before sending audio")
    }

    private static func extractStruct(named name: String, from source: String) throws -> String {
        if let block = try? extractBlock(startingWith: "private struct \(name):", from: source) {
            return block
        }
        return try extractBlock(startingWith: "struct \(name):", from: source)
    }

    private static func extractFunction(named name: String, from source: String) throws -> String {
        try extractBlock(startingWith: "private func \(name)(", from: source)
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
