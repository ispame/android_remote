import Foundation

@main
struct AuthRecoveryPolicyTests {
    static func main() throws {
        try testAccessTokenErrorsRequestSilentRefresh()
        try testRefreshTokenFailuresRequireLogin()
        print("AuthRecoveryPolicyTests passed")
    }

    private static func testAccessTokenErrorsRequestSilentRefresh() throws {
        try expect(authRecoveryAction(forWebSocketErrorCode: "ACCESS_TOKEN_EXPIRED") == .refreshSession, "expired access token should refresh silently")
        try expect(authRecoveryAction(forWebSocketErrorCode: "expired_access_token") == .refreshSession, "case-insensitive expired access token should refresh silently")
        try expect(authRecoveryAction(forWebSocketErrorCode: "INVALID_ACCESS_TOKEN") == .refreshSession, "invalid access token should try refresh once")
        try expect(authRecoveryAction(forWebSocketErrorCode: "ACCESS_TOKEN_REVOKED") == .requireLogin, "revoked token should require login")
        try expect(authRecoveryAction(forWebSocketErrorCode: "TARGET_NOT_FOUND") == .none, "non-auth router errors should not refresh auth")
    }

    private static func testRefreshTokenFailuresRequireLogin() throws {
        try expect(refreshFailureRequiresLogin("HTTP 401: REFRESH_TOKEN_EXPIRED: Refresh token expired"), "expired refresh token should require login")
        try expect(refreshFailureRequiresLogin("HTTP 401: INVALID_REFRESH_TOKEN: Refresh token not found"), "invalid refresh token should require login")
        try expect(refreshFailureRequiresLogin("HTTP 401: ACCESS_TOKEN_REVOKED: Access token revoked"), "revoked token should require login")
        try expect(!refreshFailureRequiresLogin("network timeout"), "transient refresh failure should not be classified as a credential loss")
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
