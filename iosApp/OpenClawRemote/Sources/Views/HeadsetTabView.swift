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
                        StatusDot(color: selectedDevice.isPaired ? colors.onlineGreen : colors.textSecondary)
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

    private func addFakeDevice() {
        headsetSettingsStore.update { settings in
            settings.addDemoDevice()
        }
    }

    private var connectionLabel: String {
        selectedDevice.isPaired ? "已配对" : "未配对"
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

struct HeadsetAudioSettingsView: View {
    @ObservedObject var headsetSettingsStore: HeadsetSettingsStore
    let colors: MochiColors

    private var settings: HeadsetLocalSettings {
        headsetSettingsStore.settings
    }

    private var selectedPreset: EQPreset {
        settings.eqPresets.first { $0.id == settings.selectedEQPresetId } ?? settings.eqPresets[0]
    }

    var body: some View {
        List {
            Section("EQ 预设") {
                Picker("预设", selection: selectedPresetBinding) {
                    ForEach(settings.eqPresets) { preset in
                        Text(preset.name).tag(preset.id)
                    }
                }
            }

            Section(selectedPreset.name) {
                ForEach(selectedPreset.bands) { band in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(band.frequency)
                                .font(.system(size: 14, weight: .semibold))
                            Spacer()
                            Text(formatGain(band.gain))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(colors.primary)
                        }
                        Slider(
                            value: bandBinding(presetId: selectedPreset.id, bandId: band.id),
                            in: -6...6,
                            step: 1
                        )
                        .accentColor(colors.primary)
                        HStack {
                            Text("-6 dB")
                            Spacer()
                            Text("+6 dB")
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

    private func formatGain(_ gain: Double) -> String {
        if gain > 0 {
            return "+\(Int(gain)) dB"
        }
        return "\(Int(gain)) dB"
    }
}

struct HeadsetShortcutSettingsView: View {
    @ObservedObject var headsetSettingsStore: HeadsetSettingsStore

    private var shortcuts: [HeadsetShortcut] {
        headsetSettingsStore.settings.shortcuts
    }

    var body: some View {
        List {
            ForEach(HeadsetSideSelection.allCases) { side in
                Section(side.label) {
                    ForEach(HeadsetGestureSelection.allCases) { gesture in
                        Picker(gesture.label, selection: shortcutBinding(side: side, gesture: gesture)) {
                            ForEach(HeadsetShortcut.actionOptions, id: \.self) { action in
                                Text(action).tag(action)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("耳机快捷键")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func shortcutBinding(side: HeadsetSideSelection, gesture: HeadsetGestureSelection) -> Binding<String> {
        let id = "\(side.rawValue)-\(gesture.rawValue)"
        return Binding(
            get: {
                shortcuts.first { $0.id == id }?.action ?? "无操作"
            },
            set: { newValue in
                headsetSettingsStore.update { settings in
                    if let index = settings.shortcuts.firstIndex(where: { $0.id == id }) {
                        settings.shortcuts[index].action = newValue
                    } else {
                        settings.shortcuts.append(
                            HeadsetShortcut(
                                id: id,
                                side: side,
                                gesture: gesture,
                                action: newValue
                            )
                        )
                    }
                }
            }
        )
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
