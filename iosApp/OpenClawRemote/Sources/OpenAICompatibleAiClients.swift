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

struct VolcengineAsrCredential: Equatable {
    var appKey: String
    var accessKey: String
}

enum VolcengineAsrClientError: Error, LocalizedError {
    case invalidCredential
    case invalidEndpoint(String)
    case missingResourceId
    case invalidAudio(String)
    case unsupportedCompression
    case providerError(String)
    case missingTranscript

    var errorDescription: String? {
        switch self {
        case .invalidCredential:
            return "火山云 ASR Key 需填写为 appKey:accessKey"
        case .invalidEndpoint(let value):
            return "无效的火山云 ASR endpoint：\(value)"
        case .missingResourceId:
            return "请在 Model 中填写火山云 Resource ID"
        case .invalidAudio(let message):
            return message
        case .unsupportedCompression:
            return "火山云 ASR 返回了当前客户端不支持的压缩响应"
        case .providerError(let message):
            return message
        case .missingTranscript:
            return "火山云 ASR 响应缺少识别文本"
        }
    }
}

final class VolcengineAsrClient {
    struct PcmAudio: Equatable {
        var payload: Data
        var sampleRate: Int
        var channels: Int
        var bits: Int
    }

    private struct DecodedFrame {
        var messageType: Int
        var flags: Int
        var body: Any
    }

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    static func parseCredential(_ value: String) throws -> VolcengineAsrCredential {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let data = trimmed.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let appKey = stringValue(object["appKey"]) ?? stringValue(object["app_key"])
            let accessKey = stringValue(object["accessKey"]) ?? stringValue(object["access_key"]) ?? stringValue(object["token"])
            if let appKey, let accessKey {
                return VolcengineAsrCredential(appKey: appKey, accessKey: accessKey)
            }
        }

        for separator in ["\n", ":", "|", ","] {
            let parts = trimmed
                .components(separatedBy: separator)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if parts.count == 2 {
                return VolcengineAsrCredential(appKey: parts[0], accessKey: parts[1])
            }
        }
        throw VolcengineAsrClientError.invalidCredential
    }

    static func makeWebSocketRequest(
        endpoint: String,
        credential: VolcengineAsrCredential,
        resourceId: String,
        connectId: String = UUID().uuidString
    ) throws -> URLRequest {
        let trimmedEndpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmedEndpoint), url.scheme == "wss" || url.scheme == "ws" else {
            throw VolcengineAsrClientError.invalidEndpoint(endpoint)
        }
        let trimmedResourceId = resourceId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedResourceId.isEmpty else { throw VolcengineAsrClientError.missingResourceId }

        var request = URLRequest(url: url)
        request.setValue(credential.appKey, forHTTPHeaderField: "X-Api-App-Key")
        request.setValue(credential.accessKey, forHTTPHeaderField: "X-Api-Access-Key")
        request.setValue(trimmedResourceId, forHTTPHeaderField: "X-Api-Resource-Id")
        request.setValue(connectId, forHTTPHeaderField: "X-Api-Connect-Id")
        return request
    }

    func testTranscription(endpoint: String, credential: String, resourceId: String) async throws -> String {
        try await transcribe(
            endpoint: endpoint,
            credential: credential,
            resourceId: resourceId,
            audioData: OpenAICompatibleAsrClient.silentWav16kMono(durationMilliseconds: 200)
        )
    }

    func transcribe(endpoint: String, credential: String, resourceId: String, audioData: Data) async throws -> String {
        let parsedCredential = try Self.parseCredential(credential)
        let requestId = UUID().uuidString
        let request = try Self.makeWebSocketRequest(
            endpoint: endpoint,
            credential: parsedCredential,
            resourceId: resourceId,
            connectId: requestId
        )
        let audio = try Self.extractPcmAudio(from: audioData)
        let task = session.webSocketTask(with: request)
        task.resume()
        defer { task.cancel(with: .normalClosure, reason: nil) }

        try await task.send(.data(Self.startFrame(requestId: requestId, audio: audio)))
        let chunks = Self.audioChunks(audio.payload)
        for (index, chunk) in chunks.enumerated() {
            let isLast = index == chunks.count - 1
            try await task.send(.data(Self.encodeFrame(messageType: 2, flags: isLast ? 2 : 0, payload: chunk, serialization: 0)))
        }

        var latestTranscript = ""
        while true {
            let message = try await task.receive()
            let data: Data
            switch message {
            case .data(let payload):
                data = payload
            case .string(let text):
                data = Data(text.utf8)
            @unknown default:
                continue
            }
            let decoded = try Self.decodeFrame(data)
            if decoded.messageType == 0x0f {
                throw VolcengineAsrClientError.providerError(Self.describeError(decoded.body))
            }
            let text = Self.extractTranscript(decoded.body).trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { latestTranscript = text }
            let isFinal = (decoded.flags & 0x02) != 0
            if isFinal {
                guard !latestTranscript.isEmpty else { throw VolcengineAsrClientError.missingTranscript }
                return latestTranscript
            }
        }
    }

    static func extractPcmAudio(from audioData: Data) throws -> PcmAudio {
        guard audioData.count >= 12,
              String(data: audioData.subdata(in: 0..<4), encoding: .ascii) == "RIFF",
              String(data: audioData.subdata(in: 8..<12), encoding: .ascii) == "WAVE" else {
            return PcmAudio(payload: audioData, sampleRate: 16_000, channels: 1, bits: 16)
        }

        var offset = 12
        var audioFormat: UInt16?
        var channels: UInt16?
        var sampleRate: UInt32?
        var bits: UInt16?
        var payload: Data?

        while offset + 8 <= audioData.count {
            let chunkId = String(data: audioData.subdata(in: offset..<(offset + 4)), encoding: .ascii) ?? ""
            let chunkSize = Int(audioData.uint32LE(at: offset + 4))
            let chunkStart = offset + 8
            let chunkEnd = min(chunkStart + chunkSize, audioData.count)
            if chunkId == "fmt ", chunkSize >= 16, chunkEnd <= audioData.count {
                audioFormat = audioData.uint16LE(at: chunkStart)
                channels = audioData.uint16LE(at: chunkStart + 2)
                sampleRate = audioData.uint32LE(at: chunkStart + 4)
                bits = audioData.uint16LE(at: chunkStart + 14)
            } else if chunkId == "data", chunkEnd <= audioData.count {
                payload = audioData.subdata(in: chunkStart..<chunkEnd)
            }
            offset = chunkStart + chunkSize + (chunkSize % 2)
        }

        guard let payload, !payload.isEmpty else {
            throw VolcengineAsrClientError.invalidAudio("WAV 音频没有可识别的 PCM 数据")
        }
        guard audioFormat == 1, bits == 16 else {
            throw VolcengineAsrClientError.invalidAudio("火山云 ASR 需要 16-bit PCM WAV 音频")
        }
        return PcmAudio(
            payload: payload,
            sampleRate: Int(sampleRate ?? 16_000),
            channels: Int(channels ?? 1),
            bits: Int(bits ?? 16)
        )
    }

    private static func startFrame(requestId: String, audio: PcmAudio) throws -> Data {
        let body: [String: Any] = [
            "user": ["uid": requestId],
            "audio": [
                "format": "pcm",
                "sample_rate": audio.sampleRate,
                "bits": audio.bits,
                "channel": audio.channels
            ],
            "request": [
                "reqid": requestId,
                "sequence": 1,
                "show_utterances": true,
                "enable_itn": true,
                "result_type": "full"
            ]
        ]
        let payload = try JSONSerialization.data(withJSONObject: body)
        return encodeFrame(messageType: 1, flags: 0, payload: payload, serialization: 1)
    }

    private static func audioChunks(_ audio: Data, chunkSize: Int = 6400) -> [Data] {
        guard !audio.isEmpty else { return [Data()] }
        var chunks: [Data] = []
        var offset = 0
        while offset < audio.count {
            let end = min(offset + chunkSize, audio.count)
            chunks.append(audio.subdata(in: offset..<end))
            offset = end
        }
        return chunks
    }

    private static func encodeFrame(messageType: Int, flags: Int, payload: Data, serialization: Int) -> Data {
        var frame = Data()
        frame.append(0x11)
        frame.append(UInt8((messageType << 4) | flags))
        frame.append(UInt8((serialization << 4) | 0x00))
        frame.append(0x00)
        frame.appendUInt32BE(UInt32(payload.count))
        frame.append(payload)
        return frame
    }

    private static func decodeFrame(_ frame: Data) throws -> DecodedFrame {
        guard frame.count >= 4 else {
            return DecodedFrame(messageType: 0, flags: 0, body: [:])
        }
        let headerSize = Int(frame[frame.startIndex] & 0x0f) * 4
        let messageType = Int(frame[frame.index(frame.startIndex, offsetBy: 1)] >> 4)
        let flags = Int(frame[frame.index(frame.startIndex, offsetBy: 1)] & 0x0f)
        let compression = Int(frame[frame.index(frame.startIndex, offsetBy: 2)] & 0x0f)
        guard compression == 0 else { throw VolcengineAsrClientError.unsupportedCompression }

        var offset = headerSize
        if flags != 0, frame.count >= offset + 4 {
            offset += 4
        }
        if messageType == 0x0f, frame.count >= offset + 4 {
            offset += 4
        }
        guard frame.count >= offset + 4 else {
            return DecodedFrame(messageType: messageType, flags: flags, body: [:])
        }
        let payloadSize = Int(frame.uint32BE(at: offset))
        offset += 4
        let end = min(offset + payloadSize, frame.count)
        let payload = frame.subdata(in: offset..<end)
        if let object = try? JSONSerialization.jsonObject(with: payload) {
            return DecodedFrame(messageType: messageType, flags: flags, body: object)
        }
        return DecodedFrame(
            messageType: messageType,
            flags: flags,
            body: String(data: payload, encoding: .utf8) ?? ""
        )
    }

    private static func extractTranscript(_ value: Any) -> String {
        if let text = value as? String {
            return text
        }
        if let array = value as? [Any] {
            return array.map(extractTranscript).filter { !$0.isEmpty }.joined(separator: "\n")
        }
        guard let dictionary = value as? [String: Any] else { return "" }
        if let body = dictionary["body"] {
            let text = extractTranscript(body)
            if !text.isEmpty { return text }
        }
        for key in ["text", "utterance", "transcript"] {
            if let text = dictionary[key] as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return text
            }
        }
        for key in ["result", "payload", "data", "results", "utterances"] {
            if let nested = dictionary[key] {
                let text = extractTranscript(nested)
                if !text.isEmpty { return text }
            }
        }
        return ""
    }

    private static func describeError(_ value: Any) -> String {
        if let text = value as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return text
        }
        if let dictionary = value as? [String: Any] {
            if let message = dictionary["message"] as? String, !message.isEmpty { return message }
            if let error = dictionary["error"] as? String, !error.isEmpty { return error }
            if let data = try? JSONSerialization.data(withJSONObject: dictionary),
               let text = String(data: data, encoding: .utf8) {
                return text
            }
        }
        return "火山云 ASR 返回错误"
    }

    private static func stringValue(_ value: Any?) -> String? {
        let text = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? nil : text
    }
}

enum ByokAsrTranscriptionClient {
    static func transcribe(choice: AiServiceChoice, apiKey: String, audioData: Data) async throws -> String {
        if choice.providerId == "volcengine" || choice.credentialId == localAsrVolcengineCredentialId {
            return try await VolcengineAsrClient().transcribe(
                endpoint: choice.baseUrl,
                credential: apiKey,
                resourceId: choice.model,
                audioData: audioData
            )
        }
        return try await OpenAICompatibleAsrClient().transcribe(
            baseUrl: choice.baseUrl,
            apiKey: apiKey,
            model: choice.model,
            audioData: audioData
        )
    }

    static func testTranscription(providerId: String, baseUrl: String, apiKey: String, model: String) async throws -> String {
        if providerId == "volcengine" {
            return try await VolcengineAsrClient().testTranscription(
                endpoint: baseUrl,
                credential: apiKey,
                resourceId: model
            )
        }
        return try await OpenAICompatibleAsrClient().testTranscription(
            baseUrl: baseUrl,
            apiKey: apiKey,
            model: model
        )
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

    mutating func appendUInt32BE(_ value: UInt32) {
        var bigEndian = value.bigEndian
        append(Data(bytes: &bigEndian, count: MemoryLayout<UInt32>.size))
    }

    func uint16LE(at offset: Int) -> UInt16 {
        guard count >= offset + 2 else { return 0 }
        return UInt16(self[index(startIndex, offsetBy: offset)])
            | (UInt16(self[index(startIndex, offsetBy: offset + 1)]) << 8)
    }

    func uint32LE(at offset: Int) -> UInt32 {
        guard count >= offset + 4 else { return 0 }
        return UInt32(self[index(startIndex, offsetBy: offset)])
            | (UInt32(self[index(startIndex, offsetBy: offset + 1)]) << 8)
            | (UInt32(self[index(startIndex, offsetBy: offset + 2)]) << 16)
            | (UInt32(self[index(startIndex, offsetBy: offset + 3)]) << 24)
    }

    func uint32BE(at offset: Int) -> UInt32 {
        guard count >= offset + 4 else { return 0 }
        return (UInt32(self[index(startIndex, offsetBy: offset)]) << 24)
            | (UInt32(self[index(startIndex, offsetBy: offset + 1)]) << 16)
            | (UInt32(self[index(startIndex, offsetBy: offset + 2)]) << 8)
            | UInt32(self[index(startIndex, offsetBy: offset + 3)])
    }
}
