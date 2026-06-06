import Foundation

struct OpenAICompatibleChatMessage: Codable, Equatable {
    var role: String
    var content: String
}

enum OpenAICompatibleAiClientError: Error, LocalizedError {
    case invalidBaseUrl(String)
    case missingApiKey
    case missingModel
    case providerError(statusCode: Int, body: String)
    case missingResponseText

    var errorDescription: String? {
        switch self {
        case .invalidBaseUrl(let value):
            return "无效的 Base URL：\(value)"
        case .missingApiKey:
            return "请先保存 API Key"
        case .missingModel:
            return "请先填写模型名称"
        case .providerError(let statusCode, let body):
            return "供应商请求失败：\(statusCode) \(body)"
        case .missingResponseText:
            return "供应商响应缺少文本结果"
        }
    }
}

final class OpenAICompatibleChatClient {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    static func makeRequest(
        baseUrl: String,
        apiKey: String,
        model: String,
        messages: [OpenAICompatibleChatMessage]
    ) throws -> URLRequest {
        let trimmedApiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedApiKey.isEmpty else { throw OpenAICompatibleAiClientError.missingApiKey }
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedModel.isEmpty else { throw OpenAICompatibleAiClientError.missingModel }

        var request = URLRequest(url: try endpoint(baseUrl: baseUrl, path: "chat/completions"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(trimmedApiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": trimmedModel,
            "messages": messages.map { ["role": $0.role, "content": $0.content] },
            "stream": false
        ])
        return request
    }

    func testChat(baseUrl: String, apiKey: String, model: String) async throws -> String {
        try await chat(
            baseUrl: baseUrl,
            apiKey: apiKey,
            model: model,
            messages: [OpenAICompatibleChatMessage(role: "user", content: "ping")]
        )
    }

    func chat(baseUrl: String, apiKey: String, model: String, messages: [OpenAICompatibleChatMessage]) async throws -> String {
        let request = try Self.makeRequest(
            baseUrl: baseUrl,
            apiKey: apiKey,
            model: model,
            messages: messages
        )
        let (data, response) = try await session.data(for: request)
        try Self.validate(response: response, data: data)
        return try Self.parseAssistantContent(data)
    }

    static func parseAssistantContent(_ data: Data) throws -> String {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let dictionary = object as? [String: Any],
              let choices = dictionary["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String,
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OpenAICompatibleAiClientError.missingResponseText
        }
        return content
    }

    fileprivate static func endpoint(baseUrl: String, path: String) throws -> URL {
        let trimmed = baseUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw OpenAICompatibleAiClientError.invalidBaseUrl(baseUrl) }
        let normalized = trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed
        guard let base = URL(string: normalized) else {
            throw OpenAICompatibleAiClientError.invalidBaseUrl(baseUrl)
        }
        return base.appendingPathComponent(path)
    }

    fileprivate static func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw OpenAICompatibleAiClientError.providerError(statusCode: http.statusCode, body: body)
        }
    }
}

final class AnthropicChatClient {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    static func makeRequest(
        baseUrl: String,
        apiKey: String,
        model: String,
        messages: [OpenAICompatibleChatMessage]
    ) throws -> URLRequest {
        let trimmedApiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedApiKey.isEmpty else { throw OpenAICompatibleAiClientError.missingApiKey }
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedModel.isEmpty else { throw OpenAICompatibleAiClientError.missingModel }

        var request = URLRequest(url: try OpenAICompatibleChatClient.endpoint(baseUrl: baseUrl, path: "messages"))
        request.httpMethod = "POST"
        request.setValue(trimmedApiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": trimmedModel,
            "max_tokens": 64,
            "messages": messages
                .filter { $0.role != "system" }
                .map { ["role": $0.role == "assistant" ? "assistant" : "user", "content": $0.content] }
        ])
        return request
    }

    func testChat(baseUrl: String, apiKey: String, model: String) async throws -> String {
        try await chat(
            baseUrl: baseUrl,
            apiKey: apiKey,
            model: model,
            messages: [OpenAICompatibleChatMessage(role: "user", content: "ping")]
        )
    }

    func chat(baseUrl: String, apiKey: String, model: String, messages: [OpenAICompatibleChatMessage]) async throws -> String {
        let request = try Self.makeRequest(
            baseUrl: baseUrl,
            apiKey: apiKey,
            model: model,
            messages: messages
        )
        let (data, response) = try await session.data(for: request)
        try OpenAICompatibleChatClient.validate(response: response, data: data)
        return try Self.parseAssistantContent(data)
    }

    static func parseAssistantContent(_ data: Data) throws -> String {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let dictionary = object as? [String: Any],
              let content = dictionary["content"] as? [[String: Any]] else {
            throw OpenAICompatibleAiClientError.missingResponseText
        }
        let text = content
            .compactMap { item -> String? in
                guard (item["type"] as? String) == "text" else { return nil }
                return item["text"] as? String
            }
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw OpenAICompatibleAiClientError.missingResponseText }
        return text
    }
}

final class OpenAICompatibleAsrClient {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    static func makeTranscriptionRequest(
        baseUrl: String,
        apiKey: String,
        model: String,
        fileName: String,
        audioData: Data,
        boundary: String = "boson-ai-\(UUID().uuidString)"
    ) throws -> URLRequest {
        let trimmedApiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedApiKey.isEmpty else { throw OpenAICompatibleAiClientError.missingApiKey }
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedModel.isEmpty else { throw OpenAICompatibleAiClientError.missingModel }

        var request = URLRequest(url: try OpenAICompatibleChatClient.endpoint(baseUrl: baseUrl, path: "audio/transcriptions"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(trimmedApiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = multipartBody(
            boundary: boundary,
            model: trimmedModel,
            fileName: fileName,
            audioData: audioData
        )
        return request
    }

    func transcribe(baseUrl: String, apiKey: String, model: String, audioData: Data, fileName: String = "audio.wav") async throws -> String {
        let request = try Self.makeTranscriptionRequest(
            baseUrl: baseUrl,
            apiKey: apiKey,
            model: model,
            fileName: fileName,
            audioData: audioData
        )
        let (data, response) = try await session.data(for: request)
        try OpenAICompatibleChatClient.validate(response: response, data: data)
        return try Self.parseTranscript(data)
    }

    func testTranscription(baseUrl: String, apiKey: String, model: String) async throws -> String {
        try await transcribe(
            baseUrl: baseUrl,
            apiKey: apiKey,
            model: model,
            audioData: Self.silentWav16kMono(durationMilliseconds: 200),
            fileName: "boson-asr-test.wav"
        )
    }

    static func parseTranscript(_ data: Data) throws -> String {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let dictionary = object as? [String: Any],
              let text = dictionary["text"] as? String else {
            throw OpenAICompatibleAiClientError.missingResponseText
        }
        return text
    }

    static func silentWav16kMono(durationMilliseconds: Int) -> Data {
        let sampleRate = 16_000
        let duration = max(durationMilliseconds, 1)
        let sampleCount = max(sampleRate * duration / 1000, 1)
        let pcmByteCount = sampleCount * 2
        var data = Data()
        data.appendAscii("RIFF")
        data.appendUInt32LE(UInt32(36 + pcmByteCount))
        data.appendAscii("WAVE")
        data.appendAscii("fmt ")
        data.appendUInt32LE(16)
        data.appendUInt16LE(1)
        data.appendUInt16LE(1)
        data.appendUInt32LE(UInt32(sampleRate))
        data.appendUInt32LE(UInt32(sampleRate * 2))
        data.appendUInt16LE(2)
        data.appendUInt16LE(16)
        data.appendAscii("data")
        data.appendUInt32LE(UInt32(pcmByteCount))
        data.append(Data(repeating: 0, count: pcmByteCount))
        return data
    }

    private static func multipartBody(boundary: String, model: String, fileName: String, audioData: Data) -> Data {
        var body = Data()
        body.appendAscii("--\(boundary)\r\n")
        body.appendAscii("Content-Disposition: form-data; name=\"model\"\r\n\r\n")
        body.appendAscii("\(model)\r\n")
        body.appendAscii("--\(boundary)\r\n")
        body.appendAscii("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n")
        body.appendAscii("Content-Type: audio/wav\r\n\r\n")
        body.append(audioData)
        body.appendAscii("\r\n--\(boundary)--\r\n")
        return body
    }
}

private extension Data {
    mutating func appendAscii(_ value: String) {
        append(value.data(using: .utf8) ?? Data())
    }

    mutating func appendUInt16LE(_ value: UInt16) {
        var littleEndian = value.littleEndian
        append(Data(bytes: &littleEndian, count: MemoryLayout<UInt16>.size))
    }

    mutating func appendUInt32LE(_ value: UInt32) {
        var littleEndian = value.littleEndian
        append(Data(bytes: &littleEndian, count: MemoryLayout<UInt32>.size))
    }
}
