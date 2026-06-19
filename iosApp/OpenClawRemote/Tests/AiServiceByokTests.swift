import Foundation

@main
struct AiServiceByokTests {
    static func main() throws {
        try testByokProviderCatalogFiltersCapabilities()
        try testByokProviderTemplatesDeclareCapabilitiesAndAdapters()
        try testByokProviderTemplatesAutofillDefaults()
        try testByokProviderSelectionPrefersSavedCredential()
        try testAiServiceChoicePersistsByokMetadataWithoutSecrets()
        try testAiServiceSettingsDecodeV2ServiceLibrary()
        try testAiServiceSettingsMigrateLegacyDefaultsToServiceLibrary()
        try testAgentOverrideResolvesByokChoices()
        try testOpenAICompatibleChatRequestShape()
        try testOpenAICompatibleChatClientExposesConversationCall()
        try testAnthropicChatRequestShape()
        try testAnthropicChatClientExposesConversationCall()
        try testOpenAICompatibleAsrRequestShape()
        try testVolcengineAsrCredentialAndRequestShape()
        try testSilentWavFixtureIsValidForAsrValidation()
        print("AiServiceByokTests passed")
    }

    private static func testByokProviderCatalogFiltersCapabilities() throws {
        let llmIds = AiProviderCatalog.llmByokProviders.map(\.id)
        for providerId in ["openai-compatible", "minimax", "kimi", "claude", "doubao"] {
            try expect(llmIds.contains(providerId), "LLM BYOK providers should include \(providerId)")
        }

        let asrIds = AiProviderCatalog.asrByokProviders.map(\.id)
        try expect(asrIds == ["openai-compatible", "volcengine"], "ASR BYOK providers should include Whisper-compatible and Volcengine providers")

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

        let whisperAsr = try unwrap(AiProviderCatalog.asrProvider(id: "openai-compatible"), "Whisper ASR provider should exist")
        try expect(whisperAsr.capabilities == ["asr"], "Whisper ASR should declare ASR capability")
        try expect(whisperAsr.adapter == "openai-whisper", "Whisper ASR should use the Whisper-compatible adapter")

        let volcengineAsr = try unwrap(AiProviderCatalog.asrProvider(id: "volcengine"), "Volcengine ASR provider should exist")
        try expect(volcengineAsr.capabilities == ["asr"], "Volcengine ASR should declare ASR capability")
        try expect(volcengineAsr.adapter == "volcengine-asr", "Volcengine ASR should declare the Volcengine adapter")
        try expect(volcengineAsr.credentialId == localAsrVolcengineCredentialId, "Volcengine ASR should use a dedicated ASR credential id")

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

        let minimaxLlm = try unwrap(AiProviderCatalog.llmProvider(id: "minimax"), "MiniMax LLM provider should exist")
        try expect(minimaxLlm.baseUrlDefault == "https://api.minimaxi.com/v1", "MiniMax LLM should use the documented China API base URL")

        let minimaxTts = try unwrap(AiProviderCatalog.ttsProvider(id: "minimax"), "MiniMax TTS provider should exist")
        try expect(minimaxTts.baseUrlDefault == "https://api.minimaxi.com/v1", "MiniMax TTS should fill its API base URL")
        try expect(minimaxTts.credentialId == localMiniMaxCredentialId, "MiniMax TTS should keep the existing credential id")

        let volcengineAsr = try unwrap(AiProviderCatalog.asrProvider(id: "volcengine"), "Volcengine ASR provider should exist")
        try expect(volcengineAsr.label == "豆包火山云 ASR", "Volcengine ASR should be labeled as Doubao Volcengine ASR")
        try expect(!volcengineAsr.baseUrlDefault.isEmpty, "Volcengine ASR should provide a configurable base URL default")
        try expect(!volcengineAsr.modelDefault.isEmpty, "Volcengine ASR should provide a configurable model/app id default")

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

    private static func testByokProviderSelectionPrefersSavedCredential() throws {
        let preferred = AiProviderCatalog.preferredProvider(
            in: AiProviderCatalog.llmByokProviders,
            currentProviderId: "openai-compatible",
            hasCredential: { $0 == localLlmKimiCredentialId }
        )

        try expect(preferred.id == "kimi", "BYOK provider draft should prefer the provider with a saved API key")

        let fallback = AiProviderCatalog.preferredProvider(
            in: AiProviderCatalog.llmByokProviders,
            currentProviderId: "claude",
            hasCredential: { _ in false }
        )

        try expect(fallback.id == "claude", "BYOK provider draft should keep the current provider when no saved API key exists")
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

    private static func testAiServiceSettingsDecodeV2ServiceLibrary() throws {
        let json = """
        {
          "version": 2,
          "serviceConfigs": {
            "llm": [
              {
                "id": "llm-router-default",
                "capability": "llm",
                "mode": "router",
                "providerId": "router",
                "profileId": "default",
                "apiKey": "must-not-persist"
              },
              {
                "id": "llm-byok-openai",
                "capability": "llm",
                "mode": "byok",
                "providerId": "openai-compatible",
                "baseUrl": "https://api.example.com/v1/",
                "model": "gpt-test",
                "credentialId": "llm:openai-compatible",
                "apiKey": "must-not-persist"
              }
            ],
            "asr": [
              {
                "id": "asr-agent-backend",
                "capability": "asr",
                "mode": "backend",
                "providerId": "agent"
              }
            ],
            "tts": [
              {
                "id": "tts-system",
                "capability": "tts",
                "mode": "system",
                "providerId": "system"
              },
              {
                "id": "tts-router-coming-soon",
                "capability": "tts",
                "mode": "router",
                "providerId": "router",
                "enabled": true,
                "status": "available"
              }
            ]
          },
          "sceneSelections": {
            "providerChat": { "llmConfigId": "llm-byok-openai" },
            "recording": { "asrConfigId": "asr-agent-backend" },
            "playback": { "ttsConfigId": "tts-router-coming-soon" },
            "agentOverrides": {
              "profile-openclaw": {
                "inherit": false,
                "llmConfigId": "llm-router-default",
                "asrConfigId": "asr-agent-backend",
                "ttsConfigId": "tts-system"
              }
            }
          }
        }
        """

        let settings = try JSONDecoder().decode(AiServiceSettings.self, from: Data(json.utf8))

        try expect(settings.version == 2, "settings should decode v2")
        try expect(settings.sceneSelections.providerChat.llmConfigId == "llm-byok-openai", "Provider Chat should keep its LLM scene selection")
        try expect(settings.sceneSelections.recording.asrConfigId == "asr-agent-backend", "Recording should keep its ASR scene selection")
        try expect(settings.sceneSelections.playback.ttsConfigId == "tts-system", "Router TTS selection should fall back to system TTS")
        try expect(settings.defaults.llm.mode == "byok", "legacy defaults projection should follow Provider Chat")
        try expect(settings.defaults.llm.baseUrl == "https://api.example.com/v1", "BYOK base URL should normalize trailing slash")
        try expect(settings.defaults.asr.mode == "backend", "recording ASR should project Agent backend")
        let routerTts = try unwrap(settings.serviceConfigs.tts.first { $0.id == "tts-router-coming-soon" }, "Router TTS config should exist")
        try expect(routerTts.enabled == false, "Router TTS should not remain selectable")
        try expect(routerTts.status == "coming_soon", "Router TTS should stay disabled when decoded from old settings")
        try expect(settings.sceneSelections.agentOverrides["profile-openclaw"]?.llmConfigId == "llm-router-default", "Agent scene override should persist config ids")

        let encoded = try JSONEncoder().encode(settings)
        let raw = try unwrap(String(data: encoded, encoding: .utf8), "encoded v2 settings should be readable")
        try expect(raw.contains("serviceConfigs"), "encoded settings should include service configs")
        try expect(raw.contains("sceneSelections"), "encoded settings should include scene selections")
        try expect(!raw.contains("must-not-persist"), "encoded settings should not include raw keys")
        try expect(!raw.lowercased().contains("apikey"), "encoded settings should not include api key fields")
    }

    private static func testAiServiceSettingsMigrateLegacyDefaultsToServiceLibrary() throws {
        let json = """
        {
          "defaults": {
            "llm": {
              "mode": "byok",
              "providerId": "minimax",
              "baseUrl": "https://api.minimax.com/v1/",
              "model": "MiniMax-M2.7",
              "credentialId": "llm:minimax"
            },
            "asr": { "mode": "router", "profileId": "volcengine-streaming" },
            "tts": { "mode": "system", "providerId": "system" }
          }
        }
        """

        let settings = try JSONDecoder().decode(AiServiceSettings.self, from: Data(json.utf8))

        try expect(settings.version == 2, "legacy settings should migrate to v2")
        try expect(settings.sceneSelections.providerChat.llmConfigId == "llm-byok-minimax", "legacy LLM should become Provider Chat scene selection")
        try expect(settings.sceneSelections.recording.asrConfigId == "asr-router-volcengine-streaming", "legacy ASR should become recording scene selection")
        try expect(settings.sceneSelections.playback.ttsConfigId == "tts-system", "legacy TTS should become playback scene selection")
        try expect(settings.serviceConfigs.llm.contains { $0.id == "llm-byok-minimax" }, "legacy LLM should create a service config")
        try expect(settings.defaults.llm.baseUrl == "https://api.minimaxi.com/v1", "MiniMax legacy host should migrate")
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

    private static func testVolcengineAsrCredentialAndRequestShape() throws {
        let credential = try VolcengineAsrClient.parseCredential("app-key-test:access-key-test")
        try expect(credential.appKey == "app-key-test", "Volcengine ASR credential should parse the app key")
        try expect(credential.accessKey == "access-key-test", "Volcengine ASR credential should parse the access key")

        let request = try VolcengineAsrClient.makeWebSocketRequest(
            endpoint: "wss://openspeech.bytedance.com/api/v3/sauc/bigmodel",
            credential: credential,
            resourceId: "volc.bigasr.sauc.duration",
            connectId: "connect-test"
        )
        try expect(request.url?.absoluteString == "wss://openspeech.bytedance.com/api/v3/sauc/bigmodel", "Volcengine ASR should use the configured websocket endpoint")
        try expect(request.value(forHTTPHeaderField: "X-Api-App-Key") == "app-key-test", "Volcengine ASR should send app key header")
        try expect(request.value(forHTTPHeaderField: "X-Api-Access-Key") == "access-key-test", "Volcengine ASR should send access key header")
        try expect(request.value(forHTTPHeaderField: "X-Api-Resource-Id") == "volc.bigasr.sauc.duration", "Volcengine ASR should send resource id header")
        try expect(request.value(forHTTPHeaderField: "X-Api-Connect-Id") == "connect-test", "Volcengine ASR should send connect id header")

        let wav = OpenAICompatibleAsrClient.silentWav16kMono(durationMilliseconds: 20)
        let audio = try VolcengineAsrClient.extractPcmAudio(from: wav)
        try expect(audio.sampleRate == 16_000, "Volcengine ASR should read sample rate from WAV")
        try expect(audio.channels == 1, "Volcengine ASR should read channel count from WAV")
        try expect(audio.bits == 16, "Volcengine ASR should read bit depth from WAV")
        try expect(!audio.payload.isEmpty, "Volcengine ASR should extract PCM payload from WAV")
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
