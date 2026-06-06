import Foundation
import Security

protocol CredentialVault {
    func secret(for id: String) -> String?
    func setSecret(_ secret: String, for id: String)
    func removeSecret(for id: String)
}

final class KeychainCredentialVault: CredentialVault {
    private let service = "com.openclaw.remote.ai.credentials"

    func secret(for id: String) -> String? {
        var query = baseQuery(id)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    func setSecret(_ secret: String, for id: String) {
        let trimmed = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else {
            removeSecret(for: id)
            return
        }

        let query = baseQuery(id)
        let attributes: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            SecItemAdd(addQuery as CFDictionary, nil)
        }
    }

    func removeSecret(for id: String) {
        SecItemDelete(baseQuery(id) as CFDictionary)
    }

    private func baseQuery(_ id: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id
        ]
    }
}

let localLlmOpenAICompatibleCredentialId = "llm:openai-compatible"
let localLlmMiniMaxCredentialId = "llm:minimax"
let localLlmKimiCredentialId = "llm:kimi"
let localLlmClaudeCredentialId = "llm:claude"
let localLlmDoubaoCredentialId = "llm:doubao"
let localAsrOpenAICompatibleCredentialId = "asr:openai-compatible"
let localMiniMaxCredentialId = "tts:minimax"
