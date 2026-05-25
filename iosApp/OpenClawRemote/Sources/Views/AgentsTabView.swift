import SwiftUI
import UIKit

struct AgentsTabView: View {
    @ObservedObject var wsManager: WebSocketManager
    @ObservedObject var settingsManager: SettingsManager
    @ObservedObject var audioRecorder: AudioRecorder
    @ObservedObject var headsetController: HeadsetConversationController
    @ObservedObject var messageSpeechController: MessageSpeechController
    let isDark: Bool
    let colors: MochiColors
    let onToggleTheme: () -> Void
    let onSelectProfile: (String) -> Void
    let onRequestScan: () -> Void

    private var profiles: [AgentProfile] {
        let sorted = settingsManager.profiles.sortedForAgentList(
            unreadCounts: wsManager.unreadCounts,
            activities: wsManager.agentListActivities
        )
        if sorted.count == 1,
           sorted[0].backendId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           sorted[0].token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return []
        }
        return sorted
    }

    var body: some View {
        List {
            Section {
                ForEach(profiles) { profile in
                    NavigationLink(
                        destination: AgentChatScreen(
                            profileId: profile.id,
                            wsManager: wsManager,
                            settingsManager: settingsManager,
                            audioRecorder: audioRecorder,
                            headsetController: headsetController,
                            messageSpeechController: messageSpeechController,
                            isDark: isDark,
                            colors: colors,
                            onToggleTheme: onToggleTheme,
                            onSelectProfile: onSelectProfile
                        )
                    ) {
                        AgentRowView(
                            profile: profile,
                            status: wsManager.availabilityStatus(for: profile),
                            unreadCount: wsManager.unreadCount(for: profile.id),
                            activity: wsManager.agentListActivities[profile.id],
                            colors: colors
                        )
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            delete(profile)
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                        Button {
                            settingsManager.setProfilePinned(profile.id, isPinned: !profile.isPinned)
                        } label: {
                            Label(profile.isPinned ? "取消置顶" : "置顶", systemImage: "pin.fill")
                        }
                        .tint(.orange)
                    }
                    .onAppear {
                        wsManager.syncProfiles(settingsManager.profiles)
                    }
                }
            } header: {
                Text("已连接的 Agent")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Agent")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: onRequestScan) {
                    Image(systemName: "qrcode.viewfinder")
                }
                .accessibilityLabel("扫码新增 Agent")
            }
        }
        .overlay {
            if profiles.isEmpty {
                EmptyStateView(
                    systemName: "qrcode.viewfinder",
                    title: "还没有 Agent",
                    message: "点击右上角扫码添加 Agent。"
                )
            }
        }
    }

    private func delete(_ profile: AgentProfile) {
        if settingsManager.profiles.count <= 1 {
            settingsManager.clearProfile(profile.id)
            wsManager.clearProfileState(profileId: profile.id)
        } else {
            settingsManager.deleteProfile(profile.id)
            wsManager.removeProfileState(profileId: profile.id)
        }
        wsManager.syncProfiles(settingsManager.profiles)
        onSelectProfile(settingsManager.selectedProfile.id)
    }
}

private struct AgentRowView: View {
    let profile: AgentProfile
    let status: AgentAvailabilityStatus
    let unreadCount: Int
    let activity: AgentListActivity?
    let colors: MochiColors

    private var statusColor: Color {
        switch status {
        case .available: return colors.onlineGreen
        case .pairing, .connecting: return colors.accent
        case .unconfigured, .unpaired: return colors.textSecondary
        case .offline: return colors.recordingRed
        }
    }

    private var recentPreview: String {
        let preview = activity?.latestMessagePreview?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return preview?.isEmpty == false ? preview! : "暂无对话"
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                Circle()
                    .fill(colors.primary.opacity(0.14))
                    .frame(width: 46, height: 46)
                Image(systemName: profile.platform.iconName)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(colors.primary)
                    .frame(width: 46, height: 46)
                StatusDot(color: statusColor)
                    .background(Circle().fill(Color(.systemBackground)).frame(width: 12, height: 12))
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(profile.resolvedDisplayName)
                        .font(.system(size: 16, weight: .semibold))
                        .lineLimit(1)
                    if profile.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.orange)
                    }
                    if unreadCount > 0 {
                        Circle()
                            .fill(colors.recordingRed)
                            .frame(width: 8, height: 8)
                    }
                }
                Text("\(profile.platform.label) · \(status.label)")
                    .font(.system(size: 12))
                    .foregroundColor(statusColor)
                Text(recentPreview)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(colors.textSecondary.opacity(0.6))
        }
        .padding(.vertical, 6)
    }
}

private struct AgentChatScreen: View {
    let profileId: String
    @ObservedObject var wsManager: WebSocketManager
    @ObservedObject var settingsManager: SettingsManager
    @ObservedObject var audioRecorder: AudioRecorder
    @ObservedObject var headsetController: HeadsetConversationController
    @ObservedObject var messageSpeechController: MessageSpeechController
    let isDark: Bool
    let colors: MochiColors
    let onToggleTheme: () -> Void
    let onSelectProfile: (String) -> Void

    @State private var showConfig = false

    private var profile: AgentProfile {
        settingsManager.profiles.first { $0.id == profileId } ?? settingsManager.selectedProfile
    }

    var body: some View {
        MainScreenView(
            wsManager: wsManager,
            settingsManager: settingsManager,
            audioRecorder: audioRecorder,
            headsetController: headsetController,
            messageSpeechController: messageSpeechController,
            isDark: isDark,
            colors: colors,
            onToggleTheme: onToggleTheme,
            onNavigateToSettings: { showConfig = true },
            onSelectProfile: onSelectProfile,
            showsTopBar: false,
            showsHeadsetStrip: true
        )
        .navigationTitle(profile.resolvedDisplayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showConfig = true
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("Agent 配置")
            }
        }
        .hideTabBarWhileVisible()
        .onAppear {
            onSelectProfile(profileId)
        }
        .sheet(isPresented: $showConfig) {
            CompatibleNavigationStack {
                AgentConfigView(
                    profile: profile,
                    colors: colors,
                    onSave: saveProfile
                )
            }
        }
    }

    private func saveProfile(_ profile: AgentProfile) {
        guard settingsManager.saveProfile(profile, select: true) else { return }
        wsManager.syncProfiles(settingsManager.profiles)
        wsManager.applyProfile(
            settingsManager.selectedProfile,
            deviceLabel: settingsManager.config.deviceLabel,
            accessToken: settingsManager.config.accessToken
        )
    }
}

private struct AgentConfigView: View {
    let profile: AgentProfile
    let colors: MochiColors
    let onSave: (AgentProfile) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var displayName: String
    @State private var gatewayUrl: String
    @State private var backendId: String
    @State private var token: String
    @State private var showsToken = false

    init(profile: AgentProfile, colors: MochiColors, onSave: @escaping (AgentProfile) -> Void) {
        self.profile = profile
        self.colors = colors
        self.onSave = onSave
        _displayName = State(initialValue: profile.resolvedDisplayName)
        _gatewayUrl = State(initialValue: profile.gatewayUrl)
        _backendId = State(initialValue: profile.backendId)
        _token = State(initialValue: profile.token)
    }

    var body: some View {
        Form {
            Section("Agent") {
                TextField("Agent 名称", text: $displayName)
                TextField("URL", text: $gatewayUrl)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("backend ID", text: $backendId)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            Section("Agent 连接 Token") {
                HStack {
                    if showsToken {
                        TextField("Token", text: $token)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    } else {
                        SecureField("Token", text: $token)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    Button {
                        showsToken.toggle()
                    } label: {
                        Image(systemName: showsToken ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.borderless)
                }

                HStack {
                    Button("复制") {
                        UIPasteboard.general.string = token
                    }
                    Spacer()
                    Button("粘贴") {
                        token = UIPasteboard.general.string ?? token
                    }
                }
            }
        }
        .navigationTitle("Agent 配置")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    var updated = profile
                    updated.displayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
                    updated.gatewayUrl = gatewayUrl.trimmingCharacters(in: .whitespacesAndNewlines)
                    updated.backendId = backendId.trimmingCharacters(in: .whitespacesAndNewlines)
                    updated.token = token.trimmingCharacters(in: .whitespacesAndNewlines)
                    updated.updatedAt = Date()
                    onSave(updated)
                    dismiss()
                }
            }
        }
    }
}
