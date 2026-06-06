import Foundation

@main
struct AccountSessionAgentTokenTests {
    static func main() throws {
        try testUpdateConfigExposesClearProfilesParameter()
        try testUpdateConfigAccountChangedBranchHonorsClearProfiles()
        try testReplaceAccountProfilesMergesLocalToken()
        try testClearAuthSessionAcceptsClearProfilesArgument()
        try testLogoutCallbackDisablesClearingProfiles()
        try testSwitchAccountCallbackEnablesClearingProfiles()
        try testSettingsTabFooterDescribesDifferentiatedBehavior()
        print("AccountSessionAgentTokenTests passed")
    }

    private static func testUpdateConfigExposesClearProfilesParameter() throws {
        let source = try readSource("iosApp/OpenClawRemote/Sources/SettingsManager.swift")
        let signature = try extractFunction(named: "updateConfig(", from: source)
        try expect(
            signature.contains("clearProfilesOnAccountChange"),
            "updateConfig should declare a clearProfilesOnAccountChange parameter so callers can opt out of resetting profiles"
        )
        try expect(
            signature.contains("clearProfilesOnAccountChange: Bool = true"),
            "updateConfig should default clearProfilesOnAccountChange to true to preserve existing behavior for callers that do not opt in"
        )
    }

    private static func testUpdateConfigAccountChangedBranchHonorsClearProfiles() throws {
        let source = try readSource("iosApp/OpenClawRemote/Sources/SettingsManager.swift")
        let updateConfig = try extractFunction(named: "updateConfig(", from: source)
        try expect(
            updateConfig.contains("if clearProfilesOnAccountChange"),
            "updateConfig should gate the accountChanged profile reset on clearProfilesOnAccountChange"
        )
        // The hard reset `profiles = [profile]` must sit inside the clearProfilesOnAccountChange branch,
        // not at the top of the accountChanged block. We assert that the assignment appears
        // after the `if clearProfilesOnAccountChange {` opening and before the matching close.
        guard let clearMarker = updateConfig.range(of: "if clearProfilesOnAccountChange {") else {
            throw TestFailure("updateConfig should contain an if-clearProfilesOnAccountChange block")
        }
        guard let assignment = updateConfig.range(of: "profiles = [profile]") else {
            throw TestFailure("updateConfig should still contain the profile-reset assignment, but gated on clearProfilesOnAccountChange")
        }
        try expect(
            assignment.lowerBound > clearMarker.lowerBound,
            "profiles = [profile] should be inside the clearProfilesOnAccountChange branch so it does not run when the caller opts out"
        )
    }

    private static func testReplaceAccountProfilesMergesLocalToken() throws {
        let source = try readSource("iosApp/OpenClawRemote/Sources/SettingsManager.swift")
        let replaceAccountProfiles = try extractFunction(named: "replaceAccountProfiles(", from: source)
        try expect(
            replaceAccountProfiles.contains("mappedProfile.token = existing.token"),
            "replaceAccountProfiles should merge the local token when the server returns an empty token, so that re-login after logout does not wipe stored tokens"
        )
        try expect(
            replaceAccountProfiles.contains("!existing.token.trimmingCharacters"),
            "replaceAccountProfiles should only fall back to the local token when the local token is non-empty"
        )
    }

    private static func testClearAuthSessionAcceptsClearProfilesArgument() throws {
        let source = try readSource("iosApp/OpenClawRemote/Sources/OpenClawRemoteApp.swift")
        let clearAuthSession = try extractFunction(named: "clearAuthSession(", from: source)
        try expect(
            clearAuthSession.contains("clearProfiles: Bool"),
            "clearAuthSession should declare a clearProfiles parameter to differentiate logout from switch-account"
        )
        try expect(
            clearAuthSession.contains("clearProfilesOnAccountChange: clearProfiles"),
            "clearAuthSession should forward clearProfiles to SettingsManager.updateConfig"
        )
    }

    private static func testLogoutCallbackDisablesClearingProfiles() throws {
        let source = try readSource("iosApp/OpenClawRemote/Sources/OpenClawRemoteApp.swift")
        let logoutRegion = try extractBlock(startingWith: "onLogout: {", from: source)
        try expect(
            logoutRegion.contains("clearAuthSession(message: \"已退出登录\", clearProfiles: false)"),
            "onLogout should pass clearProfiles: false so the local Agent profiles (with their tokens) are preserved"
        )
    }

    private static func testSwitchAccountCallbackEnablesClearingProfiles() throws {
        let source = try readSource("iosApp/OpenClawRemote/Sources/OpenClawRemoteApp.swift")
        let switchRegion = try extractBlock(startingWith: "onSwitchAccount: {", from: source)
        try expect(
            switchRegion.contains("clearAuthSession(message: \"请登录新账号\", clearProfiles: true)"),
            "onSwitchAccount should pass clearProfiles: true so a different account does not inherit this device's Agent tokens"
        )
    }

    private static func testSettingsTabFooterDescribesDifferentiatedBehavior() throws {
        let source = try readSource("iosApp/OpenClawRemote/Sources/Views/SimpleSettingsTabView.swift")
        try expect(
            source.contains("退出登录会保留本机 Agent 配置"),
            "settings tab should explicitly tell users that logout preserves local Agent profiles"
        )
        try expect(
            source.contains("切换账号会清空本机 Agent 配置"),
            "settings tab should explicitly tell users that switch-account clears local Agent profiles"
        )
        try expect(
            !source.contains("切换账号和退出登录会清除当前登录态，但保留本机 Agent、录音和耳机配置。"),
            "settings tab footer should no longer claim that switch-account preserves Agent profiles"
        )
    }

    private static func extractFunction(named name: String, from source: String) throws -> String {
        try extractBlock(startingWith: "func \(name)", from: source)
    }

    private static func extractBlock(startingWith marker: String, from source: String) throws -> String {
        guard let markerRange = source.range(of: marker) else {
            throw TestFailure("Could not find \(marker)")
        }
        guard let openingBrace = source[markerRange.lowerBound...].firstIndex(of: "{") else {
            throw TestFailure("Could not find opening brace for \(marker)")
        }

        var depth = 0
        var index = openingBrace
        while index < source.endIndex {
            let character = source[index]
            if character == "{" {
                depth += 1
            } else if character == "}" {
                depth -= 1
                if depth == 0 {
                    return String(source[markerRange.lowerBound...index])
                }
            }
            index = source.index(after: index)
        }

        throw TestFailure("Could not find closing brace for \(marker)")
    }

    private static func readSource(_ relativePath: String) throws -> String {
        let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
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
