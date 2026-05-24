import Foundation

enum AuthRecoveryAction {
    case none
    case refreshSession
    case requireLogin
}

func authRecoveryAction(forWebSocketErrorCode code: String) -> AuthRecoveryAction {
    switch code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() {
    case "INVALID_ACCESS_TOKEN",
         "EXPIRED_ACCESS_TOKEN",
         "ACCESS_TOKEN_EXPIRED":
        return .refreshSession
    case "REFRESH_TOKEN_EXPIRED",
         "INVALID_REFRESH_TOKEN",
         "ACCESS_TOKEN_REVOKED":
        return .requireLogin
    default:
        return .none
    }
}

func isAccessTokenRefreshableError(_ code: String) -> Bool {
    authRecoveryAction(forWebSocketErrorCode: code) == .refreshSession
}

func refreshFailureRequiresLogin(_ message: String) -> Bool {
    let normalized = message.uppercased()
    return normalized.contains("REFRESH_TOKEN_EXPIRED") ||
        normalized.contains("INVALID_REFRESH_TOKEN") ||
        normalized.contains("ACCESS_TOKEN_REVOKED")
}

func shouldRefreshAccessToken(
    accessExpiresAt: String,
    now: Date = Date(),
    skew: TimeInterval = 2 * 60
) -> Bool {
    guard let expiresAt = parseAuthIsoDate(accessExpiresAt) else { return true }
    return expiresAt.timeIntervalSince(now) <= skew
}

func tokenRefreshDelayNanoseconds(accessExpiresAt: String) -> UInt64 {
    guard let expiresAt = parseAuthIsoDate(accessExpiresAt) else { return 0 }
    let refreshAt = expiresAt.addingTimeInterval(-2 * 60)
    let seconds = max(refreshAt.timeIntervalSinceNow, 0)
    return UInt64(seconds * 1_000_000_000)
}

private func parseAuthIsoDate(_ value: String) -> Date? {
    guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
    let withFractional = ISO8601DateFormatter()
    withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = withFractional.date(from: value) {
        return date
    }
    return ISO8601DateFormatter().date(from: value)
}
