import Foundation

@main
struct CodexAgentSourceContractTests {
    static func main() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let models = try read(root, "iosApp/OpenClawRemote/Sources/Models.swift")
        let agentsTab = try read(root, "iosApp/OpenClawRemote/Sources/Views/AgentsTabView.swift")
        let codexViews = try read(root, "iosApp/OpenClawRemote/Sources/Views/CodexSessionViews.swift")
        let websocket = try read(root, "iosApp/OpenClawRemote/Sources/WebSocketManager.swift")
        let settingsManager = try read(root, "iosApp/OpenClawRemote/Sources/SettingsManager.swift")
        let app = try read(root, "iosApp/OpenClawRemote/Sources/OpenClawRemoteApp.swift")

        try expect(models.contains("case codex"), "AgentPlatform should decode the codex platform")
        try expect(models.contains("case .codex: return \"Codex\""), "Codex should have a Codex label")
        try expect(models.contains("case .codex: return false"), "Codex should disable audio in v1")
        try expect(models.contains("case .codex: return \"circle.hexagongrid.fill\""), "Codex should use the requested SF Symbol")

        try expect(agentsTab.contains("CodexSessionListScreen("), "Codex profiles should route to the session list")
        try expect(agentsTab.contains("profile.platform == .codex"), "Agent list should branch Codex navigation by platform")
        try expect(codexViews.contains("CodexSessionChatScreen("), "Session list should navigate into Codex session chat")

        for frameType in [
            "agent_session_list_request",
            "agent_session_create_request",
            "agent_session_archive_request",
            "agent_session_unarchive_request",
            "agent_session_list_response",
            "agent_session_create_response",
            "agent_session_archive_response",
            "agent_session_unarchive_response"
        ] {
            try expect(websocket.contains(frameType), "WebSocketManager should handle \(frameType)")
        }
        try expect(websocket.contains("\"session_key\": sessionId"), "Codex message/history frames should include session_key")
        try expect(websocket.contains("codexMessagesByProfileSession"), "Codex chat state should be profile/session scoped")
        try expect(models.contains("canonicalWebSocketGatewayUrl"), "AgentProfile should canonicalize HTTP/WS gateway URLs")
        try expect(websocket.contains("AgentProfile.canonicalWebSocketGatewayUrl(trimmed)"), "WebSocketManager should accept https QR gateway URLs")
        try expect(settingsManager.contains("AgentProfile.canonicalWebSocketGatewayUrl(gatewayUrl)"), "Scanned profiles should store websocket gateway URLs")
        try expect(settingsManager.contains("localOnlyProfiles"), "Account profile sync should preserve local-only Codex profiles")
        try expect(app.contains("wsManager.requestPair(backendId: backendId)"), "QR pairing should be requested even when account sync fails")
        try expect(!app.contains("Agent 配置同步失败，请稍后重试"), "Account sync failure should not block local pairing")
        try expect(codexViews.contains("requestSessionsOrPair()"), "Codex session screen should pair/retry before showing an empty list")
        try expect(codexViews.contains("Mac-mini.local"), "Codex session header should avoid showing the Hermes label")
        print("CodexAgentSourceContractTests passed")
    }

    private static func read(_ root: URL, _ relativePath: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
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
