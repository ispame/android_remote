import Foundation

@main
struct TtsBehaviorTests {
    static func main() throws {
        try testMutedPlaybackSkipsAssistantSpeech()
        try testManualSpeechPlaysWhenMutedWithoutChangingPreference()
        try testManualSpeechInterruptsCurrentPlaybackAndClearsQueuedReplies()
        try testQueuedAssistantRepliesPlayOneAtATimeInOrder()
        try testTurningSoundOffPersistsAndStopsCurrentPlayback()
        try testHeadsetWakeRestoresMutedPlaybackAndInterrupts()
        try testMiniMaxFailureFallsBackToSystemAndContinuesQueue()
        try testAssistantSpeechTriggerSkipsHistoryAndSpeaksNewAssistantReplies()
        try testMiniMaxRequestMatchesAndroidPayload()
        try testMiniMaxResponseParserDecodesHexAudio()
        try testMiniMaxResponseParserRejectsProviderErrors()
        try testMiniMaxVoiceCatalogBuildsSelectableVoices()
        try testSettingsManagerPersistsTtsDefaultsAndSoundPlaybackPreference()
        try testSettingsManagerPreservesRouterTtsModeForUnifiedSettings()
        try testSettingsManagerMigratesOldMiniMaxLlmHost()
        try testAgentProfileTtsDefaultsAndLegacyDecode()
        try testSettingsManagerMigratesLegacyGlobalTtsToAgentProfilesOnce()
        try testSettingsManagerBuildsProfileSpecificTtsConfig()
        print("TtsBehaviorTests passed")
    }

    private static func testMutedPlaybackSkipsAssistantSpeech() throws {
        let engine = FakeTtsEngine()
        let controller = SoundPlaybackController(
            ttsEngineProvider: { engine },
            initialSoundPlaybackEnabled: false
        )

        let didSpeak = controller.enqueueAssistantReplies(texts: ["长回复"], apiKey: nil, voiceId: nil)

        try expect(!didSpeak, "muted playback should skip automatic assistant speech")
        try expect(engine.spokenTexts.isEmpty, "engine should not receive muted automatic speech")
        try expect(!controller.isSpeaking, "muted automatic speech should not mark playback active")
    }

    private static func testManualSpeechPlaysWhenMutedWithoutChangingPreference() throws {
        let engine = FakeTtsEngine()
        var persisted: [Bool] = []
        let controller = SoundPlaybackController(
            ttsEngineProvider: { engine },
            initialSoundPlaybackEnabled: false,
            persistSoundPlaybackEnabled: { persisted.append($0) }
        )

        let didSpeak = controller.speakManualText(" 手动朗读 ", apiKey: "key", voiceId: "voice")

        try expect(didSpeak, "manual speech should play even when automatic playback is muted")
        try expect(engine.spokenTexts == ["手动朗读"], "manual speech should trim text before speaking")
        try expect(!controller.soundPlaybackEnabled, "manual speech should not change the mute preference")
        try expect(controller.isSpeaking, "manual speech should mark playback active")
        try expect(persisted.isEmpty, "manual speech should not persist a mute preference change")
    }

    private static func testManualSpeechInterruptsCurrentPlaybackAndClearsQueuedReplies() throws {
        let engine = FakeTtsEngine()
        let controller = SoundPlaybackController(ttsEngineProvider: { engine })
        _ = controller.enqueueAssistantReplies(texts: ["第一段", "第二段"], apiKey: nil, voiceId: nil)

        let didSpeak = controller.speakManualText("插播朗读", apiKey: nil, voiceId: nil)

        try expect(didSpeak, "manual speech should start after interrupting current playback")
        try expect(engine.stopCount == 1, "manual speech should stop the current engine")
        try expect(engine.spokenTexts == ["第一段", "插播朗读"], "manual speech should discard queued automatic replies")

        controller.markPlaybackFinished()

        try expect(!controller.isSpeaking, "manual speech completion should leave playback idle")
        try expect(engine.spokenTexts == ["第一段", "插播朗读"], "discarded queued replies should not play later")
    }

    private static func testQueuedAssistantRepliesPlayOneAtATimeInOrder() throws {
        let engine = FakeTtsEngine()
        let controller = SoundPlaybackController(ttsEngineProvider: { engine })

        let didSpeak = controller.enqueueAssistantReplies(texts: ["第一段", "第二段"], apiKey: "key", voiceId: "voice")

        try expect(didSpeak, "assistant replies should enqueue")
        try expect(engine.spokenTexts == ["第一段"], "only the first reply should start immediately")
        try expect(controller.isSpeaking, "first reply should mark playback active")

        controller.markPlaybackFinished()

        try expect(engine.spokenTexts == ["第一段", "第二段"], "second reply should start after first finishes")
        try expect(controller.isSpeaking, "second reply should keep playback active")

        controller.markPlaybackFinished()

        try expect(!controller.isSpeaking, "queue completion should mark playback idle")
    }

    private static func testTurningSoundOffPersistsAndStopsCurrentPlayback() throws {
        let engine = FakeTtsEngine()
        var persisted: [Bool] = []
        let controller = SoundPlaybackController(
            ttsEngineProvider: { engine },
            initialSoundPlaybackEnabled: true,
            persistSoundPlaybackEnabled: { persisted.append($0) }
        )
        _ = controller.enqueueAssistantReplies(texts: ["长回复", "后续回复"], apiKey: "key", voiceId: "voice")

        controller.setSoundPlaybackEnabled(false)

        try expect(persisted == [false], "turning sound off should persist the preference")
        try expect(engine.stopCount == 1, "turning sound off should stop current playback")
        try expect(!controller.soundPlaybackEnabled, "sound preference should be off")
        try expect(!controller.isSpeaking, "turning sound off should mark playback idle")

        controller.markPlaybackFinished()

        try expect(engine.spokenTexts == ["长回复"], "queued replies should be cleared when sound turns off")
    }

    private static func testHeadsetWakeRestoresMutedPlaybackAndInterrupts() throws {
        let engine = FakeTtsEngine()
        var persisted: [Bool] = []
        let controller = SoundPlaybackController(
            ttsEngineProvider: { engine },
            initialSoundPlaybackEnabled: false,
            persistSoundPlaybackEnabled: { persisted.append($0) }
        )

        controller.onHeadsetWake()

        try expect(persisted == [true], "headset wake should persistently re-enable playback")
        try expect(engine.stopCount == 1, "headset wake should interrupt any current playback")
        try expect(controller.soundPlaybackEnabled, "headset wake should leave playback enabled")
        try expect(!controller.isSpeaking, "headset wake should leave playback idle")
    }

    private static func testMiniMaxFailureFallsBackToSystemAndContinuesQueue() throws {
        let minimax = FakeTtsEngine()
        let system = FakeTtsEngine()
        let controller = SoundPlaybackController(
            ttsEngineProvider: { minimax },
            fallbackTtsEngineProvider: { system },
            shouldUseFallback: { _ in true }
        )

        _ = controller.enqueueAssistantReplies(texts: ["第一段", "第二段"], apiKey: "key", voiceId: "voice")

        try expect(minimax.spokenTexts == ["第一段"], "MiniMax should receive the first request")
        try expect(system.spokenTexts.isEmpty, "system fallback should stay idle until failure")

        controller.markPlaybackFailed(TestFailure("usage limit exceeded"))

        try expect(system.spokenTexts == ["第一段"], "system fallback should replay the failed request")
        try expect(controller.isSpeaking, "fallback playback should keep state active")

        controller.markPlaybackFinished()

        try expect(minimax.spokenTexts == ["第一段", "第二段"], "queue should continue with primary engine after fallback completes")

        controller.markPlaybackFinished()

        try expect(!controller.isSpeaking, "queue should finish after fallback and remaining primary playback")
    }

    private static func testAssistantSpeechTriggerSkipsHistoryAndSpeaksNewAssistantReplies() throws {
        let trigger = AssistantSpeechTrigger()
        let history = [
            message("old user", senderId: "user", clientMessageId: "u1"),
            message("old reply", senderId: "assistant", clientMessageId: "a1")
        ]

        try expect(trigger.onMessagesChanged(history).isEmpty, "initial history should not be spoken")

        let afterUser = history + [message("new user", senderId: "user", clientMessageId: "u2")]
        try expect(trigger.onMessagesChanged(afterUser).isEmpty, "user messages should not be spoken")

        let withReply = afterUser + [message("new reply", senderId: "assistant", clientMessageId: "a2")]
        try expect(trigger.onMessagesChanged(withReply).map(\.content) == ["new reply"], "assistant reply after current user message should be spoken")
        try expect(trigger.onMessagesChanged(withReply).isEmpty, "same assistant reply should not be spoken twice")
    }

    private static func testMiniMaxRequestMatchesAndroidPayload() throws {
        let request = MiniMaxTtsRequestBuilder.build(text: "你好", voiceId: "voice-1")

        try expect(request["model"] as? String == "speech-2.8-hd", "MiniMax model should match Android")
        try expect(request["text"] as? String == "你好", "MiniMax text should be included")
        try expect(request["stream"] as? Bool == false, "MiniMax should use non-streaming mode")
        try expect(request["output_format"] as? String == "hex", "MiniMax should request hex audio")

        let voiceSetting = try expectDictionary(request["voice_setting"], "voice_setting should be a dictionary")
        try expect(voiceSetting["voice_id"] as? String == "voice-1", "voice id should be included")
        try expect(voiceSetting["speed"] as? Double == 1.0, "voice speed should match Android")
        try expect(voiceSetting["vol"] as? Double == 1.0, "voice volume should match Android")
        try expect(voiceSetting["pitch"] as? Double == 0.0, "voice pitch should match Android")
        try expect(voiceSetting["emotion"] as? String == "happy", "voice emotion should match Android")

        let audioSetting = try expectDictionary(request["audio_setting"], "audio_setting should be a dictionary")
        try expect(audioSetting["sample_rate"] as? Int == 32_000, "sample rate should match Android")
        try expect(audioSetting["bitrate"] as? Int == 128_000, "bitrate should match Android")
        try expect(audioSetting["format"] as? String == "mp3", "format should match Android")
        try expect(audioSetting["channel"] as? Int == 1, "channel count should match Android")
    }

    private static func testMiniMaxResponseParserDecodesHexAudio() throws {
        let parsed = try MiniMaxTtsResponseParser.parse("""
        {
          "trace_id": "trace-1",
          "data": {"audio": "fff30010"},
          "extra_info": {
            "audio_format": "mp3",
            "audio_size": 4,
            "audio_sample_rate": 32000,
            "audio_channel": 1
          },
          "base_resp": {"status_code": 0, "status_msg": "success"}
        }
        """)

        try expect(parsed.traceId == "trace-1", "trace id should parse")
        try expect(parsed.audioBytes == Data([0xFF, 0xF3, 0x00, 0x10]), "hex audio should decode into bytes")
        try expect(parsed.audioFormat == "mp3", "audio format should parse")
        try expect(parsed.sampleRate == 32_000, "sample rate should parse")
        try expect(parsed.channelCount == 1, "channel count should parse")
    }

    private static func testMiniMaxResponseParserRejectsProviderErrors() throws {
        do {
            _ = try MiniMaxTtsResponseParser.parse("""
            {"trace_id":"trace-2","base_resp":{"status_code":1001,"status_msg":"bad key"}}
            """)
            throw TestFailure("provider error should throw")
        } catch {
            try expect(String(describing: error).contains("status_code=1001"), "provider error should include status code")
        }
    }

    private static func testMiniMaxVoiceCatalogBuildsSelectableVoices() throws {
        try expect(MiniMaxVoiceCatalog.builtinVoices.contains { $0.id == MiniMaxVoiceCatalog.defaultVoiceId }, "builtins should include default voice")

        let selectable = MiniMaxVoiceCatalog.buildSelectableVoices(
            currentVoiceId: "custom-voice",
            fetchedVoices: [MiniMaxVoiceOption(id: "fetched", name: "Fetched", category: "系统音色")]
        )

        try expect(selectable.first == MiniMaxVoiceOption(id: "custom-voice", name: "custom-voice", category: "当前配置"), "current unknown voice should be kept at the front")
        try expect(selectable.contains(MiniMaxVoiceOption(id: "fetched", name: "Fetched", category: "系统音色")), "fetched voices should be selectable")
    }

    private static func testSettingsManagerPersistsTtsDefaultsAndSoundPlaybackPreference() throws {
        let suiteName = "TtsBehaviorTests-\(UUID().uuidString)"
        let defaults = try expectNotNil(UserDefaults(suiteName: suiteName), "test defaults suite should be available")
        let vault = FakeCredentialVault()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let manager = SettingsManager(defaults: defaults, credentialVault: vault)
        try expect(manager.config.ttsEngine == "system", "default TTS engine should be system")
        try expect(manager.config.minimaxApiKey == "", "default MiniMax API key should be empty")
        try expect(manager.config.minimaxVoiceId == MiniMaxVoiceCatalog.defaultVoiceId, "default MiniMax voice should match catalog default")
        try expect(manager.soundPlaybackEnabled, "sound playback should default to enabled")

        var config = manager.config
        config.ttsEngine = "minimax"
        config.minimaxApiKey = "key"
        config.minimaxVoiceId = "voice"
        manager.updateConfig(config)
        manager.updateSoundPlaybackEnabled(false)

        let reloaded = SettingsManager(defaults: defaults, credentialVault: vault)
        try expect(reloaded.config.ttsEngine == "minimax", "TTS engine should persist")
        try expect(reloaded.config.minimaxApiKey == "key", "MiniMax API key should persist")
        try expect(reloaded.config.minimaxVoiceId == "voice", "MiniMax voice should persist")
        try expect(defaults.string(forKey: "minimax_api_key") == nil, "MiniMax API key should not persist in UserDefaults")
        try expect(!reloaded.soundPlaybackEnabled, "sound playback preference should persist")
    }

    private static func testSettingsManagerPreservesRouterTtsModeForUnifiedSettings() throws {
        let suiteName = "TtsBehaviorTests-\(UUID().uuidString)"
        let defaults = try expectNotNil(UserDefaults(suiteName: suiteName), "test defaults suite should be available")
        let vault = FakeCredentialVault()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let manager = SettingsManager(defaults: defaults, credentialVault: vault)
        manager.updateAiSettings(AiServiceSettings(
            defaults: AiServiceDefaults(
                llm: AiServiceChoice(mode: "router", profileId: "default"),
                asr: AiServiceChoice(mode: "router", profileId: "volcengine-streaming"),
                tts: AiServiceChoice(
                    mode: "router",
                    profileId: "router-tts-default",
                    providerId: "router",
                    voiceId: "router-voice"
                )
            )
        ))

        try expect(manager.aiSettings.defaults.tts.mode == "router", "unified AI settings should preserve Router TTS mode")
        try expect(manager.aiSettings.defaults.tts.providerId == "router", "Router TTS settings should keep router provider id")
        try expect(manager.config.ttsEngine == "system", "legacy playback projection should stay system until Router TTS playback is implemented")
    }

    private static func testSettingsManagerMigratesOldMiniMaxLlmHost() throws {
        let suiteName = "TtsBehaviorTests-\(UUID().uuidString)"
        let defaults = try expectNotNil(UserDefaults(suiteName: suiteName), "test defaults suite should be available")
        let vault = FakeCredentialVault()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let manager = SettingsManager(defaults: defaults, credentialVault: vault)
        manager.updateAiSettings(AiServiceSettings(
            defaults: AiServiceDefaults(
                llm: AiServiceChoice(
                    mode: "byok",
                    providerId: "minimax",
                    baseUrl: "https://api.minimax.com/v1/",
                    model: "MiniMax-M2.7",
                    credentialId: localLlmMiniMaxCredentialId
                ),
                asr: AiServiceChoice(mode: "router", profileId: ""),
                tts: AiServiceChoice(mode: "system", providerId: "system")
            ),
            agentOverrides: [
                "agent-minimax": AiAgentOverride(
                    inherit: false,
                    llm: AiServiceChoice(
                        mode: "byok",
                        providerId: "minimax",
                        baseUrl: "https://api.minimax.com/v1",
                        model: "MiniMax-M2.7",
                        credentialId: localLlmMiniMaxCredentialId
                    )
                )
            ]
        ))

        let reloaded = SettingsManager(defaults: defaults, credentialVault: vault)
        try expect(reloaded.aiSettings.defaults.llm.baseUrl == "https://api.minimaxi.com/v1", "saved MiniMax LLM defaults should migrate to the documented China endpoint")
        try expect(reloaded.aiSettings.agentOverrides["agent-minimax"]?.llm?.baseUrl == "https://api.minimaxi.com/v1", "saved MiniMax LLM overrides should migrate to the documented China endpoint")
    }

    private static func testAgentProfileTtsDefaultsAndLegacyDecode() throws {
        let profile = AgentProfile(backendId: "agent-a")
        try expect(profile.ttsEngine == "system", "new Agent profiles should default to system TTS")
        try expect(profile.minimaxApiKey == "", "new Agent profiles should default to an empty MiniMax key")
        try expect(profile.minimaxVoiceId == MiniMaxVoiceCatalog.defaultVoiceId, "new Agent profiles should default to the MiniMax catalog voice")

        let legacy = LegacyAgentProfile(id: "legacy-a", displayName: "Legacy", backendId: "legacy-backend")
        let data = try JSONEncoder().encode([legacy])
        let decoded = try JSONDecoder().decode([AgentProfile].self, from: data)

        try expect(decoded.count == 1, "legacy profile fixture should decode")
        try expect(decoded[0].ttsEngine == "system", "legacy Agent profile without TTS fields should decode to system TTS")
        try expect(decoded[0].minimaxApiKey == "", "legacy Agent profile without MiniMax key should decode to empty key")
        try expect(decoded[0].minimaxVoiceId == MiniMaxVoiceCatalog.defaultVoiceId, "legacy Agent profile without voice should decode to default voice")
    }

    private static func testSettingsManagerMigratesLegacyGlobalTtsToAgentProfilesOnce() throws {
        let suiteName = "TtsBehaviorTests-\(UUID().uuidString)"
        let defaults = try expectNotNil(UserDefaults(suiteName: suiteName), "test defaults suite should be available")
        let vault = FakeCredentialVault()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set("minimax", forKey: "tts_engine")
        defaults.set("legacy-key", forKey: "minimax_api_key")
        defaults.set("legacy-voice", forKey: "minimax_voice_id")
        let legacyProfiles = [
            LegacyAgentProfile(id: "agent-a", displayName: "Agent A", backendId: "backend-a"),
            LegacyAgentProfile(id: "agent-b", displayName: "Agent B", backendId: "backend-b")
        ]
        defaults.set(try JSONEncoder().encode(legacyProfiles), forKey: "agent_profiles_v1")
        defaults.set("agent-a", forKey: "selected_agent_profile_id")

        let migrated = SettingsManager(defaults: defaults, credentialVault: vault)

        try expect(migrated.profiles.count == 2, "legacy persisted profiles should load")
        try expect(migrated.profiles.allSatisfy { $0.ttsEngine == "minimax" }, "legacy global TTS engine should migrate to all Agent profiles")
        try expect(migrated.profiles.allSatisfy { $0.minimaxApiKey == "legacy-key" }, "legacy global MiniMax key should migrate to all Agent profiles")
        try expect(migrated.profiles.allSatisfy { $0.minimaxVoiceId == "legacy-voice" }, "legacy global voice should migrate to all Agent profiles")
        try expect(defaults.bool(forKey: "agent_tts_migrated_v1"), "migration should write a one-time marker")

        var customized = try expectNotNil(migrated.profiles.first { $0.id == "agent-a" }, "agent-a should exist after migration")
        customized.ttsEngine = "system"
        customized.minimaxApiKey = ""
        customized.minimaxVoiceId = MiniMaxVoiceCatalog.defaultVoiceId
        migrated.updateProfile(customized)

        let reloaded = SettingsManager(defaults: defaults, credentialVault: vault)
        let reloadedAgent = try expectNotNil(reloaded.profiles.first { $0.id == "agent-a" }, "agent-a should exist after reload")
        try expect(reloadedAgent.ttsEngine == "system", "migration should not overwrite later per-Agent edits")
        try expect(reloadedAgent.minimaxApiKey == "", "migration should not restore the legacy global key after edits")
        try expect(reloadedAgent.minimaxVoiceId == MiniMaxVoiceCatalog.defaultVoiceId, "migration should not restore the legacy global voice after edits")
    }

    private static func testSettingsManagerBuildsProfileSpecificTtsConfig() throws {
        let suiteName = "TtsBehaviorTests-\(UUID().uuidString)"
        let defaults = try expectNotNil(UserDefaults(suiteName: suiteName), "test defaults suite should be available")
        let vault = FakeCredentialVault()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let manager = SettingsManager(defaults: defaults, credentialVault: vault)
        var first = manager.selectedProfile
        first.ttsEngine = "minimax"
        first.minimaxApiKey = "key-a"
        first.minimaxVoiceId = "voice-a"
        manager.updateProfile(first)

        let second = AgentProfile(
            id: "agent-b",
            platform: .hermes,
            displayName: "Agent B",
            backendId: "backend-b",
            ttsEngine: "minimax",
            minimaxApiKey: "key-b",
            minimaxVoiceId: "voice-b"
        )
        try expect(manager.saveProfile(second, select: false), "second profile should save")

        let firstConfig = manager.config(forProfileId: first.id)
        let secondConfig = manager.config(forProfileId: "agent-b")

        try expect(firstConfig.ttsEngine == "minimax", "first profile config should use its own TTS engine")
        try expect(firstConfig.minimaxApiKey == "key-a", "first profile config should use its own API key")
        try expect(firstConfig.minimaxVoiceId == "voice-a", "first profile config should use its own voice")
        try expect(secondConfig.ttsEngine == "minimax", "second profile config should use its own TTS engine")
        try expect(secondConfig.minimaxApiKey == "key-b", "second profile config should use its own API key")
        try expect(secondConfig.minimaxVoiceId == "voice-b", "second profile config should use its own voice")

        manager.selectProfile("agent-b")
        try expect(manager.config.minimaxApiKey == "key-b", "active GatewayConfig projection should follow selected Agent TTS")
    }

    private static func message(_ content: String, senderId: String, clientMessageId: String) -> ChatMessage {
        ChatMessage(content: content, timestamp: clientMessageId, senderId: senderId, clientMessageId: clientMessageId)
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() {
            throw TestFailure(message)
        }
    }

    private static func expectDictionary(_ value: Any?, _ message: String) throws -> [String: Any] {
        guard let dictionary = value as? [String: Any] else {
            throw TestFailure(message)
        }
        return dictionary
    }

    private static func expectNotNil<T>(_ value: T?, _ message: String) throws -> T {
        guard let value else {
            throw TestFailure(message)
        }
        return value
    }
}

private struct LegacyAgentProfile: Codable {
    var id: String
    var platform: AgentPlatform = .openclaw
    var displayName: String
    var gatewayUrl: String = "wss://boson-tech.top/ws"
    var backendId: String
    var backendLabel: String? = nil
    var token: String = ""
    var isPaired: Bool = true
    var asrMode: String = "router"
    var asrProfileId: String = ""
    var createdAt: Date = Date(timeIntervalSinceReferenceDate: 0)
    var updatedAt: Date = Date(timeIntervalSinceReferenceDate: 0)
    var isPinned: Bool = false
    var sortIndex: Int = 0
}

struct GatewayAccountAgentProfile: Codable {
    var agentProfileId: String
    var platform: String
    var displayName: String
    var gatewayUrl: String
    var backendId: String
    var backendLabel: String?
    var isPaired: Bool
    var asrMode: String
    var pinned: Bool
    var sortOrder: Int
}

private final class FakeTtsEngine: TtsEngine {
    var onSpeakStart: (() -> Void)?
    var onSpeakDone: (() -> Void)?
    var onSpeakError: ((Error) -> Void)?

    private(set) var stopCount = 0
    private(set) var spokenTexts: [String] = []

    func speak(text: String, apiKey _: String?, voiceId _: String?) -> Bool {
        spokenTexts.append(text)
        return true
    }

    func stop() {
        stopCount += 1
    }

    func releaseResources() {}
}

private final class FakeCredentialVault: CredentialVault {
    private var values: [String: String] = [:]

    func secret(for id: String) -> String? {
        values[id]
    }

    func setSecret(_ secret: String, for id: String) {
        let trimmed = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            values.removeValue(forKey: id)
        } else {
            values[id] = trimmed
        }
    }

    func removeSecret(for id: String) {
        values.removeValue(forKey: id)
    }
}

private struct TestFailure: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}
