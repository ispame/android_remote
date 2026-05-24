import SwiftUI

struct SimpleSettingsTabView: View {
    @ObservedObject var wsManager: WebSocketManager
    @ObservedObject var settingsManager: SettingsManager
    let isDark: Bool
    let colors: MochiColors
    let onToggleTheme: () -> Void
    let onRequestPair: (String) -> Void
    let onSelectProfile: (String) -> Void
    let onSwitchAccount: () -> Void
    let onLogout: () -> Void
    @State private var showAdvancedSettings = false

    var body: some View {
        List {
            Section {
                HStack {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 36))
                        .foregroundColor(colors.primary)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(accountTitle)
                            .font(.system(size: 16, weight: .semibold))
                        Text("当前 Agent：\(settingsManager.selectedProfile.resolvedDisplayName)")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 6)
            }

            Section("偏好") {
                Button {
                    onToggleTheme()
                } label: {
                    HStack {
                        Label(isDark ? "浅色模式" : "深色模式", systemImage: isDark ? "sun.max.fill" : "moon.fill")
                        Spacer()
                    }
                }
                .foregroundColor(.primary)

                Button {
                    showAdvancedSettings = true
                } label: {
                    HStack {
                        Label("高级设置", systemImage: "slider.horizontal.3")
                        Spacer()
                    }
                }
                .foregroundColor(.primary)
            }

            Section(
                header: Text("账号"),
                footer: Text("切换账号和退出登录会清除当前登录态，但保留本机 Agent、任务、录音和耳机配置。")
            ) {
                Button("切换账号") {
                    onSwitchAccount()
                }
                Button(role: .destructive) {
                    onLogout()
                } label: {
                    Text("退出登录")
                }
            }

            Section("关于") {
                HStack {
                    Text("APP 版本")
                    Spacer()
                    Text(appVersion)
                        .foregroundColor(.secondary)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAdvancedSettings) {
            SettingsScreenView(
                wsManager: wsManager,
                settingsManager: settingsManager,
                isDark: isDark,
                colors: colors,
                onToggleTheme: onToggleTheme,
                onRequestPair: onRequestPair,
                onUnpair: {
                    wsManager.unpair()
                },
                onBack: {
                    showAdvancedSettings = false
                },
                onNavigateToQRScanner: {},
                onSelectProfile: onSelectProfile
            )
        }
    }

    private var accountTitle: String {
        let accountId = settingsManager.config.accountId.trimmingCharacters(in: .whitespacesAndNewlines)
        return accountId.isEmpty ? "未登录" : maskedAccountLabel(accountId)
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        switch (version, build) {
        case let (.some(version), .some(build)):
            return "\(version) (\(build))"
        case let (.some(version), .none):
            return version
        default:
            return "1.0"
        }
    }

    private func maskedAccountLabel(_ accountId: String) -> String {
        let value = accountId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.count > 12 else { return value }
        return "\(value.prefix(8))...\(value.suffix(4))"
    }
}
