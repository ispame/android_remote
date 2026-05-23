import Foundation

@main
struct ProtocolFixtureContractTests {
    private static let legacyIdentityFields: Set<String> = [
        "device_id",
        "app_id",
        "client_id",
        "from_app_id",
        "target_app_id",
        "target_id",
        "from",
        "to",
    ]

    static func main() throws {
        let fixture = try loadCanonicalFixture()
        try testHTTPAuthFixture(fixture)
        try testWebSocketFramesDecodeAndEncode(fixture)
        print("ProtocolFixtureContractTests passed")
    }

    private static func testHTTPAuthFixture(_ fixture: ProtocolFixture) throws {
        try expect(
            fixture.http.smsRequest.request.phoneNumber == "+8613800138000",
            "SMS request phone_number should decode"
        )
        try expect(
            fixture.http.smsVerify.response.accountId == "acct_abc123",
            "SMS verify response account_id should decode"
        )
    }

    private static func testWebSocketFramesDecodeAndEncode(_ fixture: ProtocolFixture) throws {
        let expectedNames = [
            "app_register",
            "app_registered",
            "backend_register",
            "backend_registered",
            "pair_request",
            "pair_response",
            "message_text",
            "message_audio",
            "message_ack",
            "history_request",
            "history_response",
            "session_preempted",
        ]
        try expect(fixture.ws.map(\.name) == expectedNames, "fixture frame order should be stable")

        for entry in fixture.ws {
            try assertNoLegacyIdentityFields(entry.frame, path: entry.name)
            let frameData = try JSONEncoder.sorted.encode(entry.frame)
            let decodedJSON = try JSONDecoder().decode(JSONValue.self, from: frameData)
            try expect(decodedJSON == entry.frame, "\(entry.name) should round-trip through Codable")
            try assertFrameShape(entry)
        }
    }

    private static func assertFrameShape(_ entry: ProtocolFixture.NamedFrame) throws {
        let frameData = try JSONEncoder.sorted.encode(entry.frame)
        switch try entry.frame.requiredString("type") {
        case "app_register":
            let frame = try JSONDecoder().decode(AppRegisterFrame.self, from: frameData)
            try expect(frame.accessToken == "access_token_example", "app_register access_token should decode")
            try expect(frame.terminalLabel == "Alice iPhone", "app_register terminal_label should decode")
            try expect(frame.platform == "ios", "app_register platform should decode")

        case "app_registered":
            let frame = try JSONDecoder().decode(AppRegisteredFrame.self, from: frameData)
            try expect(frame.success, "app_registered success should decode")
            try expect(frame.accountId == "acct_abc123", "app_registered account_id should decode")
            try expect(frame.sessionPolicy == "single_active", "app_registered session_policy should decode")
            try expect(frame.pairedBackends.first?.backendId == "main", "paired backend should decode")

        case "backend_register":
            let frame = try JSONDecoder().decode(BackendRegisterFrame.self, from: frameData)
            try expect(frame.backendId == "main", "backend_register backend_id should decode")
            try expect(frame.backendLabel == "OpenClaw", "backend_register backend_label should decode")

        case "backend_registered":
            let frame = try JSONDecoder().decode(BackendRegisteredFrame.self, from: frameData)
            try expect(frame.success, "backend_registered success should decode")
            try expect(frame.backendId == "main", "backend_registered backend_id should decode")

        case "pair_request":
            let frame = try JSONDecoder().decode(PairRequestFrame.self, from: frameData)
            try expect(frame.accountId == "acct_abc123", "pair_request account_id should decode")
            try expect(frame.backendId == "main", "pair_request backend_id should decode")
            try expect(frame.terminalLabel == "Alice iPhone", "pair_request terminal_label should decode")

        case "pair_response":
            let frame = try JSONDecoder().decode(PairResponseFrame.self, from: frameData)
            try expect(frame.accountId == "acct_abc123", "pair_response account_id should decode")
            try expect(frame.backendId == "main", "pair_response backend_id should decode")
            try expect(frame.approved, "pair_response approved should decode")

        case "message":
            let frame = try JSONDecoder().decode(MessageFrame.self, from: frameData)
            try expect(frame.accountId == "acct_abc123", "\(entry.name) account_id should decode")
            try expect(frame.backendId == "main", "\(entry.name) backend_id should decode")
            try expect(!frame.messageId.isEmpty, "\(entry.name) message_id should decode")
            try expect(!frame.content.isEmpty, "\(entry.name) content should decode")
            if entry.name == "message_audio" {
                try expect(frame.audio?.sampleRate == 16_000, "message_audio sample_rate should decode")
                try expect(frame.audio?.channels == 1, "message_audio channels should decode")
                try expect(frame.asr?.mode == "backend", "message_audio asr mode should decode")
            }

        case "message_ack":
            let frame = try JSONDecoder().decode(MessageAckFrame.self, from: frameData)
            try expect(frame.messageId == "msg_123", "message_ack message_id should decode")

        case "history_request":
            let frame = try JSONDecoder().decode(HistoryRequestFrame.self, from: frameData)
            try expect(frame.accountId == "acct_abc123", "history_request account_id should decode")
            try expect(frame.backendId == "main", "history_request backend_id should decode")
            try expect(frame.sessionKey == "current", "history_request session_key should decode")
            try expect(frame.beforeTimestamp == "2026-05-21T15:00:00.000Z", "history_request before_timestamp should decode")
            try expect(frame.limit == 30, "history_request limit should decode")

        case "history_response":
            let frame = try JSONDecoder().decode(HistoryResponseFrame.self, from: frameData)
            try expect(frame.accountId == "acct_abc123", "history_response account_id should decode")
            try expect(frame.backendId == "main", "history_response backend_id should decode")
            try expect(frame.messages.count == 2, "history_response messages should decode")
            try expect(frame.hasMore, "history_response has_more should decode")
            try expect(frame.error == nil, "history_response error null should decode")

        case "session_preempted":
            let frame = try JSONDecoder().decode(SessionPreemptedFrame.self, from: frameData)
            try expect(frame.reason == "replaced_by_new_terminal", "session_preempted reason should decode")
            try expect(frame.replacementTerminalLabel == "Alice iPad", "session_preempted replacement_terminal_label should decode")

        default:
            throw TestFailure("Unhandled fixture frame \(entry.name)")
        }
    }

    private static func assertNoLegacyIdentityFields(_ value: JSONValue, path: String) throws {
        switch value {
        case .object(let object):
            for (key, child) in object {
                try expect(!legacyIdentityFields.contains(key), "legacy identity field \(path).\(key) must not appear in V2 fixture")
                try assertNoLegacyIdentityFields(child, path: "\(path).\(key)")
            }
        case .array(let array):
            for (index, child) in array.enumerated() {
                try assertNoLegacyIdentityFields(child, path: "\(path)[\(index)]")
            }
        case .null, .bool, .number, .string:
            break
        }
    }

    private static func loadCanonicalFixture() throws -> ProtocolFixture {
        let data = try Data(contentsOf: try canonicalFixtureURL())
        return try JSONDecoder().decode(ProtocolFixture.self, from: data)
    }

    private static func canonicalFixtureURL() throws -> URL {
        let env = ProcessInfo.processInfo.environment["OPENCLAW_PROTOCOL_FIXTURE"]
        if let env, !env.isEmpty {
            let url = URL(fileURLWithPath: env)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }

        let fixturePath = "packages/protocol/fixtures/account-scoped-session-v2.json"
        let starts = [
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
            URL(fileURLWithPath: #filePath),
        ]

        for start in starts {
            var dir = start.hasDirectoryPath ? start : start.deletingLastPathComponent()
            while true {
                let candidates = [
                    dir.appendingPathComponent("../android-remote-gateway/\(fixturePath)").standardizedFileURL,
                    dir.appendingPathComponent("android-remote-gateway/\(fixturePath)").standardizedFileURL,
                    dir.appendingPathComponent(fixturePath).standardizedFileURL,
                ]
                if let match = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) {
                    return match
                }
                let parent = dir.deletingLastPathComponent()
                if parent.path == dir.path { break }
                dir = parent
            }
        }

        throw TestFailure("Cannot find account-scoped-session-v2.json. Set OPENCLAW_PROTOCOL_FIXTURE or keep android_remote next to android-remote-gateway.")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() {
            throw TestFailure(message)
        }
    }
}

private struct ProtocolFixture: Decodable {
    let http: HTTP
    let ws: [NamedFrame]

    struct HTTP: Decodable {
        let smsRequest: SMSRequest
        let smsVerify: SMSVerify

        enum CodingKeys: String, CodingKey {
            case smsRequest = "sms_request"
            case smsVerify = "sms_verify"
        }
    }

    struct SMSRequest: Decodable {
        let request: SMSRequestBody
        let response: SMSRequestResponse
    }

    struct SMSRequestBody: Decodable {
        let phoneNumber: String
        let purpose: String

        enum CodingKeys: String, CodingKey {
            case phoneNumber = "phone_number"
            case purpose
        }
    }

    struct SMSRequestResponse: Decodable {
        let requestId: String
        let retryAfterSeconds: Int

        enum CodingKeys: String, CodingKey {
            case requestId = "request_id"
            case retryAfterSeconds = "retry_after_seconds"
        }
    }

    struct SMSVerify: Decodable {
        let request: SMSVerifyBody
        let response: TokenBundle
    }

    struct SMSVerifyBody: Decodable {
        let phoneNumber: String
        let code: String
        let terminalLabel: String
        let platform: String

        enum CodingKeys: String, CodingKey {
            case phoneNumber = "phone_number"
            case code
            case terminalLabel = "terminal_label"
            case platform
        }
    }

    struct TokenBundle: Decodable {
        let accountId: String
        let accessToken: String
        let refreshToken: String
        let accessExpiresAt: String
        let refreshExpiresAt: String

        enum CodingKeys: String, CodingKey {
            case accountId = "account_id"
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case accessExpiresAt = "access_expires_at"
            case refreshExpiresAt = "refresh_expires_at"
        }
    }

    struct NamedFrame: Decodable {
        let name: String
        let frame: JSONValue
    }
}

private struct AppRegisterFrame: Codable, Equatable {
    let type: String
    let accessToken: String
    let terminalLabel: String
    let platform: String
    let appVersion: String?

    enum CodingKeys: String, CodingKey {
        case type
        case accessToken = "access_token"
        case terminalLabel = "terminal_label"
        case platform
        case appVersion = "app_version"
    }
}

private struct AppRegisteredFrame: Codable, Equatable {
    let type: String
    let success: Bool
    let accountId: String
    let terminalLabel: String
    let sessionPolicy: String
    let pairedBackends: [PairedBackend]
    let selectedBackendId: String?

    enum CodingKeys: String, CodingKey {
        case type
        case success
        case accountId = "account_id"
        case terminalLabel = "terminal_label"
        case sessionPolicy = "session_policy"
        case pairedBackends = "paired_backends"
        case selectedBackendId = "selected_backend_id"
    }
}

private struct PairedBackend: Codable, Equatable {
    let backendId: String
    let backendLabel: String
    let pairedAt: String
    let connected: Bool

    enum CodingKeys: String, CodingKey {
        case backendId = "backend_id"
        case backendLabel = "backend_label"
        case pairedAt = "paired_at"
        case connected
    }
}

private struct BackendRegisterFrame: Codable, Equatable {
    let type: String
    let backendId: String
    let backendToken: String?
    let backendLabel: String
    let resumeId: String?

    enum CodingKeys: String, CodingKey {
        case type
        case backendId = "backend_id"
        case backendToken = "backend_token"
        case backendLabel = "backend_label"
        case resumeId = "resume_id"
    }
}

private struct BackendRegisteredFrame: Codable, Equatable {
    let type: String
    let success: Bool
    let backendId: String
    let backendLabel: String
    let resumeId: String?
    let token: String?

    enum CodingKeys: String, CodingKey {
        case type
        case success
        case backendId = "backend_id"
        case backendLabel = "backend_label"
        case resumeId = "resume_id"
        case token
    }
}

private struct PairRequestFrame: Codable, Equatable {
    let type: String
    let accountId: String
    let backendId: String
    let terminalLabel: String
    let appMetadata: [String: JSONValue]?

    enum CodingKeys: String, CodingKey {
        case type
        case accountId = "account_id"
        case backendId = "backend_id"
        case terminalLabel = "terminal_label"
        case appMetadata = "app_metadata"
    }
}

private struct PairResponseFrame: Codable, Equatable {
    let type: String
    let accountId: String
    let backendId: String
    let approved: Bool
    let backendLabel: String?

    enum CodingKeys: String, CodingKey {
        case type
        case accountId = "account_id"
        case backendId = "backend_id"
        case approved
        case backendLabel = "backend_label"
    }
}

private struct MessageFrame: Codable, Equatable {
    let type: String
    let accountId: String
    let backendId: String
    let messageId: String
    let clientMessageId: String?
    let content: String
    let contentType: String
    let timestamp: String
    let audio: AudioPayload?
    let asr: AsrPayload?

    enum CodingKeys: String, CodingKey {
        case type
        case accountId = "account_id"
        case backendId = "backend_id"
        case messageId = "message_id"
        case clientMessageId = "client_message_id"
        case content
        case contentType = "content_type"
        case timestamp
        case audio
        case asr
    }
}

private struct AudioPayload: Codable, Equatable {
    let format: String
    let codec: String
    let sampleRate: Int
    let channels: Int

    enum CodingKeys: String, CodingKey {
        case format
        case codec
        case sampleRate = "sample_rate"
        case channels
    }
}

private struct AsrPayload: Codable, Equatable {
    let mode: String
    let profileId: String?

    enum CodingKeys: String, CodingKey {
        case mode
        case profileId = "profile_id"
    }
}

private struct MessageAckFrame: Codable, Equatable {
    let type: String
    let messageId: String

    enum CodingKeys: String, CodingKey {
        case type
        case messageId = "message_id"
    }
}

private struct HistoryRequestFrame: Codable, Equatable {
    let type: String
    let accountId: String
    let backendId: String
    let sessionKey: String
    let beforeTimestamp: String?
    let limit: Int

    enum CodingKeys: String, CodingKey {
        case type
        case accountId = "account_id"
        case backendId = "backend_id"
        case sessionKey = "session_key"
        case beforeTimestamp = "before_timestamp"
        case limit
    }
}

private struct HistoryResponseFrame: Codable, Equatable {
    let type: String
    let accountId: String
    let backendId: String
    let sessionKey: String
    let messages: [HistoryMessage]
    let hasMore: Bool
    let error: String?

    enum CodingKeys: String, CodingKey {
        case type
        case accountId = "account_id"
        case backendId = "backend_id"
        case sessionKey = "session_key"
        case messages
        case hasMore = "has_more"
        case error
    }
}

private struct HistoryMessage: Codable, Equatable {
    let messageId: String
    let role: String
    let content: String
    let contentType: String
    let timestamp: String

    enum CodingKeys: String, CodingKey {
        case messageId = "message_id"
        case role
        case content
        case contentType = "content_type"
        case timestamp
    }
}

private struct SessionPreemptedFrame: Codable, Equatable {
    let type: String
    let reason: String
    let replacedAt: String
    let replacementTerminalLabel: String?

    enum CodingKeys: String, CodingKey {
        case type
        case reason
        case replacedAt = "replaced_at"
        case replacementTerminalLabel = "replacement_terminal_label"
    }
}

private enum JSONValue: Codable, Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case .bool(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        }
    }

    func requiredString(_ key: String) throws -> String {
        guard case .object(let object) = self,
              case .string(let value)? = object[key],
              !value.isEmpty else {
            throw TestFailure("missing string field \(key)")
        }
        return value
    }
}

private extension JSONEncoder {
    static var sorted: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

private struct TestFailure: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}
