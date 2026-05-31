import SwiftUI

struct FindHeadsetView: View {
    @ObservedObject var headsetSettingsStore: HeadsetSettingsStore
    let colors: MochiColors

    private var settings: HeadsetLocalSettings {
        headsetSettingsStore.settings
    }

    @State private var isPlayingSound = false
    @State private var soundTimer: Timer?

    var body: some View {
        List {
            Section {
                VStack(spacing: 16) {
                    Image(systemName: "headphones.circle.fill")
                        .font(.system(size: 80))
                        .foregroundColor(colors.primary)

                    Text("找不到耳机？")
                        .font(.system(size: 20, weight: .semibold))

                    Text("让耳机发出声音来帮助您找到它")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
            }

            Section {
                Button {
                    toggleSound()
                } label: {
                    HStack {
                        Spacer()
                        if isPlayingSound {
                            Image(systemName: "speaker.wave.3.fill")
                                .foregroundColor(.white)
                            Text("停止播放")
                                .foregroundColor(.white)
                        } else {
                            Image(systemName: "speaker.wave.2.fill")
                            Text("播放声音")
                        }
                        Spacer()
                    }
                    .padding(.vertical, 12)
                    .background(isPlayingSound ? Color.red : colors.primary)
                    .cornerRadius(10)
                }
                .foregroundColor(.white)
            } footer: {
                Text(isPlayingSound ? "耳机正在播放声音，请在附近查找" : "点击按钮让耳机发出声音")
            }

            Section("耳机信息") {
                HStack {
                    Text("设备名称")
                    Spacer()
                    Text(selectedDeviceName)
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("连接状态")
                    Spacer()
                    HStack(spacing: 6) {
                        Circle()
                            .fill(settings.selectedDeviceId.isEmpty ? Color.gray : colors.onlineGreen)
                            .frame(width: 8, height: 8)
                        Text(settings.selectedDeviceId.isEmpty ? "未连接" : "已连接")
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("查找耳机")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            stopSound()
        }
    }

    private var selectedDeviceName: String {
        settings.devices.first { $0.id == settings.selectedDeviceId }?.name ?? "未选择设备"
    }

    private func toggleSound() {
        if isPlayingSound {
            stopSound()
        } else {
            startSound()
        }
    }

    private func startSound() {
        isPlayingSound = true
        // 模拟播放声音，间隔发出提示音
        soundTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            // 这里会触发耳机的提示音
        }
    }

    private func stopSound() {
        isPlayingSound = false
        soundTimer?.invalidate()
        soundTimer = nil
    }
}