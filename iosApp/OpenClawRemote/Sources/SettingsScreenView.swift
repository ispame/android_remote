import SwiftUI

// MARK: - Connection Status Card

struct ConnectionStatusCard: View {
    let connectionState: ConnectionState
    let pairingState: PairingState
    let pairedBackendLabel: String?
    let colors: MochiColors
    let onUnpair: () -> Void

    private var statusColor: Color {
        if pairingState == .paired { return colors.primary }
        if connectionState == .connected || connectionState == .registered { return colors.accent }
        if connectionState == .connecting { return colors.secondary }
        return colors.recordingRed
    }

    private var statusText: String {
        if pairingState == .paired {
            return "已配对" + (pairedBackendLabel.map { ": \($0)" } ?? "")
        }
        switch connectionState {
        case .registered: return "连接成功，请扫码配对"
        case .connecting: return "连接中..."
        default: return "未连接"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: pairingState == .paired ? "link" : "link.badge.plus")
                .font(.system(size: 24))
                .foregroundColor(statusColor)

            VStack(alignment: .leading, spacing: 2) {
                Text("连接状态")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(colors.textSecondary)
                Text(statusText)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(statusColor)
            }

            Spacer()

            if pairingState == .paired {
                Button(action: onUnpair) {
                    Text("取消配对")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(colors.recordingRed)
                }
            }
        }
        .padding(16)
        .background(statusColor.opacity(0.1))
        .cornerRadius(12)
    }
}

// MARK: - Section Title

struct SectionTitleView: View {
    let text: String
    let colors: MochiColors

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(colors.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
    }
}

// MARK: - Outlined TextField — matches Android's Material3 OutlinedTextField

struct OutlinedTextField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    let colors: MochiColors

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(colors.textSecondary)

            TextField(placeholder, text: $text)
                .font(.system(size: 15, weight: .regular))
                .foregroundColor(colors.inputText)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(colors.inputBg)
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(colors.inputBorder, lineWidth: 1)
                    }
                )
        }
    }
}

// MARK: - Help Card

struct HelpCardView: View {
    let colors: MochiColors

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("使用说明")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(colors.textPrimary)

            VStack(alignment: .leading, spacing: 4) {
                Text("1. 在 OpenClaw 侧启动 Gateway Plugin")
                Text("2. Plugin 会生成配对二维码")
                Text("3. 点击「扫描二维码配对」")
                Text("4. 扫描后自动连接并配对")
                Text("5. 配对成功后即可开始对话")
            }
            .font(.system(size: 12, weight: .regular))
            .foregroundColor(colors.textSecondary.opacity(0.7))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(colors.surface.opacity(0.5))
        .cornerRadius(12)
    }
}

// MARK: - Settings Screen

struct SettingsScreenView: View {
    @ObservedObject var wsManager: WebSocketManager
    @ObservedObject var settingsManager: SettingsManager
    let isDark: Bool
    let colors: MochiColors
    let onToggleTheme: () -> Void
    let onRequestPair: (String) -> Void
    let onUnpair: () -> Void
    let onBack: () -> Void
    let onNavigateToQRScanner: () -> Void

    @State private var gatewayUrl: String = ""
    @State private var deviceLabel: String = ""
    @State private var manualBackendId: String = ""
    @State private var manualToken: String = ""
    @State private var showSaved = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    // Connection status
                    ConnectionStatusCard(
                        connectionState: wsManager.connectionState,
                        pairingState: wsManager.pairingState,
                        pairedBackendLabel: settingsManager.config.pairedBackendLabel,
                        colors: colors,
                        onUnpair: onUnpair
                    )

                    Divider()

                    // QR scan pairing
                    SectionTitleView(text: "扫码配对 OpenClaw", colors: colors)
                    Text("扫描 OpenClaw Gateway Plugin 生成的二维码，配对成功后即可开始对话")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(colors.textSecondary)

                    Button(action: onNavigateToQRScanner) {
                        HStack {
                            Image(systemName: "qrcode.viewfinder")
                            Text(settingsManager.config.pairedBackendId == nil ? "扫描二维码配对" : "重新扫码配对")
                        }
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(colors.onPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(colors.primary)
                        .cornerRadius(8)
                    }

                    Divider()

                    // Manual pairing
                    SectionTitleView(text: "手动配对", colors: colors)
                    Text("输入 Gateway 地址和 Backend ID 进行配对")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(colors.textSecondary)

                    OutlinedTextField(
                        label: "Backend ID",
                        placeholder: "agent backend ID",
                        text: $manualBackendId,
                        colors: colors
                    )
                    OutlinedTextField(
                        label: "Token",
                        placeholder: "配对 Token",
                        text: $manualToken,
                        colors: colors
                    )

                    Button {
                        guard !gatewayUrl.isEmpty else { return }
                        guard !manualBackendId.isEmpty else { return }

                        settingsManager.updateConfig(GatewayConfig(
                            gatewayUrl: gatewayUrl,
                            deviceId: settingsManager.config.deviceId,
                            deviceLabel: deviceLabel.isEmpty ? "我的设备" : deviceLabel,
                            token: manualToken,
                            pairedBackendId: manualBackendId,
                            pairedBackendLabel: nil
                        ))
                        onRequestPair(manualBackendId)
                    } label: {
                        HStack {
                            Image(systemName: "link")
                            Text("配对")
                        }
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(colors.onPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(colors.primary)
                        .cornerRadius(8)
                    }
                    .disabled(wsManager.connectionState == .connecting)

                    Divider()

                    // Gateway address
                    SectionTitleView(text: "Gateway 地址", colors: colors)
                    OutlinedTextField(
                        label: "Gateway URL",
                        placeholder: "ws://gateway.example.com:8765",
                        text: $gatewayUrl,
                        colors: colors
                    )

                    // Device info
                    SectionTitleView(text: "设备信息", colors: colors)
                    OutlinedTextField(
                        label: "设备名称",
                        placeholder: "例如：我的手机",
                        text: $deviceLabel,
                        colors: colors
                    )

                    Button {
                        settingsManager.updateConfig(GatewayConfig(
                            gatewayUrl: gatewayUrl,
                            deviceId: settingsManager.config.deviceId,
                            deviceLabel: deviceLabel.isEmpty ? "我的设备" : deviceLabel,
                            token: manualToken,
                            pairedBackendId: manualBackendId.isEmpty ? nil : manualBackendId,
                            pairedBackendLabel: settingsManager.config.pairedBackendLabel
                        ))
                        showSaved = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { showSaved = false }
                    } label: {
                        Text("保存")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(colors.onPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(colors.primary)
                            .cornerRadius(8)
                    }

                    if showSaved {
                        Text("设置已保存")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(colors.accent)
                    }

                    HelpCardView(colors: colors)
                }
                .padding(16)
            }
            .background(colors.background)
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: onBack) {
                        Image(systemName: "chevron.left")
                            .foregroundColor(colors.icon)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: onToggleTheme) {
                        Image(systemName: isDark ? "sun.max.fill" : "moon.fill")
                            .foregroundColor(colors.icon)
                    }
                }
            }
        }
        .onAppear {
            gatewayUrl = settingsManager.config.gatewayUrl
            deviceLabel = settingsManager.config.deviceLabel
            manualBackendId = settingsManager.config.pairedBackendId ?? ""
            manualToken = settingsManager.config.token
        }
    }
}
