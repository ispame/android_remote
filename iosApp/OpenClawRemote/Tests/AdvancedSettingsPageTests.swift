import Foundation

@main
struct AdvancedSettingsPageTests {
    static func main() throws {
        try testAdvancedSettingsOwnsOnlyConnectionDiagnosticsAndGlobalPreferences()
        try testAdvancedSettingsSavePathDoesNotMutateAgentProfilesOrAuthSession()
        try testAdvancedSettingsShowsAsrLoadingFailureAndManualFallback()
        try testPasswordChangeMovedToAccountSecurity()
        try testSettingsHomeExposesWalletAndPlanBilling()
        print("AdvancedSettingsPageTests passed")
    }

    private static func testAdvancedSettingsOwnsOnlyConnectionDiagnosticsAndGlobalPreferences() throws {
        let source = try readSource("iosApp/OpenClawRemote/Sources/SettingsScreenView.swift")
        let settingsView = try extractSettingsScreenView(from: source)

        try expect(source.contains("private struct AdvancedSettingsDraft"), "advanced settings should keep a small dedicated draft model")
        try expect(!source.contains("private struct AgentFormState"), "advanced settings should not own multi-Agent form state")
        try expect(!source.contains("private struct AgentFormCardView"), "advanced settings should not render Agent edit cards")

        for removedText in ["扫码或新增Agent", "短信登录", "修改密码", "发送验证码"] {
            try expect(!settingsView.contains(removedText), "advanced settings should not contain \(removedText)")
        }

        for requiredText in ["连接与诊断", "当前 Agent", "Gateway URL", "Backend ID", "登录状态", "重连", "取消当前 Agent 配对", "复制诊断信息"] {
            try expect(settingsView.contains(requiredText), "advanced settings should show \(requiredText)")
        }
    }

    private static func testAdvancedSettingsSavePathDoesNotMutateAgentProfilesOrAuthSession() throws {
        let source = try readSource("iosApp/OpenClawRemote/Sources/SettingsScreenView.swift")
        let saveFunction = try extractFunction(named: "saveAdvancedSettings", from: source)

        for requiredCall in [
            "settingsManager.updateDeviceLabel",
            "settingsManager.updateGlobalAsr",
            "wsManager.updateAsrConfiguration",
            "wsManager.applyProfile"
        ] {
            try expect(saveFunction.contains(requiredCall), "advanced settings save should call \(requiredCall)")
        }

        for forbiddenCall in [
            "settingsManager.saveProfile",
            "settingsManager.updateConfig",
            "GatewayConfig(",
            "agentForms",
            "saveForm("
        ] {
            try expect(!saveFunction.contains(forbiddenCall), "advanced settings save should not call or reference \(forbiddenCall)")
        }
    }

    private static func testAdvancedSettingsShowsAsrLoadingFailureAndManualFallback() throws {
        let source = try readSource("iosApp/OpenClawRemote/Sources/SettingsScreenView.swift")

        try expect(source.contains("private enum AsrProviderLoadState"), "ASR provider loading should have explicit UI state")
        for requiredState in ["case idle", "case loading", "case loaded", "case failed"] {
            try expect(source.contains(requiredState), "ASR provider state should include \(requiredState)")
        }
        try expect(source.contains("手动 Profile ID"), "failed or empty ASR provider loading should allow manual profile input")
        try expect(source.contains("刷新模型列表"), "ASR provider section should let the user retry loading providers")
    }

    private static func testPasswordChangeMovedToAccountSecurity() throws {
        let source = try readSource("iosApp/OpenClawRemote/Sources/Views/SimpleSettingsTabView.swift")

        try expect(source.contains("账号与安全"), "settings home should expose an account security destination")
        try expect(source.contains("GatewayAuthClient.changePassword"), "account security should own password changes")
        try expect(source.contains("wsManager.applyProfile"), "password changes should refresh the active WebSocket credentials")
    }

    private static func testSettingsHomeExposesWalletAndPlanBilling() throws {
        let source = try readSource("iosApp/OpenClawRemote/Sources/Views/SimpleSettingsTabView.swift")
        let appSource = try readSource("iosApp/OpenClawRemote/Sources/OpenClawRemoteApp.swift")
        let authSource = try readSource("iosApp/OpenClawRemote/Sources/SettingsScreenView.swift")

        try expect(source.contains("钱包与套餐"), "settings home should expose a wallet and plan destination")
        try expect(source.contains("WalletAndPlanView"), "wallet UI should be implemented in the settings flow")
        try expect(source.contains("GatewayAuthClient.billingSummary"), "wallet UI should load server billing summary")
        try expect(source.contains("GatewayAuthClient.createBillingOrder"), "wallet UI should create server-side orders")
        try expect(source.contains("GatewayAuthClient.billingOrderQrData"), "wallet UI should display server-generated QR images")
        try expect(appSource.contains("PAYMENT_REQUIRED"), "app should route PAYMENT_REQUIRED errors to wallet")
        try expect(authSource.contains("GatewayBillingSummaryResponse"), "GatewayAuthClient should decode billing summary responses")
    }

    private static func extractSettingsScreenView(from source: String) throws -> String {
        guard let start = source.range(of: "struct SettingsScreenView: View"),
              let end = source.range(of: "\n}\n\nprivate func maskedAccountLabel", range: start.lowerBound..<source.endIndex) else {
            throw TestFailure("Could not isolate SettingsScreenView")
        }
        return String(source[start.lowerBound..<end.upperBound])
    }

    private static func extractFunction(named name: String, from source: String) throws -> String {
        guard let start = source.range(of: "private func \(name)(") else {
            throw TestFailure("Could not find \(name)")
        }
        guard let nextFunction = source.range(of: "\n    private func ", range: start.upperBound..<source.endIndex) else {
            return String(source[start.lowerBound..<source.endIndex])
        }
        return String(source[start.lowerBound..<nextFunction.lowerBound])
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
