import Foundation

@main
struct AiServiceByokTests {
    static func main() throws {
        try testByokProviderCatalogFiltersCapabilities()
        try testByokProviderTemplatesDeclareCapabilitiesAndAdapters()
        try testByokProviderTemplatesAutofillDefaults()
        try testAiServiceChoicePersistsByokMetadataWithoutSecrets()
        try testAgentOverrideResolvesByokChoices()
        try testOpenAICompatibleChatRequestShape()
        try testOpenAICompatibleChatClientExposesConversationCall()
        try testAnthropicChatRequestShape()
        try testAnthropicChatClientExposesConversationCall()
        try testOpenAICompatibleAsrRequestShape()
        try testSilentWavFixtureIsValidForAsrValidation()
        print("AiServiceByokTests passed")
    }

    private static func testByokProviderCatalogFiltersCapabilities() throws {
        let llmIds = AiProviderCatalog.llmByokProviders.map(\.id)
        for providerId in ["openai-compatible", "minimax", "kimi", "claude", "doubao"] {
            try expect(llmIds.contains(providerId), "LLM BYOK providers should include \(providerId)")
        }

        let asrIds = AiProviderCatalog.asrByokProviders.map(\.id)
        try expect(asrIds == ["openai-compatible"], "ASR BYOK providers should only include Whisper-compatible providers")

        let ttsIds = AiProviderCatalog.ttsByokProviders.map(\.id)
        try expect(ttsIds == ["minimax"], "TTS BYOK providers should only include providers with implemented local TTS")
    }

    private static func testByokProviderTemplatesDeclareCapabilitiesAndAdapters() throws {
        for provider in AiProviderCatalog.llmByokProviders {
            try expect(provider.capabilities == ["llm"], "\(provider.id) should declare only LLM capability in the LLM picker")
            try expect(!provider.adapter.isEmpty, "\(provider.id) should declare the local chat adapter")
        }
        try expect(AiProviderCatalog.llmProvider(id: "claude")?.adapter == "anthropic-messages", "Claude should use the Anthropic Messages adapter")
        try expect(AiProviderCatalog.llmProvider(id: "kimi")?.adapter == "openai-compatible-chat", "Kimi should use OpenAI-compatible chat")

        for provider in AiProviderCatalog.asrByokProviders {
            try expect(provider.capabilities == ["asr"], "\(provider.id) should declare ASR capability")
            try expect(provider.adapter == "openai-whisper", "\(provider.id) should use the Whisper-compatible adapter")
        }

        for provider in AiProviderCatalog.ttsByokProviders {
            try expect(provider.capabilities == ["tts"], "\(provider.id) should declare TTS capability")
            try expect(provider.adapter == "minimax-tts", "\(provider.id) should use the MiniMax TTS adapter")
        }
    }

    private static func testByokProviderTemplatesAutofillDefaults() throws {
        let kimi = try unwrap(AiProviderCatalog.llmProvider(id: "kimi"), "Kimi provider should exist")
        try expect(kimi.baseUrlDefault == "https://api.moonshot.ai/v1", "Kimi should fill Moonshot base URL")
        try expect(kimi.modelDefault == "moonshot-v1-8k", "Kimi should fill a default model")
        try expect(kimi.credentialId == "llm:kimi", "Kimi should use a provider-scoped credential id")

        let minimaxTts = try unwrap(AiProviderCatalog.ttsProvider(id: "minimax"), "MiniMax TTS provider should exist")
        try expect(minimaxTts.baseUrlDefault == "https://api.minimaxi.com/v1", "MiniMax TTS should fill its API base URL")
        try expect(minimaxTts.credentialId == localMiniMaxCredentialId, "MiniMax TTS should keep the existing credential id")

        let choice = AiProviderCatalog.choice(
            mode: "byok",
            provider: minimaxTts,
            voiceId: "voice-a"
        )
        try expect(choice.mode == "byok", "provider choice should preserve BYOK mode")
        try expect(choice.providerId == "minimax", "provider choice should persist provider id")
        try expect(choice.baseUrl == "https://api.minimaxi.com/v1", "provider choice should autofill base URL")
        try expect(choice.voiceId == "voice-a", "provider choice should preserve voice id")
    }

    private static func testAiServiceChoicePersistsByokMetadataWithoutSecrets() throws {
        let llm = AiServiceChoice(
            mode: "byok",
            profileId: "",
            providerId: "openai-compatible",
            baseUrl: "https://api.example.com/v1",
            model: "gpt-test",
            credentialId: localLlmOpenAICompatibleCredentialId,
            displayName: "Example LLM"
        )
        let asr = AiServiceChoice(
            mode: "byok",
            providerId: "openai-compatible",
            baseUrl: "https://api.example.com/v1",
            model: "whisper-test",
            credentialId: localAsrOpenAICompatibleCredentialId,
            displayName: "Example ASR"
        )
        let settings = AiServiceSettings(
            defaults: AiServiceDefaults(
                llm: llm,
                asr: asr,
                tts: AiServiceChoice(
                    mode: "byok",
                    providerId: "minimax",
                    voiceId: "voice-a",
                    credentialId: localMiniMaxCredentialId
                )
            )
        )

        let data = try JSONEncoder().encode(settings)
        let raw = try unwrap(String(data: data, encoding: .utf8), "encoded settings should be readable")
        try expect(raw.contains("\"credentialId\":\"llm:openai-compatible\""), "settings should persist LLM credential id")
        try expect(raw.contains("\"credentialId\":\"asr:openai-compatible\""), "settings should persist ASR credential id")
        try expect(!raw.contains("sk-"), "settings JSON should not contain raw API keys")

        let decoded = try JSONDecoder().decode(AiServiceSettings.self, from: data)
        try expect(decoded.defaults.llm.baseUrl == "https://api.example.com/v1", "LLM base URL should round-trip")
        try expect(decoded.defaults.llm.model == "gpt-test", "LLM model should round-trip")
        try expect(decoded.defaults.llm.credentialId == localLlmOpenAICompatibleCredentialId, "LLM credential id should round-trip")
        try expect(decoded.defaults.asr.model == "whisper-test", "ASR model should round-trip")
        try expect(decoded.defaults.tts.credentialId == localMiniMaxCredentialId, "TTS credential id should round-trip")
    }

    private static func testAgentOverrideResolvesByokChoices() throws {
        let defaults = AiServiceDefaults(
            llm: AiServiceChoice(mode: "router", profileId: "default"),
            asr: AiServiceChoice(mode: "router", profileId: "volcengine-streaming"),
            tts: AiServiceChoice(mode: "system", providerId: "system")
        )
        let settings = AiServiceSettings(
            defaults: defaults,
            agentOverrides: [
                "agent-a": AiAgentOverride(
                    inherit: false,
                    llm: AiServiceChoice(
                        mode: "byok",
                        providerId: "openai-compatible",
                        baseUrl: "https://llm.example.com/v1",
                        model: "gpt-agent",
                        credentialId: localLlmOpenAICompatibleCredentialId
                    ),
                    asr: AiServiceChoice(
                        mode: "byok",
                        providerId: "openai-compatible",
                        baseUrl: "https://asr.example.com/v1",
                        model: "whisper-agent",
                        credentialId: localAsrOpenAICompatibleCredentialId
                    ),
                    tts: nil
                )
            ]
        )

        let resolved = settings.resolved(for: "agent-a")
        try expect(resolved.llm.mode == "byok", "Agent override should switch LLM to BYOK")
        try expect(resolved.llm.model == "gpt-agent", "Agent override should resolve LLM model")
        try expect(resolved.asr.mode == "byok", "Agent override should switch ASR to BYOK")
        try expect(resolved.asr.baseUrl == "https://asr.example.com/v1", "Agent override should resolve ASR base URL")
        try expect(resolved.tts.mode == "system", "missing override fields should inherit defaults")
        try expect(settings.resolved(for: "agent-b").llm.mode == "router", "Unknown Agent should inherit defaults")
    }

    private static func testOpenAICompatibleChatRequestShape() throws {
        let request = try OpenAICompatibleChatClient.makeRequest(
            baseUrl: "https://api.example.com/v1/",
            apiKey: "sk-test",
            model: "gpt-test",
            messages: [OpenAICompatibleChatMessage(role: "user", content: "ping")]
        )

        try expect(request.url?.absoluteString == "https://api.example.com/v1/chat/completions", "chat request should target chat completions")
        try expect(request.httpMethod == "POST", "chat request should be POST")
        try expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test", "chat request should include bearer auth")
        try expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json", "chat request should be JSON")

        let body = try decodeJsonObject(request.httpBody, "chat body should be JSON")
        try expect(body["model"] as? String == "gpt-test", "chat request should include model")
        let messages = try unwrap(body["messages"] as? [[String: String]], "chat request should include messages")
        try expect(messages == [["role": "user", "content": "ping"]], "chat request should include the prompt message")
        try expect(body["stream"] as? Bool == false, "chat request should be non-streaming")
    }

    private static func testOpenAICompatibleChatClientExposesConversationCall() throws {
        let source = try readSource("iosApp/OpenClawRemote/Sources/OpenAICompatibleAiClients.swift")
        try expect(source.contains("func chat(baseUrl: String, apiKey: String, model: String, messages: [OpenAICompatibleChatMessage]) async throws -> String"), "OpenAI-compatible client should expose a reusable chat call")
        try expect(source.contains("messages: messages"), "OpenAI-compatible reusable chat should send caller-provided conversation history")
    }

    private static func testAnthropicChatRequestShape() throws {
        let request = try AnthropicChatClient.makeRequest(
            baseUrl: "https://api.anthropic.com/v1/",
            apiKey: "sk-ant-test",
            model: "claude-sonnet-4-20250514",
            messages: [OpenAICompatibleChatMessage(role: "user", content: "ping")]
        )

        try expect(request.url?.absoluteString == "https://api.anthropic.com/v1/messages", "Claude request should target Messages API")
        try expect(request.httpMethod == "POST", "Claude request should be POST")
        try expect(request.value(forHTTPHeaderField: "x-api-key") == "sk-ant-test", "Claude request should use x-api-key auth")
        try expect(request.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01", "Claude request should set API version")
        try expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json", "Claude request should be JSON")

        let body = try decodeJsonObject(request.httpBody, "Claude body should be JSON")
        try expect(body["model"] as? String == "claude-sonnet-4-20250514", "Claude request should include model")
        try expect(body["max_tokens"] as? Int == 64, "Claude test request should cap max tokens")
        let messages = try unwrap(body["messages"] as? [[String: String]], "Claude request should include messages")
        try expect(messages == [["role": "user", "content": "ping"]], "Claude request should include prompt message")
    }

    private static func testAnthropicChatClientExposesConversationCall() throws {
        let source = try readSource("iosApp/OpenClawRemote/Sources/OpenAICompatibleAiClients.swift")
        try expect(source.contains("func chat(baseUrl: String, apiKey: String, model: String, messages: [OpenAICompatibleChatMessage]) async throws -> String"), "Anthropic client should expose a reusable chat call")
        try expect(source.contains("messages: messages"), "Anthropic reusable chat should send caller-provided conversation history")
    }

    private static func testOpenAICompatibleAsrRequestShape() throws {
        let request = try OpenAICompatibleAsrClient.makeTranscriptionRequest(
            baseUrl: "https://api.example.com/v1",
            apiKey: "sk-asr",
            model: "whisper-test",
            fileName: "sample.wav",
            audioData: Data([0x52, 0x49, 0x46, 0x46]),
            boundary: "boundary-test"
        )

        try expect(request.url?.absoluteString == "https://api.example.com/v1/audio/transcriptions", "ASR request should target audio transcriptions")
        try expect(request.httpMethod == "POST", "ASR request should be POST")
        try expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-asr", "ASR request should include bearer auth")
        try expect(request.value(forHTTPHeaderField: "Content-Type") == "multipart/form-data; boundary=boundary-test", "ASR request should be multipart")
        let body = try unwrap(String(data: try unwrap(request.httpBody, "ASR request should have body"), encoding: .utf8), "ASR body should be inspectable")
        try expect(body.contains("name=\"model\""), "ASR request should include model field")
        try expect(body.contains("whisper-test"), "ASR request should include model value")
        try expect(body.contains("name=\"file\"; filename=\"sample.wav\""), "ASR request should include audio file")
        try expect(body.contains("audio/wav"), "ASR request should mark audio as WAV")
    }

    private static func testSilentWavFixtureIsValidForAsrValidation() throws {
        let wav = OpenAICompatibleAsrClient.silentWav16kMono(durationMilliseconds: 200)
        try expect(wav.count > 44, "silent WAV should include header and PCM data")
        try expect(String(data: wav.prefix(4), encoding: .ascii) == "RIFF", "silent WAV should start with RIFF")
        try expect(String(data: wav.dropFirst(8).prefix(4), encoding: .ascii) == "WAVE", "silent WAV should be a WAVE file")
    }

    private static func decodeJsonObject(_ data: Data?, _ message: String) throws -> [String: Any] {
        let data = try unwrap(data, message)
        let object = try JSONSerialization.jsonObject(with: data)
        guard let dictionary = object as? [String: Any] else {
            throw TestFailure(message)
        }
        return dictionary
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() {
            throw TestFailure(message)
        }
    }

    private static func unwrap<T>(_ value: T?, _ message: String) throws -> T {
        guard let value else {
            throw TestFailure(message)
        }
        return value
    }

    private static func readSource(_ relativePath: String) throws -> String {
        let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }
}

private struct TestFailure: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}
