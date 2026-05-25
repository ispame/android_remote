import Foundation
import Combine

final class SettingsManager: ObservableObject {
    static let maxAgentProfiles = 20

    private let defaults: UserDefaults
    private let profilesKey = "agent_profiles_v1"
    private let selectedProfileIdKey = "selected_agent_profile_id"
    private let primaryRecordingAgentProfileIdKey = "primary_agent_profile_id"
    private let recordingDeliverToAgentKey = "recording_deliver_to_agent"
    private let recordingPromptKey = "recording_prompt"
    private let recordingAsrProfileIdKey = "recording_asr_profile_id"

    @Published private(set) var profiles: [AgentProfile]
    @Published private(set) var selectedProfileId: String
    @Published private(set) var recordingSettings = RecordingSettings()
    @Published var configPublished: GatewayConfig

    private let _config = CurrentValueSubject<GatewayConfig, Never>(GatewayConfig())
    private var recordingSettingsReady = false

    var config: GatewayConfig { _config.value }

    var configFlow: AnyPublisher<GatewayConfig, Never> {
        _config.eraseToAnyPublisher()
    }

    var selectedProfile: AgentProfile {
        profiles.first { $0.id == selectedProfileId } ?? profiles[0]
    }

    var hasMultipleProfiles: Bool {
        profiles.count >= 2
    }

    var canAddProfile: Bool {
        profiles.count < Self.maxAgentProfiles
    }

    var primaryRecordingProfile: AgentProfile? {
        configuredProfiles.first { $0.id == recordingSettings.primaryAgentProfileId } ?? configuredProfiles.first
    }

    private var configuredProfiles: [AgentProfile] {
        profiles.filter { !$0.backendId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    var globalAsrMode: String {
        let value = defaults.string(forKey: "asr_mode") ?? selectedProfile.asrMode
        return value == "backend" ? "backend" : "router"
    }

    var globalAsrProfileId: String {
        defaults.string(forKey: "asr_profile_id") ?? selectedProfile.asrProfileId
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let legacyConfig = Self.loadLegacyConfig(from: defaults)
        let loadedProfiles = Self.loadProfiles(from: defaults, key: profilesKey)
        let initialProfiles: [AgentProfile]
        if loadedProfiles.isEmpty {
            initialProfiles = [Self.makeLegacyProfile(from: legacyConfig)]
        } else {
            initialProfiles = loadedProfiles.map { profile in
                var copy = profile
                copy.asrMode = legacyConfig.asrMode == "backend" ? "backend" : "router"
                copy.asrProfileId = legacyConfig.asrProfileId
                return copy
            }.sortedForAgentList()
        }
        let initialSelectedProfileId = defaults.string(forKey: selectedProfileIdKey)
            .flatMap { id in initialProfiles.contains(where: { $0.id == id }) ? id : nil }
            ?? initialProfiles[0].id

        let activeConfig = Self.makeConfig(
            from: initialProfiles.first { $0.id == initialSelectedProfileId } ?? initialProfiles[0],
            deviceLabel: legacyConfig.deviceLabel,
            defaults: defaults
        )
        let sortedInitialProfiles = initialProfiles.sortedForAgentList()
        profiles = sortedInitialProfiles
        selectedProfileId = initialSelectedProfileId
        recordingSettings = Self.loadRecordingSettings(from: defaults, profiles: sortedInitialProfiles)
        recordingSettingsReady = true
        configPublished = activeConfig
        _config.send(activeConfig)
        persistProfiles()
    }

    func updateConfig(_ config: GatewayConfig) {
        defaults.set(config.accountId, forKey: "account_id")
        defaults.set(config.accessToken, forKey: "access_token")
        defaults.set(config.refreshToken, forKey: "refresh_token")
        defaults.set(config.accessExpiresAt, forKey: "access_expires_at")
        defaults.set(config.refreshExpiresAt, forKey: "refresh_expires_at")
        defaults.set(config.deviceLabel, forKey: "device_label")
        defaults.set(config.lastLoginMode, forKey: "last_login_mode")
        defaults.set(config.lastPhoneNumber, forKey: "last_phone_number")
        var profile = selectedProfile
        profile.gatewayUrl = config.gatewayUrl
        profile.backendId = config.pairedBackendId ?? profile.backendId
        profile.backendLabel = config.pairedBackendLabel
        profile.token = config.token
        profile.isPaired = config.pairedBackendId != nil
        profile.asrMode = config.asrMode == "backend" ? "backend" : "router"
        profile.asrProfileId = config.asrProfileId
        profile.updatedAt = Date()
        replaceProfile(profile, select: true)
        updateGlobalAsr(mode: config.asrMode, profileId: config.asrProfileId)
        mirrorLegacyKeys(from: profile)
    }

    func updateDeviceLabel(_ label: String) {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        defaults.set(trimmed.isEmpty ? "我的设备" : trimmed, forKey: "device_label")
        publishActiveConfig()
    }

    func updateRecordingSettings(_ settings: RecordingSettings) {
        var normalized = settings
        normalized.primaryAgentProfileId = resolvedPrimaryRecordingProfileId(settings.primaryAgentProfileId)
        if normalized.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            normalized.prompt = RecordingSettings.defaultPrompt
        }
        recordingSettings = normalized
        persistRecordingSettings()
    }

    func setLastLoginMode(_ mode: String) {
        defaults.set(mode, forKey: "last_login_mode")
        var updatedConfig = configPublished
        updatedConfig.lastLoginMode = mode
        _config.send(updatedConfig)
        configPublished = updatedConfig
    }

    func updateGatewayUrl(_ url: String) {
        var profile = selectedProfile
        profile.gatewayUrl = url
        profile.updatedAt = Date()
        replaceProfile(profile, select: true)
    }

    func updatePairedBackend(_ backendId: String?, _ backendLabel: String?) {
        updatePairedBackend(backendId, backendLabel, profileId: selectedProfileId)
    }

    func updatePairedBackend(_ backendId: String?, _ backendLabel: String?, profileId: String?) {
        guard let profileId, let index = profiles.firstIndex(where: { $0.id == profileId }) else { return }
        profiles[index].backendId = backendId ?? profiles[index].backendId
        profiles[index].backendLabel = backendLabel
        profiles[index].isPaired = backendId != nil
        profiles[index].updatedAt = Date()
        persistProfiles()
        if profileId == selectedProfileId {
            mirrorLegacyKeys(from: profiles[index])
            publishActiveConfig()
        }
    }

    func selectProfile(_ profileId: String) {
        guard profiles.contains(where: { $0.id == profileId }) else { return }
        selectedProfileId = profileId
        defaults.set(profileId, forKey: selectedProfileIdKey)
        publishActiveConfig()
    }

    func deleteProfile(_ profileId: String) {
        guard profiles.count > 1 else { return }
        profiles.removeAll { $0.id == profileId }
        profiles = profiles.sortedForAgentList()
        if selectedProfileId == profileId {
            selectedProfileId = profiles[0].id
            defaults.set(selectedProfileId, forKey: selectedProfileIdKey)
        }
        persistProfiles()
        publishActiveConfig()
    }

    func updateProfile(_ profile: AgentProfile) {
        replaceProfile(profile, select: profile.id == selectedProfileId)
    }

    @discardableResult
    func saveProfile(_ profile: AgentProfile, select: Bool = true) -> Bool {
        var normalizedProfile = profile
        normalizedProfile.asrMode = globalAsrMode
        normalizedProfile.asrProfileId = globalAsrProfileId
        normalizedProfile.updatedAt = Date()

        if let index = profiles.firstIndex(where: { $0.id == normalizedProfile.id }) {
            profiles[index] = normalizedProfile
        } else {
            guard profiles.count < Self.maxAgentProfiles else { return false }
            guard isGatewayCompatible(normalizedProfile.gatewayUrl) else { return false }
            normalizedProfile.sortIndex = nextSortIndex()
            profiles.append(normalizedProfile)
        }

        if select {
            selectedProfileId = normalizedProfile.id
            defaults.set(normalizedProfile.id, forKey: selectedProfileIdKey)
        }
        profiles = profiles.sortedForAgentList()
        persistProfiles()
        publishActiveConfig()
        return true
    }

    func clearProfile(_ profileId: String) {
        guard let index = profiles.firstIndex(where: { $0.id == profileId }) else { return }
        var cleared = profiles[index]
        cleared.platform = .openclaw
        cleared.displayName = AgentPlatform.openclaw.defaultDisplayName
        cleared.gatewayUrl = "wss://boson-tech.top/ws"
        cleared.backendId = ""
        cleared.backendLabel = nil
        cleared.token = ""
        cleared.isPaired = false
        cleared.asrMode = globalAsrMode
        cleared.asrProfileId = globalAsrProfileId
        cleared.isPinned = false
        cleared.updatedAt = Date()
        profiles[index] = cleared
        profiles = profiles.sortedForAgentList()
        if selectedProfileId == profileId {
            persistProfiles()
            publishActiveConfig()
        } else {
            persistProfiles()
        }
    }

    func updateGlobalAsr(mode: String, profileId: String) {
        let normalizedMode = mode == "backend" ? "backend" : "router"
        defaults.set(normalizedMode, forKey: "asr_mode")
        defaults.set(normalizedMode == "router" ? profileId : "", forKey: "asr_profile_id")
        for index in profiles.indices {
            profiles[index].asrMode = normalizedMode
            profiles[index].asrProfileId = normalizedMode == "router" ? profileId : ""
            profiles[index].updatedAt = Date()
        }
        profiles = profiles.sortedForAgentList()
        persistProfiles()
        publishActiveConfig()
    }

    func setProfilePinned(_ profileId: String, isPinned: Bool) {
        guard let index = profiles.firstIndex(where: { $0.id == profileId }) else { return }
        profiles[index].isPinned = isPinned
        if isPinned {
            profiles[index].sortIndex = nextPinnedSortIndex()
        }
        profiles[index].updatedAt = Date()
        profiles = profiles.sortedForAgentList()
        persistProfiles()
        publishActiveConfig()
    }

    func canAcceptProfile(gatewayUrl: String, backendId: String) -> Bool {
        let normalizedKey = "\(AgentProfile.normalizedGatewayKey(gatewayUrl))|\(backendId)"
        if profiles.contains(where: { $0.uniqueBackendKey == normalizedKey }) {
            return true
        }
        if profiles.count == 1, profiles[0].backendId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        guard profiles.count < Self.maxAgentProfiles else { return false }
        return isGatewayCompatible(gatewayUrl)
    }

    func profileAcceptError(gatewayUrl: String, backendId: String) -> String? {
        if canAcceptProfile(gatewayUrl: gatewayUrl, backendId: backendId) {
            return nil
        }
        if profiles.count >= Self.maxAgentProfiles {
            return "最多支持 \(Self.maxAgentProfiles) 个 Agent"
        }
        if !isGatewayCompatible(gatewayUrl) {
            return "当前版本仅支持同一 Gateway 下最多 \(Self.maxAgentProfiles) 个 Agent"
        }
        return "无法新增 Agent"
    }

    func upsertProfile(
        gatewayUrl: String,
        backendId: String,
        token: String,
        platform: AgentPlatform,
        label: String?
    ) -> AgentProfile? {
        let displayName = resolvedProfileName(platform: platform, label: label, backendId: backendId)
        let normalizedKey = "\(AgentProfile.normalizedGatewayKey(gatewayUrl))|\(backendId)"

        if let index = profiles.firstIndex(where: { $0.uniqueBackendKey == normalizedKey }) {
            profiles[index].platform = platform
            profiles[index].displayName = displayName
            profiles[index].gatewayUrl = gatewayUrl
            profiles[index].backendId = backendId
            profiles[index].backendLabel = label ?? backendId
            profiles[index].token = token
            profiles[index].updatedAt = Date()
            selectedProfileId = profiles[index].id
            profiles = profiles.sortedForAgentList()
            persistProfiles()
            publishActiveConfig()
            return profiles.first { $0.id == selectedProfileId }
        }

        if profiles.count == 1, profiles[0].backendId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            profiles[0].platform = platform
            profiles[0].displayName = displayName
            profiles[0].gatewayUrl = gatewayUrl
            profiles[0].backendId = backendId
            profiles[0].backendLabel = label ?? backendId
            profiles[0].token = token
            profiles[0].isPaired = false
            profiles[0].sortIndex = profiles[0].sortIndex == 0 ? nextSortIndex() : profiles[0].sortIndex
            profiles[0].updatedAt = Date()
            selectedProfileId = profiles[0].id
            profiles = profiles.sortedForAgentList()
            persistProfiles()
            publishActiveConfig()
            return profiles.first { $0.id == selectedProfileId }
        }

        guard profiles.count < Self.maxAgentProfiles, isGatewayCompatible(gatewayUrl) else {
            return nil
        }

        let id = UUID().uuidString
        let profile = AgentProfile(
            id: id,
            platform: platform,
            displayName: displayName,
            gatewayUrl: gatewayUrl,
            backendId: backendId,
            backendLabel: label ?? backendId,
            token: token,
            isPaired: false,
            asrMode: globalAsrMode,
            asrProfileId: globalAsrProfileId,
            sortIndex: nextSortIndex()
        )
        profiles.append(profile)
        selectedProfileId = profile.id
        profiles = profiles.sortedForAgentList()
        persistProfiles()
        publishActiveConfig()
        return profile
    }

    private func replaceProfile(_ profile: AgentProfile, select: Bool) {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        let normalizedProfile = profile
        profiles[index] = normalizedProfile
        profiles = profiles.sortedForAgentList()
        if select {
            selectedProfileId = normalizedProfile.id
            defaults.set(normalizedProfile.id, forKey: selectedProfileIdKey)
        }
        persistProfiles()
        publishActiveConfig()
    }

    private func isGatewayCompatible(_ gatewayUrl: String) -> Bool {
        let target = AgentProfile.normalizedGatewayKey(gatewayUrl)
        let configuredGateways = profiles
            .filter { !$0.backendId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { AgentProfile.normalizedGatewayKey($0.gatewayUrl) }
        guard let first = configuredGateways.first else { return true }
        return configuredGateways.allSatisfy { $0 == first } && first == target
    }

    private func nextSortIndex() -> Int {
        (profiles.map(\.sortIndex).max() ?? 0) + 1
    }

    private func nextPinnedSortIndex() -> Int {
        (profiles.filter(\.isPinned).map(\.sortIndex).max() ?? 0) + 1
    }

    private func persistProfiles() {
        if let data = try? JSONEncoder().encode(profiles) {
            defaults.set(data, forKey: profilesKey)
        }
        defaults.set(selectedProfileId, forKey: selectedProfileIdKey)
        if recordingSettingsReady {
            reconcileRecordingPrimaryAgent()
        }
    }

    private func publishActiveConfig() {
        let active = selectedProfile
        let deviceLabel = defaults.string(forKey: "device_label") ?? "我的设备"
        let config = Self.makeConfig(from: active, deviceLabel: deviceLabel, defaults: defaults)
        _config.send(config)
        configPublished = config
        mirrorLegacyKeys(from: active)
    }

    private func persistRecordingSettings() {
        defaults.set(recordingSettings.primaryAgentProfileId, forKey: primaryRecordingAgentProfileIdKey)
        defaults.set(recordingSettings.deliverToAgent, forKey: recordingDeliverToAgentKey)
        defaults.set(recordingSettings.prompt, forKey: recordingPromptKey)
        defaults.set(recordingSettings.asrProfileId, forKey: recordingAsrProfileIdKey)
    }

    private func reconcileRecordingPrimaryAgent() {
        let resolved = hasExplicitPrimaryRecordingAgent
            ? resolvedPrimaryRecordingProfileId(recordingSettings.primaryAgentProfileId)
            : (configuredProfiles.first?.id ?? "")
        guard resolved != recordingSettings.primaryAgentProfileId else { return }
        recordingSettings.primaryAgentProfileId = resolved
        if hasExplicitPrimaryRecordingAgent {
            persistRecordingSettings()
        }
    }

    private func resolvedPrimaryRecordingProfileId(_ requestedId: String) -> String {
        if configuredProfiles.contains(where: { $0.id == requestedId }) {
            return requestedId
        }
        return configuredProfiles.first?.id ?? ""
    }

    private var hasExplicitPrimaryRecordingAgent: Bool {
        guard let saved = defaults.string(forKey: primaryRecordingAgentProfileIdKey) else { return false }
        return !saved.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func mirrorLegacyKeys(from profile: AgentProfile) {
        defaults.set(profile.gatewayUrl, forKey: "gateway_url")
        defaults.set(profile.token, forKey: "token")
        defaults.set(profile.asrMode, forKey: "asr_mode")
        defaults.set(profile.asrProfileId, forKey: "asr_profile_id")
        if profile.isPaired, !profile.backendId.isEmpty {
            defaults.set(profile.backendId, forKey: "paired_backend_id")
        } else {
            defaults.removeObject(forKey: "paired_backend_id")
        }
        if let backendLabel = profile.backendLabel {
            defaults.set(backendLabel, forKey: "paired_backend_label")
        } else {
            defaults.removeObject(forKey: "paired_backend_label")
        }
    }

    private func resolvedProfileName(platform: AgentPlatform, label: String?, backendId: String) -> String {
        if let label, !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return label
        }
        if platform != .custom {
            return platform.defaultDisplayName
        }
        return backendId
    }

    private static func loadProfiles(from defaults: UserDefaults, key: String) -> [AgentProfile] {
        guard let data = defaults.data(forKey: key),
              let profiles = try? JSONDecoder().decode([AgentProfile].self, from: data),
              !profiles.isEmpty else {
            return []
        }
        return profiles
    }

    private static func loadLegacyConfig(from defaults: UserDefaults) -> GatewayConfig {
        GatewayConfig(
            gatewayUrl: defaults.string(forKey: "gateway_url") ?? "wss://boson-tech.top/ws",
            accountId: defaults.string(forKey: "account_id") ?? "",
            accessToken: defaults.string(forKey: "access_token") ?? "",
            refreshToken: defaults.string(forKey: "refresh_token") ?? "",
            accessExpiresAt: defaults.string(forKey: "access_expires_at") ?? "",
            refreshExpiresAt: defaults.string(forKey: "refresh_expires_at") ?? "",
            deviceLabel: defaults.string(forKey: "device_label") ?? "",
            token: defaults.string(forKey: "token") ?? "",
            pairedBackendId: defaults.string(forKey: "paired_backend_id"),
            pairedBackendLabel: defaults.string(forKey: "paired_backend_label"),
            asrMode: defaults.string(forKey: "asr_mode") ?? "router",
            asrProfileId: defaults.string(forKey: "asr_profile_id") ?? "",
            lastLoginMode: defaults.string(forKey: "last_login_mode") ?? "",
            lastPhoneNumber: defaults.string(forKey: "last_phone_number") ?? ""
        )
    }

    private static func makeLegacyProfile(from config: GatewayConfig) -> AgentProfile {
        let backendId = config.pairedBackendId ?? ""
        return AgentProfile(
            platform: .openclaw,
            displayName: config.pairedBackendLabel ?? AgentPlatform.openclaw.defaultDisplayName,
            gatewayUrl: config.gatewayUrl,
            backendId: backendId,
            backendLabel: config.pairedBackendLabel,
            token: config.token,
            isPaired: config.pairedBackendId != nil,
            asrMode: config.asrMode,
            asrProfileId: config.asrProfileId
        )
    }

    private static func loadRecordingSettings(from defaults: UserDefaults, profiles: [AgentProfile]) -> RecordingSettings {
        let configuredProfiles = profiles.filter { !$0.backendId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let savedPrimaryId = defaults.string(forKey: "primary_agent_profile_id") ?? ""
        let primaryAgentProfileId = configuredProfiles.contains(where: { $0.id == savedPrimaryId })
            ? savedPrimaryId
            : (configuredProfiles.first?.id ?? "")
        let savedPrompt = defaults.string(forKey: "recording_prompt") ?? ""
        let prompt = savedPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? RecordingSettings.defaultPrompt
            : savedPrompt
        let deliverToAgent = defaults.object(forKey: "recording_deliver_to_agent") as? Bool ?? true
        let recordingAsrProfileId = defaults.string(forKey: "recording_asr_profile_id")
            ?? defaults.string(forKey: "asr_profile_id")
            ?? ""
        return RecordingSettings(
            primaryAgentProfileId: primaryAgentProfileId,
            deliverToAgent: deliverToAgent,
            prompt: prompt,
            asrProfileId: recordingAsrProfileId
        )
    }

    private static func makeConfig(from profile: AgentProfile, deviceLabel: String, defaults: UserDefaults) -> GatewayConfig {
        GatewayConfig(
            gatewayUrl: profile.gatewayUrl,
            accountId: defaults.string(forKey: "account_id") ?? "",
            accessToken: defaults.string(forKey: "access_token") ?? "",
            refreshToken: defaults.string(forKey: "refresh_token") ?? "",
            accessExpiresAt: defaults.string(forKey: "access_expires_at") ?? "",
            refreshExpiresAt: defaults.string(forKey: "refresh_expires_at") ?? "",
            deviceLabel: deviceLabel.isEmpty ? "我的设备" : deviceLabel,
            token: profile.token,
            pairedBackendId: profile.backendId.isEmpty ? nil : profile.backendId,
            pairedBackendLabel: profile.backendLabel ?? profile.resolvedDisplayName,
            asrMode: profile.asrMode,
            asrProfileId: profile.asrProfileId,
            lastLoginMode: defaults.string(forKey: "last_login_mode") ?? "",
            lastPhoneNumber: defaults.string(forKey: "last_phone_number") ?? ""
        )
    }
}
