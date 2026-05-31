import SwiftUI

struct OTAUpgradeView: View {
    @ObservedObject var headsetSettingsStore: HeadsetSettingsStore
    let colors: MochiColors

    private var settings: HeadsetLocalSettings {
        headsetSettingsStore.settings
    }

    @State private var isUpgrading = false
    @State private var upgradeProgress: Double = 0

    var body: some View {
        List {
            Section("固件信息") {
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
            }

            Section {
                Button {
                    startUpgrade()
                } label: {
                    HStack {
                        Spacer()
                        if isUpgrading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                            Text("升级中...")
                        } else if settings.currentFirmwareVersion == settings.latestFirmwareVersion {
                            Text("已是最新版本")
                                .foregroundColor(.secondary)
                        } else {
                            Text("检查更新")
                        }
                        Spacer()
                    }
                }
                .disabled(isUpgrading || settings.currentFirmwareVersion == settings.latestFirmwareVersion)
            } footer: {
                if isUpgrading {
                    Text("正在下载并安装固件更新，请保持耳机与手机连接...")
                } else {
                    Text("建议在稳定的网络环境下进行升级")
                }
            }

            if isUpgrading {
                Section("升级进度") {
                    VStack(alignment: .leading, spacing: 8) {
                        ProgressView(value: upgradeProgress)
                            .accentColor(colors.primary)
                        Text("\(Int(upgradeProgress * 100))%")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("OTA升级")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func startUpgrade() {
        isUpgrading = true
        upgradeProgress = 0

        // 模拟升级进度
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
            if upgradeProgress < 1.0 {
                upgradeProgress += 0.05
            } else {
                timer.invalidate()
                isUpgrading = false
                // 更新当前版本
                headsetSettingsStore.update { settings in
                    settings.currentFirmwareVersion = settings.latestFirmwareVersion
                }
            }
        }
    }
}