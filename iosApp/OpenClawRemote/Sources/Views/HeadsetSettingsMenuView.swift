import SwiftUI

struct HeadsetSettingsMenuView: View {
    @ObservedObject var headsetSettingsStore: HeadsetSettingsStore
    let colors: MochiColors

    private var settings: HeadsetLocalSettings {
        headsetSettingsStore.settings
    }

    private var shortcutSummary: String {
        let activeCount = settings.shortcuts.filter { $0.action != "无操作" }.count
        return "\(activeCount) 个已设置"
    }

    private var firmwareVersionLine: String {
        if settings.currentFirmwareVersion == settings.latestFirmwareVersion {
            return "已是最新"
        }
        return "\(settings.currentFirmwareVersion) → \(settings.latestFirmwareVersion)"
    }

    var body: some View {
        List {
            Section("耳机设置") {
                NavigationLink {
                    HeadsetShortcutSettingsView(headsetSettingsStore: headsetSettingsStore)
                        .hideTabBarWhileVisible()
                } label: {
                    HStack {
                        Image(systemName: "hand.tap.fill")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(colors.primary)
                            .frame(width: 28, height: 28)
                        Text("耳机快捷键")
                            .font(.system(size: 15, weight: .semibold))
                        Spacer()
                        Text(shortcutSummary)
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                }

                NavigationLink {
                    HeadsetAudioSettingsView(
                        headsetSettingsStore: headsetSettingsStore,
                        colors: colors
                    )
                    .hideTabBarWhileVisible()
                } label: {
                    HStack {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(colors.primary)
                            .frame(width: 28, height: 28)
                        Text("EQ音频")
                            .font(.system(size: 15, weight: .semibold))
                        Spacer()
                        Text(selectedPresetName)
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                }

                NavigationLink {
                    OTAUpgradeView(
                        headsetSettingsStore: headsetSettingsStore,
                        colors: colors
                    )
                    .hideTabBarWhileVisible()
                } label: {
                    HStack {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(colors.primary)
                            .frame(width: 28, height: 28)
                        Text("OTA升级")
                            .font(.system(size: 15, weight: .semibold))
                        Spacer()
                        Text(firmwareVersionLine)
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                }

                NavigationLink {
                    FindHeadsetView(
                        headsetSettingsStore: headsetSettingsStore,
                        colors: colors
                    )
                    .hideTabBarWhileVisible()
                } label: {
                    HStack {
                        Image(systemName: "location.magnifyingglass")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(colors.primary)
                            .frame(width: 28, height: 28)
                        Text("查找耳机")
                            .font(.system(size: 15, weight: .semibold))
                        Spacer()
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("耳机设置")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var selectedPresetName: String {
        settings.eqPresets.first { $0.id == settings.selectedEQPresetId }?.name ?? "默认"
    }
}