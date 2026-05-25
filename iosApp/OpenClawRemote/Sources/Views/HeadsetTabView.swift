import SwiftUI

struct HeadsetTabView: View {
    @ObservedObject var headsetController: HeadsetConversationController
    @ObservedObject var headsetSettingsStore: HeadsetSettingsStore
    let colors: MochiColors

    private var settings: HeadsetLocalSettings {
        headsetSettingsStore.settings
    }

    private var selectedDevice: HeadsetDevice {
        settings.devices.first { $0.id == settings.selectedDeviceId } ?? settings.devices[0]
    }

    private var selectedPreset: EQPreset {
        settings.eqPresets.first { $0.id == settings.selectedEQPresetId } ?? settings.eqPresets[0]
    }

    @State private var audioSettingsExpanded = false
    @State private var shortcutSettingsExpanded = false
    @State private var otaExpanded = false
    @State private var findHeadsetExpanded = false

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "headphones")
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundColor(colors.primary)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(selectedDevice.name)
                                .font(.system(size: 18, weight: .semibold))
                            Text(connectionLabel)
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        StatusDot(color: headsetIsReady ? colors.onlineGreen : colors.textSecondary)
                    }

                    HStack(spacing: 16) {
                        BatteryPill(title: "左耳", value: selectedDevice.leftBattery, colors: colors)
                        BatteryPill(title: "右耳", value: selectedDevice.rightBattery, colors: colors)
                    }
                }
                .padding(.vertical, 6)
            } header: {
                Text("耳机状态")
            }

            Section("新功能") {
                FeatureRow(icon: "textformat.abc", title: "英语口语练习", subtitle: "使用耳机完成口语对练")
                FeatureRow(icon: "globe.asia.australia.fill", title: "同声传译", subtitle: "实时翻译对话内容")
                FeatureRow(icon: "sparkles", title: "AI聊天", subtitle: "通过耳机直接与 Agent 对话")
            }

            Section("设置") {
                ExpandableSettingsRow(
                    icon: "slider.horizontal.3",
                    title: "音频设置",
                    detail: selectedPreset.name,
                    isExpanded: $audioSettingsExpanded,
                    colors: colors
                ) {
                    HeadsetAudioSettingsView(headsetSettingsStore: headsetSettingsStore)
                        .listRowInsets(EdgeInsets())
                }

                ExpandableSettingsRow(
                    icon: "hand.tap.fill",
                    title: "耳机快捷键",
                    detail: shortcutSummary,
                    isExpanded: $shortcutSettingsExpanded,
                    colors: colors
                ) {
                    HeadsetShortcutSettingsView(headsetSettingsStore: headsetSettingsStore)
                        .listRowInsets(EdgeInsets())
                }

                ExpandableSettingsRow(
                    icon: "arrow.triangle.2.circlepath",
                    title: "OTA 升级",
                    detail: firmwareVersionLine,
                    isExpanded: $otaExpanded,
                    colors: colors
                ) {
                    HeadsetOTAPlaceholderView(settings: settings, colors: colors)
                        .listRowInsets(EdgeInsets())
                }

                ExpandableSettingsRow(
                    icon: "location.magnifyingglass",
                    title: "查找耳机",
                    detail: nil,
                    isExpanded: $findHeadsetExpanded,
                    colors: colors
                ) {
                    FindHeadsetView(colors: colors)
                        .listRowInsets(EdgeInsets())
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("耳机")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    addFakeDevice()
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("添加新耳机")
            }
        }
    }

    private var shortcutSummary: String {
        let activeCount = settings.shortcuts.filter { $0.action != "无操作" }.count
        return "\(activeCount) 个已设置"
    }

    private var firmwareVersionLine: String {
        return "直接升级"
    }

    private func addFakeDevice() {
        headsetSettingsStore.update { settings in
            let id = "demo-\(settings.devices.count + 1)"
            settings.devices.append(
                HeadsetDevice(
                    id: id,
                    name: "A9 Ultra \(settings.devices.count + 1)",
                    isPaired: false,
                    leftBattery: 100,
                    rightBattery: 100
                )
            )
            settings.selectedDeviceId = id
        }
    }

    private var headsetIsReady: Bool {
        if case .ready = headsetController.connectionState {
            return true
        }
        return false
    }

    private var connectionLabel: String {
        switch headsetController.connectionState {
        case .idle:
            return selectedDevice.isPaired ? "已配对，等待连接" : "未配对"
        case .scanning:
            return "正在查找耳机"
        case .connecting(let name):
            return "正在连接 \(name)"
        case .connected(let name):
            return "\(name) 校验中"
        case .ready(let name):
            return "\(name) 已就绪"
        case .unsupportedProduct(let productId):
            return "不支持的设备 0x\(String(productId, radix: 16))"
        case .bluetoothUnavailable(let message):
            return message
        }
    }
}

private struct ExpandableSettingsRow<Content: View>: View {
    let icon: String
    let title: String
    let detail: String?
    @Binding var isExpanded: Bool
    let colors: MochiColors
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: icon)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(colors.primary)
                        .frame(width: 28, height: 28)
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(colors.textPrimary)
                    Spacer()
                    if let detail {
                        Text(detail)
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)

            if isExpanded {
                content()
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

private struct SettingsEntryRow: View {
    let icon: String
    let title: String
    let detail: String?
    let colors: MochiColors

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(colors.primary)
                .frame(width: 28, height: 28)
            Text(title)
                .font(.system(size: 15, weight: .semibold))
            Spacer()
            if let detail {
                Text(detail)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 3)
    }
}

private struct HeadsetAudioSettingsView: View {
    @ObservedObject var headsetSettingsStore: HeadsetSettingsStore

    private var settings: HeadsetLocalSettings {
        headsetSettingsStore.settings
    }

    private var selectedPreset: EQPreset {
        settings.eqPresets.first { $0.id == settings.selectedEQPresetId } ?? settings.eqPresets[0]
    }

    @State private var audioSettingsExpanded = false
    @State private var shortcutSettingsExpanded = false
    @State private var otaExpanded = false
    @State private var findHeadsetExpanded = false

    var body: some View {
        List {
            Section("音频设置") {
                Picker("预设", selection: selectedPresetBinding) {
                    ForEach(settings.eqPresets) { preset in
                        Text(preset.name).tag(preset.id)
                    }
                }

                ForEach(selectedPreset.bands) { band in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(band.frequency)
                            .font(.system(size: 14, weight: .semibold))
                        Slider(
                            value: bandBinding(presetId: selectedPreset.id, bandId: band.id),
                            in: -6...6,
                            step: 1
                        )
                        HStack {
                            Text("Low")
                            Spacer()
                            Text("High")
                        }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("音频设置")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var selectedPresetBinding: Binding<String> {
        Binding(
            get: { settings.selectedEQPresetId },
            set: { newValue in
                headsetSettingsStore.update { $0.selectedEQPresetId = newValue }
            }
        )
    }

    private func bandBinding(presetId: String, bandId: String) -> Binding<Double> {
        Binding(
            get: {
                settings.eqPresets
                    .first { $0.id == presetId }?
                    .bands
                    .first { $0.id == bandId }?
                    .gain ?? 0
            },
            set: { newValue in
                headsetSettingsStore.update { settings in
                    guard let presetIndex = settings.eqPresets.firstIndex(where: { $0.id == presetId }),
                          let bandIndex = settings.eqPresets[presetIndex].bands.firstIndex(where: { $0.id == bandId }) else {
                        return
                    }
                    settings.eqPresets[presetIndex].bands[bandIndex].gain = newValue
                }
            }
        )
    }
}

private struct HeadsetShortcutSettingsView: View {
    @ObservedObject var headsetSettingsStore: HeadsetSettingsStore

    private var shortcuts: [HeadsetShortcut] {
        headsetSettingsStore.settings.shortcuts
    }

    var body: some View {
        List {
            Section("耳机快捷键") {
                ForEach(shortcuts) { shortcut in
                    Picker("\(shortcut.side.label) \(shortcut.gesture.label)", selection: shortcutBinding(shortcut.id)) {
                        ForEach(HeadsetShortcut.actionOptions, id: \.self) { action in
                            Text(action).tag(action)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("耳机快捷键")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func shortcutBinding(_ id: String) -> Binding<String> {
        Binding(
            get: {
                shortcuts.first { $0.id == id }?.action ?? "无操作"
            },
            set: { newValue in
                headsetSettingsStore.update { settings in
                    guard let index = settings.shortcuts.firstIndex(where: { $0.id == id }) else { return }
                    settings.shortcuts[index].action = newValue
                }
            }
        )
    }
}

private struct HeadsetOTAPlaceholderView: View {
    let settings: HeadsetLocalSettings
    let colors: MochiColors

    var body: some View {
        List {
            Section {
                HStack {
                    Text("OTA 版本")
                        .font(.system(size: 15))
                    Spacer()
                    Button("直接升级") {}
                        .foregroundColor(colors.primary)
                        .buttonStyle(.borderless)
                }
                .padding(.vertical, 3)
            } footer: {
                Text("升级入口预留，暂未接入实际 OTA 流程")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("OTA 升级")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct FindHeadsetView: View {
    let colors: MochiColors

    var body: some View {
        List {
            Section {
                Text("查找耳机功能开发中")
                    .font(.system(size: 15))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 40)
            } footer: {
                Text("该功能即将推出")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("查找耳机")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct UnsupportedHeadsetFeatureView: View {
    let title: String
    let systemName: String

    var body: some View {
        EmptyStateView(
            systemName: systemName,
            title: title,
            message: "暂不支持"
        )
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct BatteryPill: View {
    let title: String
    let value: Int
    let colors: MochiColors

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "battery.100")
                .foregroundColor(colors.onlineGreen)
            Text(title)
                .font(.system(size: 13, weight: .medium))
            Spacer()
            Text("\(value)%")
                .font(.system(size: 13, weight: .semibold))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(10)
    }
}

private struct FeatureRow: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 34, height: 34)
                .background(Color(.tertiarySystemGroupedBackground))
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 3)
    }
}
