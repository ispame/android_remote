import Foundation

@main
struct AiServiceByokTests {
    static func main() throws {
        try testAiServiceChoicePersistsByokMetadataWithoutSecrets()
        try testAgentOverrideResolvesByokChoices()
        try testOpenAICompatibleChatRequestShape()
        try testOpenAICompatibleAsrRequestShape()
        try testSilentWavFixtureIsValidForAsrValidation()
        print("AiServiceByokTests passed")
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
}

private struct TestFailure: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}
