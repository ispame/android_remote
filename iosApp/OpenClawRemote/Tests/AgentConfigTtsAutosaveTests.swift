import Foundation

@main
struct AgentConfigTtsAutosaveTests {
    static func main() throws {
        try testAgentListExposesAiProviderVirtualConversation()
        try testAgentConfigShowsInlineAsrTtsDropdowns()
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
        try expect(providerChatScreen.contains("ByokAsrTranscriptionClient.transcribe"), "Provider chat should support provider-aware local BYOK ASR")
        try expect(!providerChatScreen.contains("正在使用本机 ASR 识别"), "Provider chat should not show an inaccurate local-device ASR progress message")
        try expect(!providerChatScreen.contains("本机 ASR"), "Provider chat ASR copy should match BYOK settings, not local-device ASR")
        try expect(providerChatScreen.contains("messageSpeechController.speakManualText"), "Provider chat should support manual TTS playback")
        try expect(providerChatScreen.contains("messageSpeechController.enqueueAssistantReplies"), "Provider chat should support automatic assistant reply TTS")
        try expect(!providerChatScreen.contains("wsManager.sendText"), "Provider chat must not send through the Agent WebSocket")
    }

    private static func testAgentConfigShowsInlineAsrTtsDropdowns() throws {
        let source = try readSource("iosApp/OpenClawRemote/Sources/Views/AgentsTabView.swift")
        let agentConfigView = try extractStruct(named: "AgentConfigView", from: source)

        try expect(agentConfigView.contains("AI 服务"), "Agent config view should keep an AI service summary")
        try expect(!agentConfigView.contains("NavigationLink"), "Agent AI service settings should not navigate to a separate editor")
        try expect(!agentConfigView.contains("AgentAiOverrideEditorView("), "Agent config should not open a separate Agent AI override editor")
        try expect(!agentConfigView.contains("AiServiceInfoRow(label: \"来源\""), "Agent config view should not show the AI service source row")
        try expect(!agentConfigView.contains("AiServiceInfoRow(label: \"LLM\""), "Agent config view should not summarize LLM")
        try expect(agentConfigView.contains("AgentAiServicePicker(title: \"ASR\""), "Agent config should edit ASR inline")
        try expect(agentConfigView.contains("AgentAiServicePicker(title: \"TTS\""), "Agent config should edit TTS inline")
        try expect(!agentConfigView.contains("跟随全局"), "Agent config picker should not expose a follow-global option")
        try expect(agentConfigView.contains("defaultAsrSelectionId"), "Agent config should still show the resolved global ASR choice when there is no override")
        try expect(agentConfigView.contains("defaultTtsSelectionId"), "Agent config should still show the resolved global TTS choice when there is no override")
        try expect(agentConfigView.contains("configuredAsrByokProviders"), "Agent config should filter ASR BYOK providers by saved credentials")
        try expect(agentConfigView.contains("configuredTtsByokProviders"), "Agent config should filter TTS BYOK providers by saved credentials")
        try expect(agentConfigView.contains("localAsrVolcengineCredentialId"), "Agent config should support Volcengine ASR as BYOK when configured")
        try expect(agentConfigView.contains("updateAgentAiServiceOverride"), "Agent config should persist field-level Agent AI overrides")
        try expect(!agentConfigView.contains("SecureField(\"MiniMax API Key\""), "Agent config view should not edit MiniMax keys inline")
        try expect(!agentConfigView.contains("persistTtsConfigurationIfChanged"), "Agent config view should not autosave distributed TTS settings")
        try expect(!agentConfigView.contains("Toggle(\"继承全局默认\""), "Agent config should not expose a global inheritance toggle")
        try expect(!agentConfigView.contains("Picker(\"模型服务\""), "Agent config should not edit LLM")
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
            "按住测试 ASR",
            "TTS 配置",
            "本机 Key",
            "MiniMax API Key",
            "MiniMax 音色",
            "从 MiniMax 刷新可用音色",
            "业务场景",
            "Provider Chat LLM",
            "录音 ASR",
            "播放 TTS"
        ] {
            try expect(aiServiceView.contains(requiredText), "AI service page should contain \(requiredText)")
        }
        try expect(!aiServiceView.contains("AiSettingsInfoRow(label: \"Router TTS\""), "AI service page should not show Router TTS")

        try expect(aiServiceView.contains("WalletAndPlanView("), "AI service page should preserve a wallet and plan link")
        try expect(aiServiceView.contains("settingsManager.updateLocalCredential"), "AI service page should save BYOK keys through the credential vault")
        try expect(aiServiceView.contains("settingsManager.upsertAiServiceConfig"), "AI service page should persist service library entries")
        try expect(aiServiceView.contains("settingsManager.updateAiSceneSelection"), "AI service page should persist scene selections separately")
        try expect(!aiServiceView.contains(".onChange(of: llmApiKey)"), "AI service page should not autosave raw keys while editing")
        try expect(aiServiceView.contains("OpenAICompatibleChatClient"), "AI service page should test BYOK LLM directly from the app")
        try expect(aiServiceView.contains("startAsrTestRecording"), "AI service page should start ASR test recording while the user presses the test control")
        try expect(aiServiceView.contains("finishAsrTestRecording"), "AI service page should finish ASR test recording when the user releases the test control")
        try expect(aiServiceView.contains("ByokAsrTranscriptionClient.transcribe"), "AI service page should test provider-aware BYOK ASR with recorded speech")
        try expect(!aiServiceView.contains("ByokAsrTranscriptionClient.testTranscription"), "AI service page should not test ASR with a silent fixture")
    }

    private static func testMainScreenByokAsrTranscribesLocallyBeforeSendingText() throws {
        let source = try readSource("iosApp/OpenClawRemote/Sources/MainScreenView.swift")
        let sendFunction = try extractFunction(named: "sendAudioUsingSelectedAsr", from: source)

        try expect(sendFunction.contains("settingsManager.aiSettings.resolved(for: selectedProfile.id).asr"), "main chat should resolve ASR from unified AI settings")
        try expect(sendFunction.contains("guard asr.mode == \"byok\" else"), "main chat should keep Router/Agent ASR on the existing audio path")
        try expect(sendFunction.contains("ByokAsrTranscriptionClient.transcribe"), "BYOK ASR should transcribe locally from the app")
        try expect(sendFunction.contains("settingsManager.localCredential"), "BYOK ASR should read the local Keychain credential")
        try expect(sendFunction.contains("wsManager.sendText(text)"), "BYOK ASR should send the transcript as text to the Agent")
        try expect(sendFunction.contains("请先在 AI 服务中保存 ASR API Key"), "missing BYOK ASR key should be shown before sending audio")
        try expect(!sendFunction.contains("正在使用本机 ASR 识别"), "main chat should not add an inaccurate ASR progress message to the conversation")
        try expect(!sendFunction.contains("本机 ASR"), "main chat ASR copy should match BYOK settings, not local-device ASR")
        try expect(sendFunction.contains("BYOK ASR 没有识别到文本"), "empty ASR result should use BYOK ASR wording")
        try expect(sendFunction.contains("BYOK ASR 失败"), "ASR failures should use BYOK ASR wording")
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
