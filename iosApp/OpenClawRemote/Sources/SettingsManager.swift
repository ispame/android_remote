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
    private let recordingDefaultTypeKey = "recording_default_type"
    private let recordingCustomPromptKey = "recording_custom_prompt"
    private let soundPlaybackEnabledKey = "sound_playback_enabled_v1"
    private let aiServiceSettingsKey = "ai_service_settings_v1"
    private let agentTtsMigratedKey = "agent_tts_migrated_v1"
    private let credentialVault: CredentialVault

    @Published private(set) var profiles: [AgentProfile]
    @Published private(set) var selectedProfileId: String
    @Published private(set) var aiSettings: AiServiceSettings
    @Published private(set) var recordingSettings = RecordingSettings()
    @Published private(set) var soundPlaybackEnabled: Bool
    @Published var configPublished: GatewayConfig

    private let _config = CurrentValueSubject<GatewayConfig, Never>(GatewayConfig())
    private var recordingSettingsReady = false

    var config: GatewayConfig { _config.value }

    var configFlow: AnyPublisher<GatewayConfig, Never> {
        _config.eraseToAnyPublisher()
    }

    func config(forProfileId profileId: String) -> GatewayConfig {
        let profile = profiles.first { $0.id == profileId } ?? selectedProfile
        let deviceLabel = defaults.string(forKey: "device_label") ?? "我的设备"
        return Self.makeConfig(from: profile, deviceLabel: deviceLabel, defaults: defaults)
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
        return value == "backend" || value == "byok" ? value : "router"
    }

    var globalAsrProfileId: String {
        defaults.string(forKey: "asr_profile_id") ?? selectedProfile.asrProfileId
    }

    init(defaults: UserDefaults = .standard, credentialVault: CredentialVault = KeychainCredentialVault()) {
        self.defaults = defaults
        self.credentialVault = credentialVault
        let legacyConfig = Self.loadLegacyConfig(from: defaults)
        let loadedProfiles = Self.loadProfiles(from: defaults, key: profilesKey)
        let loadedAiSettings = Self.loadAiSettings(from: defaults, key: aiServiceSettingsKey, legacyConfig: legacyConfig)
        let shouldMigrateAgentTts = !defaults.bool(forKey: agentTtsMigratedKey)
        var initialProfiles: [AgentProfile]
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
        if shouldMigrateAgentTts {
            initialProfiles = initialProfiles.map { profile in
                var copy = profile
                Self.applyLegacyTts(from: legacyConfig, to: &copy)
                return copy
            }
            defaults.set(true, forKey: agentTtsMigratedKey)
        }
        Self.migrateLocalMiniMaxCredential(from: legacyConfig, profiles: initialProfiles, defaults: defaults, vault: credentialVault)
        initialProfiles = Self.injectLocalMiniMaxCredential(into: initialProfiles, vault: credentialVault)
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
        aiSettings = loadedAiSettings
        recordingSettings = Self.loadRecordingSettings(from: defaults, profiles: sortedInitialProfiles)
        soundPlaybackEnabled = defaults.object(forKey: soundPlaybackEnabledKey) as? Bool ?? true
        recordingSettingsReady = true
        configPublished = activeConfig
        _config.send(activeConfig)
        persistProfiles()
    }

    func updateConfig(
        _ config: GatewayConfig,
        clearProfilesOnAccountChange: Bool = true
    ) {
        storeLocalMiniMaxCredential(config.minimaxApiKey)
        let previousAccountId = defaults.string(forKey: "account_id") ?? ""
        let accountChanged = !previousAccountId.isEmpty && previousAccountId != config.accountId
        defaults.set(config.accountId, forKey: "account_id")
        defaults.set(config.accessToken, forKey: "access_token")
        defaults.set(config.refreshToken, forKey: "refresh_token")
        defaults.set(config.accessExpiresAt, forKey: "access_expires_at")
        defaults.set(config.refreshExpiresAt, forKey: "refresh_expires_at")
        defaults.set(config.deviceLabel, forKey: "device_label")
        defaults.set(config.lastLoginMode, forKey: "last_login_mode")
        defaults.set(config.lastPhoneNumber, forKey: "last_phone_number")
        if accountChanged {
            if clearProfilesOnAccountChange {
                let profile = AgentProfile(
                    platform: .openclaw,
                    displayName: AgentPlatform.openclaw.defaultDisplayName,
                    gatewayUrl: config.gatewayUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "wss://boson-tech.top/ws" : config.gatewayUrl,
                    backendId: "",
                    backendLabel: nil,
                    token: "",
                    isPaired: false,
                    asrMode: config.asrMode == "backend" ? "backend" : "router",
                    asrProfileId: config.asrMode == "backend" ? "" : config.asrProfileId
                )
                profiles = [profile]
                selectedProfileId = profile.id
                defaults.set(profile.id, forKey: selectedProfileIdKey)
                persistProfiles()
                updateGlobalAsr(mode: config.asrMode, profileId: config.asrProfileId)
                updateAiSettings(Self.aiSettings(from: config), publish: false)
                mirrorLegacyKeys(from: selectedProfile)
                return
            }
            // 保留本地 profiles：只同步全局 ASR / AI 设置，让后续 replaceProfile 同步 selectedProfile 字段
            updateGlobalAsr(mode: config.asrMode, profileId: config.asrProfileId)
            updateAiSettings(Self.aiSettings(from: config), publish: false)
        }
        var profile = selectedProfile
        profile.gatewayUrl = config.gatewayUrl
        profile.backendId = config.pairedBackendId ?? profile.backendId
        profile.backendLabel = config.pairedBackendLabel
        profile.token = config.token
        profile.isPaired = config.pairedBackendId != nil
        profile.asrMode = config.asrMode == "backend" ? "backend" : "router"
        profile.asrProfileId = config.asrProfileId
        profile.ttsEngine = Self.normalizedTtsEngine(config.ttsEngine)
        profile.minimaxApiKey = localMiniMaxApiKey()
        profile.minimaxVoiceId = config.minimaxVoiceId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "male-qn-qingse" : config.minimaxVoiceId
        profile.updatedAt = Date()
        replaceProfile(profile, select: true)
        updateGlobalAsr(mode: config.asrMode, profileId: config.asrProfileId)
        updateAiSettings(Self.aiSettings(from: config), publish: false)
        mirrorLegacyKeys(from: profile)
    }

    func replaceAccountProfiles(_ serverProfiles: [GatewayAccountAgentProfile]) {
        let existingById = profiles.reduce(into: [String: AgentProfile]()) { result, profile in
            result[profile.id] = profile
        }
        let existingByBackendKey = profiles.reduce(into: [String: AgentProfile]()) { result, profile in
            result[profile.uniqueBackendKey] = profile
        }
        let mapped = serverProfiles
            .filter { !$0.backendId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { profile in
                var mappedProfile = AgentProfile(
                    id: profile.agentProfileId,
                    platform: AgentPlatform(rawValue: profile.platform) ?? .openclaw,
                    displayName: profile.displayName,
                    gatewayUrl: profile.gatewayUrl,
                    backendId: profile.backendId,
                    backendLabel: profile.backendLabel,
                    token: "",
                    isPaired: profile.isPaired,
                    asrMode: profile.asrMode == "backend" ? "backend" : "router",
                    asrProfileId: "",
                    isPinned: profile.pinned,
                    sortIndex: profile.sortOrder
                )
                let backendKey = mappedProfile.uniqueBackendKey
                if let existing = existingById[mappedProfile.id] ?? existingByBackendKey[backendKey] {
                    // server 端不返 token / minimax key，只返元数据。
                    // 保留本地这些字段，避免「退出登录保留 token → 重新登录被 server 同步清空」。
                    if !existing.token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        mappedProfile.token = existing.token
                    }
                    mappedProfile.ttsEngine = existing.ttsEngine
                    mappedProfile.minimaxApiKey = existing.minimaxApiKey
                    mappedProfile.minimaxVoiceId = existing.minimaxVoiceId
                }
                return mappedProfile
            }
        guard !mapped.isEmpty else { return }
        profiles = mapped.sortedForAgentList()
        selectedProfileId = profiles[0].id
        defaults.set(selectedProfileId, forKey: selectedProfileIdKey)
        persistProfiles()
        publishActiveConfig()
    }

    func updateSoundPlaybackEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: soundPlaybackEnabledKey)
        soundPlaybackEnabled = enabled
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
        if normalized.defaultRecordingType == .custom,
           normalized.customPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            normalized.defaultRecordingType = .audioOnly
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
        applyLocalMiniMaxCredential(to: &normalizedProfile)

        if let index = profiles.firstIndex(where: { $0.id == normalizedProfile.id }) {
            let previousProfile = profiles[index]
            if Self.connectionIdentityChanged(from: previousProfile, to: normalizedProfile) {
                normalizedProfile.isPaired = false
                if Self.trimmed(previousProfile.backendId) != Self.trimmed(normalizedProfile.backendId) {
                    normalizedProfile.backendLabel = Self.trimmed(normalizedProfile.backendId).isEmpty
                        ? nil
                        : Self.trimmed(normalizedProfile.backendId)
                }
            }
            profiles[index] = normalizedProfile
        } else {
            guard profiles.count < Self.maxAgentProfiles else { return false }
            guard isGatewayCompatible(normalizedProfile.gatewayUrl) else { return false }
            normalizedProfile.isPaired = false
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
        cleared.ttsEngine = "system"
        cleared.minimaxApiKey = ""
        cleared.minimaxVoiceId = "male-qn-qingse"
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
        updateAiSettings(
            AiServiceSettings(
                defaults: AiServiceDefaults(
                    llm: aiSettings.defaults.llm,
                    asr: AiServiceChoice(mode: normalizedMode, profileId: normalizedMode == "router" ? profileId : ""),
                    tts: aiSettings.defaults.tts
                ),
                agentOverrides: aiSettings.agentOverrides
            ),
            publish: false
        )
        for index in profiles.indices {
            profiles[index].asrMode = normalizedMode
            profiles[index].asrProfileId = normalizedMode == "router" ? profileId : ""
            profiles[index].updatedAt = Date()
        }
        profiles = profiles.sortedForAgentList()
        persistProfiles()
        publishActiveConfig()
    }

    func updateAiSettings(_ settings: AiServiceSettings, publish: Bool = true) {
        let normalized = Self.normalizedAiSettings(settings)
        aiSettings = normalized
        if let data = try? JSONEncoder().encode(normalized) {
            defaults.set(data, forKey: aiServiceSettingsKey)
        }
        defaults.set(normalized.defaults.asr.mode, forKey: "asr_mode")
        defaults.set(normalized.defaults.asr.mode == "router" ? normalized.defaults.asr.profileId : "", forKey: "asr_profile_id")
        defaults.set(normalized.defaults.tts.mode == "byok" && normalized.defaults.tts.providerId == "minimax" ? "minimax" : "system", forKey: "tts_engine")
        defaults.set(normalized.defaults.tts.voiceId.isEmpty ? "male-qn-qingse" : normalized.defaults.tts.voiceId, forKey: "minimax_voice_id")
        defaults.removeObject(forKey: "minimax_api_key")
        applyAiSettingsToProfiles(normalized)
        if publish {
            publishActiveConfig()
        }
    }

    func upsertAiServiceConfig(_ config: AiServiceConfig, publish: Bool = true) {
        updateAiSettings(aiSettings.upsertingServiceConfig(config), publish: publish)
    }

    func updateAiSceneSelection(
        providerChatLlmConfigId: String? = nil,
        recordingAsrConfigId: String? = nil,
        playbackTtsConfigId: String? = nil,
        publish: Bool = true
    ) {
        updateAiSettings(
            aiSettings.updatingSceneSelection(
                providerChatLlmConfigId: providerChatLlmConfigId,
                recordingAsrConfigId: recordingAsrConfigId,
                playbackTtsConfigId: playbackTtsConfigId
            ),
            publish: publish
        )
    }

    func updateLocalCredential(id: String, apiKey: String) {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            credentialVault.removeSecret(for: id)
        } else {
            credentialVault.setSecret(trimmed, for: id)
        }
        if id == localMiniMaxCredentialId {
            defaults.removeObject(forKey: "minimax_api_key")
            profiles = Self.injectLocalMiniMaxCredential(into: profiles, vault: credentialVault)
            persistProfiles()
            publishActiveConfig()
        }
    }

    func localCredential(id: String) -> String? {
        let secret = credentialVault.secret(for: id)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return secret.isEmpty ? nil : secret
    }

    func updateLocalTtsCredential(providerId: String, apiKey: String) {
        guard providerId == "minimax" else { return }
        updateLocalCredential(id: localMiniMaxCredentialId, apiKey: apiKey)
    }

    func localTtsCredential(providerId: String) -> String? {
        guard providerId == "minimax" else { return nil }
        return localCredential(id: localMiniMaxCredentialId)
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
            let previousProfile = profiles[index]
            profiles[index].platform = platform
            profiles[index].displayName = displayName
            profiles[index].gatewayUrl = gatewayUrl
            profiles[index].backendId = backendId
            profiles[index].backendLabel = label ?? backendId
            profiles[index].token = token
            if Self.connectionIdentityChanged(from: previousProfile, to: profiles[index]) {
                profiles[index].isPaired = false
            }
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
        var normalizedProfile = profile
        applyLocalMiniMaxCredential(to: &normalizedProfile)
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
        let profilesForStorage = profiles.map { profile in
            var copy = profile
            copy.minimaxApiKey = ""
            return copy
        }
        if let data = try? JSONEncoder().encode(profilesForStorage) {
            defaults.set(data, forKey: profilesKey)
        }
        defaults.set(selectedProfileId, forKey: selectedProfileIdKey)
        if recordingSettingsReady {
            reconcileRecordingPrimaryAgent()
        }
    }

    private func localMiniMaxApiKey() -> String {
        credentialVault.secret(for: localMiniMaxCredentialId) ?? ""
    }

    private func storeLocalMiniMaxCredential(_ apiKey: String) {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        credentialVault.setSecret(trimmed, for: localMiniMaxCredentialId)
        defaults.removeObject(forKey: "minimax_api_key")
    }

    private func applyLocalMiniMaxCredential(to profile: inout AgentProfile) {
        profile.ttsEngine = Self.normalizedTtsEngine(profile.ttsEngine)
        profile.minimaxVoiceId = profile.minimaxVoiceId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "male-qn-qingse"
            : profile.minimaxVoiceId
        if profile.ttsEngine == "minimax" {
            storeLocalMiniMaxCredential(profile.minimaxApiKey)
        }
        profile.minimaxApiKey = localMiniMaxApiKey()
    }

    private func applyAiSettingsToProfiles(_ settings: AiServiceSettings) {
        for index in profiles.indices {
            let resolved = settings.resolved(for: profiles[index].id)
            let resolvedAsrMode = resolved.asr.mode == "backend" || resolved.asr.mode == "byok" ? resolved.asr.mode : "router"
            let resolvedTtsEngine = resolved.tts.mode == "byok" && resolved.tts.providerId == "minimax" ? "minimax" : "system"
            profiles[index].asrMode = resolvedAsrMode
            profiles[index].asrProfileId = resolvedAsrMode == "router" ? resolved.asr.profileId : ""
            profiles[index].ttsEngine = resolvedTtsEngine
            profiles[index].minimaxVoiceId = resolved.tts.voiceId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "male-qn-qingse"
                : resolved.tts.voiceId
            profiles[index].minimaxApiKey = resolvedTtsEngine == "minimax" ? localMiniMaxApiKey() : ""
            profiles[index].updatedAt = Date()
        }
        persistProfiles()
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
        defaults.set(recordingSettings.defaultRecordingType.rawValue, forKey: recordingDefaultTypeKey)
        defaults.set(recordingSettings.customPrompt, forKey: recordingCustomPromptKey)
        defaults.set(recordingSettings.defaultDeliverToAgent, forKey: "recording_default_deliver_to_agent")
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
        defaults.set(Self.normalizedTtsEngine(profile.ttsEngine), forKey: "tts_engine")
        defaults.set(profile.minimaxVoiceId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "male-qn-qingse" : profile.minimaxVoiceId, forKey: "minimax_voice_id")
        defaults.removeObject(forKey: "minimax_api_key")
        if profile.isPaired, !profile.backendId.isEmpty {
            defaults.set(profile.backendId, forKey: "paired_backend_id")
        } else {
            defaults.removeObject(forKey: "paired_backend_id")
        }
        if profile.isPaired, let backendLabel = profile.backendLabel {
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

    private static func loadAiSettings(from defaults: UserDefaults, key: String, legacyConfig: GatewayConfig) -> AiServiceSettings {
        guard let data = defaults.data(forKey: key),
              let settings = try? JSONDecoder().decode(AiServiceSettings.self, from: data) else {
            return normalizedAiSettings(aiSettings(from: legacyConfig))
        }
        return normalizedAiSettings(settings)
    }

    private static func aiSettings(from config: GatewayConfig) -> AiServiceSettings {
        let llmProvider = AiProviderCatalog.llmByokProviders[0]
        let asrProvider = AiProviderCatalog.asrByokProviders[0]
        let ttsProvider = AiProviderCatalog.ttsByokProviders[0]
        return normalizedAiSettings(AiServiceSettings(
            defaults: AiServiceDefaults(
                llm: AiServiceChoice(
                    mode: "router",
                    profileId: "default",
                    providerId: llmProvider.id,
                    baseUrl: llmProvider.baseUrlDefault,
                    model: llmProvider.modelDefault,
                    credentialId: llmProvider.credentialId,
                    displayName: llmProvider.label
                ),
                asr: AiServiceChoice(
                    mode: config.asrMode == "backend" || config.asrMode == "byok" ? config.asrMode : "router",
                    profileId: config.asrMode == "router" ? config.asrProfileId : "",
                    providerId: asrProvider.id,
                    baseUrl: asrProvider.baseUrlDefault,
                    model: asrProvider.modelDefault,
                    credentialId: asrProvider.credentialId,
                    displayName: asrProvider.label
                ),
                tts: config.ttsEngine == "minimax"
                    ? AiServiceChoice(
                        mode: "byok",
                        providerId: ttsProvider.id,
                        voiceId: config.minimaxVoiceId.isEmpty ? "male-qn-qingse" : config.minimaxVoiceId,
                        baseUrl: ttsProvider.baseUrlDefault,
                        model: ttsProvider.modelDefault,
                        credentialId: ttsProvider.credentialId,
                        displayName: ttsProvider.label
                    )
                    : AiServiceChoice(mode: "system", providerId: "system", voiceId: "male-qn-qingse", credentialId: ttsProvider.credentialId)
            )
        ))
    }

    private static func normalizedAiSettings(_ settings: AiServiceSettings) -> AiServiceSettings {
        AiServiceSettings(
            version: settings.version,
            serviceConfigs: settings.serviceConfigs,
            sceneSelections: settings.sceneSelections,
            defaults: settings.defaults,
            agentOverrides: settings.agentOverrides
        )
    }

    private static func normalizedDefaults(_ defaults: AiServiceDefaults) -> AiServiceDefaults {
        AiServiceDefaults(
            llm: normalizedLlmChoice(defaults.llm),
            asr: normalizedAsrChoice(defaults.asr),
            tts: normalizedTtsChoice(defaults.tts)
        )
    }

    private static func normalizedLlmChoice(_ choice: AiServiceChoice) -> AiServiceChoice {
        let mode = choice.mode == "byok" || choice.mode == "agent" ? choice.mode : "router"
        let provider = AiProviderCatalog.llmProvider(id: choice.providerId) ?? AiProviderCatalog.llmByokProviders[0]
        let baseUrl = normalizedLlmBaseUrl(choice.baseUrl, provider: provider)
        return AiServiceChoice(
            mode: mode,
            profileId: mode == "router" ? (choice.profileId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "default" : choice.profileId) : choice.profileId,
            providerId: provider.id,
            voiceId: choice.voiceId,
            baseUrl: baseUrl,
            model: choice.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? provider.modelDefault : choice.model,
            credentialId: provider.credentialId,
            displayName: choice.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? provider.label : choice.displayName
        )
    }

    private static func normalizedLlmBaseUrl(_ baseUrl: String, provider: AiByokProviderTemplate) -> String {
        let trimmed = baseUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return provider.baseUrlDefault
        }
        if provider.id == "minimax" && trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "/")) == "https://api.minimax.com/v1" {
            return provider.baseUrlDefault
        }
        return trimmed
    }

    private static func normalizedAsrChoice(_ choice: AiServiceChoice) -> AiServiceChoice {
        let mode = choice.mode == "byok" || choice.mode == "backend" ? choice.mode : "router"
        let provider = AiProviderCatalog.asrProvider(id: choice.providerId) ?? AiProviderCatalog.asrByokProviders[0]
        return AiServiceChoice(
            mode: mode,
            profileId: mode == "router" ? choice.profileId : "",
            providerId: provider.id,
            voiceId: choice.voiceId,
            baseUrl: choice.baseUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? provider.baseUrlDefault : choice.baseUrl,
            model: choice.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? provider.modelDefault : choice.model,
            credentialId: provider.credentialId,
            displayName: choice.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? provider.label : choice.displayName
        )
    }

    private static func normalizedTtsChoice(_ choice: AiServiceChoice) -> AiServiceChoice {
        let provider = AiProviderCatalog.ttsProvider(id: choice.providerId) ?? AiProviderCatalog.ttsByokProviders[0]
        let isByok = choice.mode == "byok"
        let voiceId = choice.voiceId.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = choice.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return AiServiceChoice(
            mode: isByok ? "byok" : "system",
            profileId: "",
            providerId: isByok ? provider.id : "system",
            voiceId: voiceId.isEmpty ? "male-qn-qingse" : voiceId,
            baseUrl: isByok ? (choice.baseUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? provider.baseUrlDefault : choice.baseUrl) : "",
            model: isByok ? (choice.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? provider.modelDefault : choice.model) : "",
            credentialId: isByok ? provider.credentialId : localMiniMaxCredentialId,
            displayName: isByok ? (displayName.isEmpty ? provider.label : choice.displayName) : "系统 TTS"
        )
    }

    private static func migrateLocalMiniMaxCredential(
        from legacyConfig: GatewayConfig,
        profiles: [AgentProfile],
        defaults: UserDefaults,
        vault: CredentialVault
    ) {
        let legacyKey = legacyConfig.minimaxApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let profileKey = profiles
            .map { $0.minimaxApiKey.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? ""
        let key = legacyKey.isEmpty ? profileKey : legacyKey
        if !key.isEmpty {
            vault.setSecret(key, for: localMiniMaxCredentialId)
        }
        defaults.removeObject(forKey: "minimax_api_key")
    }

    private static func injectLocalMiniMaxCredential(into profiles: [AgentProfile], vault: CredentialVault) -> [AgentProfile] {
        let localKey = vault.secret(for: localMiniMaxCredentialId) ?? ""
        return profiles.map { profile in
            var copy = profile
            copy.minimaxApiKey = copy.ttsEngine == "minimax" ? localKey : ""
            return copy
        }
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
            ttsEngine: defaults.string(forKey: "tts_engine") ?? "system",
            minimaxApiKey: defaults.string(forKey: "minimax_api_key") ?? "",
            minimaxVoiceId: defaults.string(forKey: "minimax_voice_id") ?? "male-qn-qingse",
            lastLoginMode: defaults.string(forKey: "last_login_mode") ?? "",
            lastPhoneNumber: defaults.string(forKey: "last_phone_number") ?? ""
        )
    }

    private static func applyLegacyTts(from config: GatewayConfig, to profile: inout AgentProfile) {
        profile.ttsEngine = normalizedTtsEngine(config.ttsEngine)
        profile.minimaxApiKey = config.minimaxApiKey
        profile.minimaxVoiceId = config.minimaxVoiceId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "male-qn-qingse" : config.minimaxVoiceId
    }

    private static func normalizedTtsEngine(_ value: String) -> String {
        value == "minimax" ? "minimax" : "system"
    }

    private static func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func connectionIdentityChanged(from previous: AgentProfile, to next: AgentProfile) -> Bool {
        AgentProfile.normalizedGatewayKey(previous.gatewayUrl) != AgentProfile.normalizedGatewayKey(next.gatewayUrl)
            || trimmed(previous.backendId) != trimmed(next.backendId)
            || trimmed(previous.token) != trimmed(next.token)
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
            asrProfileId: config.asrProfileId,
            ttsEngine: normalizedTtsEngine(config.ttsEngine),
            minimaxApiKey: config.minimaxApiKey,
            minimaxVoiceId: config.minimaxVoiceId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "male-qn-qingse" : config.minimaxVoiceId
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
        let defaultRecordingType = defaults.string(forKey: "recording_default_type")
            .flatMap(RecordingType.init(rawValue:)) ?? .audioOnly
        let savedCustomPrompt = defaults.string(forKey: "recording_custom_prompt") ?? ""
        let customPrompt = savedCustomPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? (savedPrompt == RecordingSettings.defaultPrompt ? "" : savedPrompt)
            : savedCustomPrompt
        return RecordingSettings(
            primaryAgentProfileId: primaryAgentProfileId,
            deliverToAgent: deliverToAgent,
            prompt: prompt,
            asrProfileId: recordingAsrProfileId,
            defaultRecordingType: defaultRecordingType == .custom && customPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .audioOnly : defaultRecordingType,
            customPrompt: customPrompt,
            defaultDeliverToAgent: defaults.object(forKey: "recording_default_deliver_to_agent") as? Bool ?? true
        )
    }

    private static func makeConfig(from profile: AgentProfile, deviceLabel: String, defaults: UserDefaults) -> GatewayConfig {
        let pairedBackendId = profile.isPaired && !profile.backendId.isEmpty ? profile.backendId : nil
        return GatewayConfig(
            gatewayUrl: profile.gatewayUrl,
            accountId: defaults.string(forKey: "account_id") ?? "",
            accessToken: defaults.string(forKey: "access_token") ?? "",
            refreshToken: defaults.string(forKey: "refresh_token") ?? "",
            accessExpiresAt: defaults.string(forKey: "access_expires_at") ?? "",
            refreshExpiresAt: defaults.string(forKey: "refresh_expires_at") ?? "",
            deviceLabel: deviceLabel.isEmpty ? "我的设备" : deviceLabel,
            token: profile.token,
            pairedBackendId: pairedBackendId,
            pairedBackendLabel: pairedBackendId == nil ? nil : (profile.backendLabel ?? profile.resolvedDisplayName),
            asrMode: profile.asrMode,
            asrProfileId: profile.asrProfileId,
            ttsEngine: normalizedTtsEngine(profile.ttsEngine),
            minimaxApiKey: profile.minimaxApiKey,
            minimaxVoiceId: profile.minimaxVoiceId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "male-qn-qingse" : profile.minimaxVoiceId,
            lastLoginMode: defaults.string(forKey: "last_login_mode") ?? "",
            lastPhoneNumber: defaults.string(forKey: "last_phone_number") ?? ""
        )
    }
}
