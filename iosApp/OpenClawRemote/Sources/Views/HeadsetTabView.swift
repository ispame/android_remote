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

            Section("EQ 音频设置") {
                Picker("预设", selection: selectedPresetBinding) {
                    ForEach(settings.eqPresets) { preset in
                        Text(preset.name).tag(preset.id)
                    }
                }

                ForEach(selectedPreset.bands) { band in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(band.frequency)
                            Spacer()
                            Text("\(Int(band.gain)) dB")
                                .foregroundColor(.secondary)
                        }
                        Slider(
                            value: bandBinding(presetId: selectedPreset.id, bandId: band.id),
                            in: -6...6,
                            step: 1
                        )
                    }
                    .padding(.vertical, 3)
                }
            }

            Section("耳机快捷键") {
                ForEach(settings.shortcuts) { shortcut in
                    Picker("\(shortcut.side.label) \(shortcut.gesture.label)", selection: shortcutBinding(shortcut.id)) {
                        ForEach(HeadsetShortcut.actionOptions, id: \.self) { action in
                            Text(action).tag(action)
                        }
                    }
                }
            }

            Section("OTA 升级") {
                HStack {
                    Text("当前版本")
                    Spacer()
                    Text(settings.currentFirmwareVersion)
                        .foregroundColor(.secondary)
                }
                HStack {
                    Text("最新版本")
                    Spacer()
                    Text(settings.latestFirmwareVersion)
                        .foregroundColor(colors.primary)
                }
                Button("升级到 \(settings.latestFirmwareVersion)") {
                    headsetSettingsStore.update {
                        $0.currentFirmwareVersion = $0.latestFirmwareVersion
                    }
                }
                    .disabled(settings.currentFirmwareVersion == settings.latestFirmwareVersion)
            }

            Section {
                Button("查找耳机") {}
                    .disabled(true)
            } footer: {
                Text("查找耳机暂未实现")
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

    private func shortcutBinding(_ id: String) -> Binding<String> {
        Binding(
            get: {
                settings.shortcuts.first { $0.id == id }?.action ?? "无操作"
            },
            set: { newValue in
                headsetSettingsStore.update { settings in
                    guard let index = settings.shortcuts.firstIndex(where: { $0.id == id }) else { return }
                    settings.shortcuts[index].action = newValue
                }
            }
        )
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
