import Foundation

@main
struct AdvancedSettingsPageTests {
    static func main() throws {
        try testAdvancedSettingsOwnsOnlyConnectionDiagnosticsAndGlobalPreferences()
        try testAdvancedSettingsSavePathDoesNotMutateAgentProfilesOrAuthSession()
        try testAdvancedSettingsRedirectsAiServiceInsteadOfEditingAsrInline()
        try testAiServicePageUsesByokProviderPickers()
        try testPasswordChangeMovedToAccountSecurity()
        try testChangePasswordConfirmButtonStaysTappableForValidationFeedback()
        try testSettingsHomeExposesWalletAndPlanBilling()
        try testWalletCopiesPlainPaymentUrlForShareAndScan()
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
            "wsManager.applyProfile"
        ] {
            try expect(saveFunction.contains(requiredCall), "advanced settings save should call \(requiredCall)")
        }

        for forbiddenCall in [
            "settingsManager.updateGlobalAsr",
            "wsManager.updateAsrConfiguration",
            "settingsManager.saveProfile",
            "settingsManager.updateConfig",
            "GatewayConfig(",
            "agentForms",
            "saveForm("
        ] {
            try expect(!saveFunction.contains(forbiddenCall), "advanced settings save should not call or reference \(forbiddenCall)")
        }
    }

    private static func testAdvancedSettingsRedirectsAiServiceInsteadOfEditingAsrInline() throws {
        let source = try readSource("iosApp/OpenClawRemote/Sources/SettingsScreenView.swift")
        let settingsView = try extractSettingsScreenView(from: source)

        try expect(settingsView.contains("AIServiceNavigationLink"), "advanced settings should redirect AI service editing to the unified page")
        try expect(settingsView.contains("AdvancedInfoRow(title: \"AI 服务\""), "advanced settings should show an AI service summary")
        try expect(!source.contains("private enum AsrProviderLoadState"), "advanced settings should not own ASR provider loading state")
        try expect(!settingsView.contains("Picker(\"语音识别\""), "advanced settings should not edit ASR inline")
        try expect(!settingsView.contains("刷新模型列表"), "advanced settings should not refresh ASR providers inline")
    }

    private static func testAiServicePageUsesByokProviderPickers() throws {
        let source = try readSource("iosApp/OpenClawRemote/Sources/Views/SimpleSettingsTabView.swift")
        let aiServiceView = try extractStruct(named: "AiServiceSettingsView", from: source, isPrivate: false)
        let agentOverrideView = try extractStruct(named: "AgentAiOverrideEditorView", from: source)

        for requiredText in [
            "AiProviderCatalog.llmByokProviders",
            "AiProviderCatalog.asrByokProviders",
            "AiProviderCatalog.ttsByokProviders",
            "Picker(\"Provider\", selection: $draftLlmProviderId)",
            "Picker(\"Provider\", selection: $draftAsrProviderId)",
            "Picker(\"Provider\", selection: $draftTtsProviderId)",
            "Text(\"Router\").tag(\"router\")",
            "Text(\"BYOK\").tag(\"byok\")",
            "Text(\"系统 TTS\").tag(\"system\")",
            "Router TTS",
            "applyLlmProviderDefaults",
            "applyAsrProviderDefaults",
            "applyTtsProviderDefaults"
        ] {
            try expect(aiServiceView.contains(requiredText), "AI service page should contain \(requiredText)")
        }

        try expect(agentOverrideView.contains("Picker(\"Provider\", selection: $llmProviderId)"), "Agent override should choose LLM BYOK provider")
        try expect(agentOverrideView.contains("Picker(\"Provider\", selection: $asrProviderId)"), "Agent override should choose ASR BYOK provider")
        try expect(agentOverrideView.contains("Picker(\"Provider\", selection: $ttsProviderId)"), "Agent override should choose TTS BYOK provider")
        try expect(agentOverrideView.contains("Text(\"Router\").tag(\"router\")"), "Agent override should expose Router TTS as a top-level mode")
        try expect(!aiServiceView.contains("Text(\"MiniMax\").tag(\"minimax\")"), "TTS should not expose MiniMax as a top-level mode")
    }

    private static func testPasswordChangeMovedToAccountSecurity() throws {
        let source = try readSource("iosApp/OpenClawRemote/Sources/Views/SimpleSettingsTabView.swift")

        try expect(source.contains("账号与安全"), "settings home should expose an account security destination")
        try expect(source.contains("EditAccountDisplayNameView"), "account security should expose username editing as a child page")
        try expect(source.contains("GatewayAuthClient.updateAccountDisplayName"), "username edits should call the server account profile API")
        try expect(source.contains("ChangePasswordView"), "password changes should live in a child page")
        try expect(source.contains("GatewayAuthClient.changePassword"), "account security should own password changes")
        try expect(source.contains("wsManager.applyProfile"), "password changes should refresh the active WebSocket credentials")
        let accountSecurityView = try extractStruct(named: "AccountSecurityView", from: source)
        try expect(accountSecurityView.contains("NavigationLink"), "account security home should navigate to child pages")
        try expect(!accountSecurityView.contains("SecureField("), "account security home should not inline password inputs")
    }

    private static func testChangePasswordConfirmButtonStaysTappableForValidationFeedback() throws {
        let source = try readSource("iosApp/OpenClawRemote/Sources/Views/SimpleSettingsTabView.swift")
        let changePasswordView = try extractStruct(named: "ChangePasswordView", from: source)

        try expect(changePasswordView.contains("确认修改密码"), "password screen should expose a clear confirm action")
        try expect(changePasswordView.contains("guard canSubmit else"), "password validation should happen inside the submit action")
        try expect(changePasswordView.contains(".disabled(isLoading)"), "confirm action should only be disabled while the request is running")
        try expect(!changePasswordView.contains(".disabled(isLoading || !canSubmit)"), "confirm action should remain tappable so validation can show feedback")
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

    private static func testWalletCopiesPlainPaymentUrlForShareAndScan() throws {
        let source = try readSource("iosApp/OpenClawRemote/Sources/Views/SimpleSettingsTabView.swift")

        try expect(source.contains("private func billingPaymentClipboardText(for order: GatewayBillingOrderResponse) -> String"), "wallet copy behavior should be isolated for payment links")
        try expect(source.contains("UIPasteboard.general.string = billingPaymentClipboardText(for: activeOrder)"), "wallet copy button should copy the plain payment URL")
        try expect(!source.contains("UIPasteboard.general.string = activeOrder.copyText.isEmpty ? activeOrder.paymentUrl : activeOrder.copyText"), "wallet copy button should not prefer multiline copy_text over payment_url")
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

    private static func extractStruct(named name: String, from source: String, isPrivate: Bool = true) throws -> String {
        let declaration = isPrivate ? "private struct \(name): View" : "struct \(name): View"
        guard let start = source.range(of: declaration) else {
            throw TestFailure("Could not find \(name)")
        }
        guard let nextStruct = source.range(of: "\nprivate struct ", range: start.upperBound..<source.endIndex) else {
            return String(source[start.lowerBound..<source.endIndex])
        }
        return String(source[start.lowerBound..<nextStruct.lowerBound])
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
