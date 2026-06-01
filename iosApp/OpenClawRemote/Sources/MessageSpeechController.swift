import AVFoundation
import Combine
import Foundation

protocol TtsEngine: AnyObject {
    var onSpeakStart: (() -> Void)? { get set }
    var onSpeakDone: (() -> Void)? { get set }
    var onSpeakError: ((Error) -> Void)? { get set }

    @discardableResult
    func speak(text: String, apiKey: String?, voiceId: String?) -> Bool
    func stop()
    func releaseResources()
}

final class SoundPlaybackController: ObservableObject {
    @Published private(set) var soundPlaybackEnabled: Bool
    @Published private(set) var isSpeaking = false

    private let externalTtsEngineProvider: (() -> TtsEngine?)?
    private let externalFallbackTtsEngineProvider: (() -> TtsEngine?)?
    private let shouldUseFallbackOverride: ((Error) -> Bool)?
    private let persistSoundPlaybackEnabled: (Bool) -> Void

    private var activeTtsEngine: TtsEngine?
    private var activeEngineKey: TtsEngineKey?
    private var systemFallbackTtsEngine: TtsEngine?
    private var currentConfig = GatewayConfig()
    private var queue: [SpeechRequest] = []
    private var currentRequest: SpeechRequest?

    init(
        ttsEngineProvider: (() -> TtsEngine?)? = nil,
        fallbackTtsEngineProvider: (() -> TtsEngine?)? = nil,
        shouldUseFallback: ((Error) -> Bool)? = nil,
        initialSoundPlaybackEnabled: Bool = true,
        persistSoundPlaybackEnabled: @escaping (Bool) -> Void = { _ in }
    ) {
        externalTtsEngineProvider = ttsEngineProvider
        externalFallbackTtsEngineProvider = fallbackTtsEngineProvider
        shouldUseFallbackOverride = shouldUseFallback
        self.persistSoundPlaybackEnabled = persistSoundPlaybackEnabled
        soundPlaybackEnabled = initialSoundPlaybackEnabled
    }

    static func normalizedText(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func syncSoundPlaybackEnabled(_ enabled: Bool) {
        applySoundPlaybackEnabled(enabled, persist: false)
    }

    func setSoundPlaybackEnabled(_ enabled: Bool) {
        applySoundPlaybackEnabled(enabled, persist: true)
    }

    func syncConfiguration(_ config: GatewayConfig) {
        currentConfig = config
        guard externalTtsEngineProvider == nil else { return }

        let nextKey: TtsEngineKey = config.ttsEngine == TtsEngineKey.minimax.rawValue ? .minimax : .system
        if activeEngineKey == nextKey, activeTtsEngine != nil { return }

        let nextEngine: TtsEngine
        switch nextKey {
        case .system:
            nextEngine = ensureSystemFallbackTtsEngine()
        case .minimax:
            nextEngine = MiniMaxTtsEngine()
            configureCallbacks(for: nextEngine)
        }

        if activeTtsEngine !== nextEngine {
            interruptCurrentPlayback()
            if let activeTtsEngine, activeTtsEngine !== systemFallbackTtsEngine {
                activeTtsEngine.releaseResources()
            }
            activeTtsEngine = nextEngine
            activeEngineKey = nextKey
        }
    }

    func speak(_ text: String) {
        syncConfiguration(currentConfig)
        let credentials = speechCredentials(for: currentConfig)
        _ = speakManualText(text, apiKey: credentials.apiKey, voiceId: credentials.voiceId)
    }

    @discardableResult
    func speakManualText(_ text: String, config: GatewayConfig) -> Bool {
        syncConfiguration(config)
        let credentials = speechCredentials(for: config)
        return speakManualText(text, apiKey: credentials.apiKey, voiceId: credentials.voiceId)
    }

    @discardableResult
    func speakManualText(_ text: String, apiKey: String?, voiceId: String?) -> Bool {
        guard let spokenText = Self.normalizedText(text) else { return false }

        interruptCurrentPlayback()
        queue.append(SpeechRequest(text: spokenText, apiKey: apiKey, voiceId: voiceId))
        startNextIfIdle()
        return currentRequest != nil
    }

    @discardableResult
    func speakAssistantReply(_ text: String, config: GatewayConfig) -> Bool {
        enqueueAssistantReplies(texts: [text], config: config)
    }

    @discardableResult
    func enqueueAssistantReplies(texts: [String], config: GatewayConfig) -> Bool {
        syncConfiguration(config)
        let credentials = speechCredentials(for: config)
        return enqueueAssistantReplies(texts: texts, apiKey: credentials.apiKey, voiceId: credentials.voiceId)
    }

    @discardableResult
    func enqueueAssistantReplies(texts: [String], apiKey: String?, voiceId: String?) -> Bool {
        guard soundPlaybackEnabled else { return false }
        let requests = texts.compactMap { text -> SpeechRequest? in
            guard let spokenText = Self.normalizedText(text) else { return nil }
            return SpeechRequest(text: spokenText, apiKey: apiKey, voiceId: voiceId)
        }
        guard !requests.isEmpty else { return false }

        queue.append(contentsOf: requests)
        startNextIfIdle()
        return true
    }

    func interruptCurrentPlayback() {
        queue.removeAll()
        currentRequest = nil
        ttsEngineProvider()?.stop()
        fallbackTtsEngineProvider()?.stop()
        markPlaybackFinished()
    }

    func onHeadsetWake() {
        if !soundPlaybackEnabled {
            setSoundPlaybackEnabled(true)
        }
        interruptCurrentPlayback()
    }

    func markPlaybackStarted() {
        dispatchOnMainIfNeeded {
            self.isSpeaking = true
        }
    }

    func markPlaybackFinished() {
        dispatchOnMainIfNeeded {
            self.currentRequest = nil
            self.startNextIfIdle()
            if self.currentRequest == nil {
                self.isSpeaking = false
            }
        }
    }

    func markPlaybackFailed(_ error: Error) {
        dispatchOnMainIfNeeded {
            let failedRequest = self.currentRequest
            let shouldUseFallback = self.shouldUseFallbackOverride?(error) ?? self.shouldFallbackToSystemTts(error)
            if let failedRequest,
               !failedRequest.isFallback,
               shouldUseFallback,
               let fallbackEngine = self.fallbackTtsEngineProvider() {
                let fallbackRequest = failedRequest.withFallback()
                self.currentRequest = fallbackRequest
                if fallbackEngine.speak(text: fallbackRequest.text, apiKey: nil, voiceId: nil) {
                    self.markPlaybackStarted()
                    return
                }
            }

            self.currentRequest = nil
            self.startNextIfIdle()
            if self.currentRequest == nil {
                self.isSpeaking = false
            }
        }
    }

    func release() {
        if let activeTtsEngine, activeTtsEngine !== systemFallbackTtsEngine {
            activeTtsEngine.releaseResources()
        }
        systemFallbackTtsEngine?.releaseResources()
        activeTtsEngine = nil
        systemFallbackTtsEngine = nil
    }

    private func applySoundPlaybackEnabled(_ enabled: Bool, persist: Bool) {
        let previous = soundPlaybackEnabled
        if !enabled {
            interruptCurrentPlayback()
        }
        soundPlaybackEnabled = enabled
        if persist, previous != enabled {
            persistSoundPlaybackEnabled(enabled)
        }
    }

    private func startNextIfIdle() {
        guard currentRequest == nil else { return }
        guard !queue.isEmpty else { return }
        let request = queue.removeFirst()
        guard let engine = ttsEngineProvider() else {
            currentRequest = request
            markPlaybackFailed(TtsPlaybackError.engineUnavailable)
            return
        }

        currentRequest = request
        if engine.speak(text: request.text, apiKey: request.apiKey, voiceId: request.voiceId) {
            markPlaybackStarted()
            return
        }
        markPlaybackFailed(TtsPlaybackError.engineRejectedPlayback)
    }

    private func ttsEngineProvider() -> TtsEngine? {
        externalTtsEngineProvider?() ?? activeTtsEngine ?? ensureSystemFallbackTtsEngine()
    }

    private func fallbackTtsEngineProvider() -> TtsEngine? {
        externalFallbackTtsEngineProvider?() ?? ensureSystemFallbackTtsEngine()
    }

    private func ensureSystemFallbackTtsEngine() -> TtsEngine {
        if let systemFallbackTtsEngine { return systemFallbackTtsEngine }
        let engine = SystemTtsEngine()
        configureCallbacks(for: engine)
        systemFallbackTtsEngine = engine
        return engine
    }

    private func configureCallbacks(for engine: TtsEngine) {
        engine.onSpeakStart = { [weak self] in
            self?.markPlaybackStarted()
        }
        engine.onSpeakDone = { [weak self] in
            self?.markPlaybackFinished()
        }
        engine.onSpeakError = { [weak self] error in
            self?.markPlaybackFailed(error)
        }
    }

    private func speechCredentials(for config: GatewayConfig) -> (apiKey: String?, voiceId: String?) {
        guard config.ttsEngine == TtsEngineKey.minimax.rawValue else {
            return (nil, nil)
        }
        return (config.minimaxApiKey, config.minimaxVoiceId)
    }

    private func shouldFallbackToSystemTts(_ error: Error) -> Bool {
        guard currentConfig.ttsEngine == TtsEngineKey.minimax.rawValue else { return false }
        let message = String(describing: error).lowercased()
        if message.isEmpty { return true }
        return [
            "usage limit",
            "provider error",
            "api key",
            "minimax api error",
            "empty response",
            "rejected",
            "failed",
            "audio",
            "playback"
        ].contains { message.contains($0) }
    }

    private func dispatchOnMainIfNeeded(_ work: @escaping () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }

    private enum TtsEngineKey: String {
        case system
        case minimax
    }

    private struct SpeechRequest {
        var text: String
        var apiKey: String?
        var voiceId: String?
        var isFallback = false

        func withFallback() -> SpeechRequest {
            SpeechRequest(text: text, apiKey: nil, voiceId: nil, isFallback: true)
        }
    }
}

typealias MessageSpeechController = SoundPlaybackController

final class SystemTtsEngine: NSObject, TtsEngine, AVSpeechSynthesizerDelegate {
    var onSpeakStart: (() -> Void)?
    var onSpeakDone: (() -> Void)?
    var onSpeakError: ((Error) -> Void)?

    private let synthesizer = AVSpeechSynthesizer()

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(text: String, apiKey _: String?, voiceId _: String?) -> Bool {
        guard let spokenText = SoundPlaybackController.normalizedText(text) else { return false }
        configureAudioSession()
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: spokenText)
        utterance.voice = AVSpeechSynthesisVoice(language: "zh-CN") ?? AVSpeechSynthesisVoice(language: Locale.current.identifier)
        utterance.rate = 0.48
        utterance.pitchMultiplier = 1.0
        synthesizer.speak(utterance)
        return true
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    func releaseResources() {
        stop()
        synthesizer.delegate = nil
    }

    func speechSynthesizer(_: AVSpeechSynthesizer, didStart _: AVSpeechUtterance) {
        onSpeakStart?()
    }

    func speechSynthesizer(_: AVSpeechSynthesizer, didFinish _: AVSpeechUtterance) {
        onSpeakDone?()
    }

    func speechSynthesizer(_: AVSpeechSynthesizer, didCancel _: AVSpeechUtterance) {
        onSpeakDone?()
    }

    private func configureAudioSession() {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetoothHFP, .allowBluetoothA2DP])
        try? session.setActive(true)
        #endif
    }
}

final class MiniMaxTtsEngine: NSObject, TtsEngine, AVAudioPlayerDelegate {
    var onSpeakStart: (() -> Void)?
    var onSpeakDone: (() -> Void)?
    var onSpeakError: ((Error) -> Void)?

    private var speakTask: Task<Void, Never>?
    private var audioPlayer: AVAudioPlayer?

    func speak(text: String, apiKey: String?, voiceId: String?) -> Bool {
        guard let spokenText = SoundPlaybackController.normalizedText(text) else { return false }
        guard let apiKey = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines), !apiKey.isEmpty else {
            return false
        }

        stop()
        onSpeakStart?()
        let resolvedVoiceId = voiceId?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? MiniMaxVoiceCatalog.defaultVoiceId
        speakTask = Task { [weak self] in
            guard let self else { return }
            do {
                let audioData = try await MiniMaxTtsEngine.fetchTtsAudio(text: spokenText, apiKey: apiKey, voiceId: resolvedVoiceId)
                try Task.checkCancellation()
                try await self.playMp3Audio(audioData)
            } catch is CancellationError {
                return
            } catch {
                await MainActor.run {
                    self.onSpeakError?(error)
                }
            }
        }
        return true
    }

    func stop() {
        speakTask?.cancel()
        speakTask = nil
        audioPlayer?.stop()
        audioPlayer = nil
    }

    func releaseResources() {
        stop()
    }

    func audioPlayerDidFinishPlaying(_: AVAudioPlayer, successfully flag: Bool) {
        audioPlayer = nil
        if flag {
            onSpeakDone?()
        } else {
            onSpeakError?(TtsPlaybackError.audioPlaybackFailed)
        }
    }

    func audioPlayerDecodeErrorDidOccur(_: AVAudioPlayer, error: Error?) {
        audioPlayer = nil
        onSpeakError?(error ?? TtsPlaybackError.audioPlaybackFailed)
    }

    private static func fetchTtsAudio(text: String, apiKey: String, voiceId: String) async throws -> Data {
        let requestBody = MiniMaxTtsRequestBuilder.build(text: text, voiceId: voiceId)
        let bodyData = try JSONSerialization.data(withJSONObject: requestBody)
        var request = URLRequest(url: URL(string: "https://api.minimaxi.com/v1/t2a_v2")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TtsPlaybackError.emptyResponse
        }
        let responseText = String(data: data, encoding: .utf8) ?? ""
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw TtsPlaybackError.minimaxApiError(statusCode: httpResponse.statusCode, body: responseText)
        }
        return try MiniMaxTtsResponseParser.parse(responseText).audioBytes
    }

    @MainActor
    private func playMp3Audio(_ mp3Data: Data) throws {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetoothHFP, .allowBluetoothA2DP])
        try? session.setActive(true)
        #endif

        let player = try AVAudioPlayer(data: mp3Data)
        player.delegate = self
        player.prepareToPlay()
        audioPlayer = player
        guard player.play() else {
            audioPlayer = nil
            throw TtsPlaybackError.audioPlaybackFailed
        }
    }
}

final class AssistantSpeechTrigger {
    private var hasSeenCurrentUserMessage = false
    private var lastObservedMessageKey: String?
    private var spokenAssistantKeys = Set<String>()

    func onMessagesChanged(_ messages: [ChatMessage]) -> [ChatMessage] {
        guard !messages.isEmpty else { return [] }
        let previousKey = lastObservedMessageKey
        let lastKey = speechKey(for: messages[messages.count - 1])
        guard previousKey != lastKey else { return [] }
        guard let previousKey else {
            if messages.last?.senderId == "user" {
                hasSeenCurrentUserMessage = true
            }
            lastObservedMessageKey = lastKey
            return []
        }
        guard let startIndex = messages.lastIndex(where: { speechKey(for: $0) == previousKey }) else {
            lastObservedMessageKey = lastKey
            return []
        }

        var messagesToSpeak: [ChatMessage] = []
        for message in messages.dropFirst(startIndex + 1) {
            let key = speechKey(for: message)
            if message.senderId == "user" {
                hasSeenCurrentUserMessage = true
                continue
            }
            if message.senderId == "assistant",
               !message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               hasSeenCurrentUserMessage,
               !spokenAssistantKeys.contains(key) {
                spokenAssistantKeys.insert(key)
                messagesToSpeak.append(message)
            }
        }

        lastObservedMessageKey = lastKey
        return messagesToSpeak
    }

    private func speechKey(for message: ChatMessage) -> String {
        message.clientMessageId ?? "\(message.senderId)|\(message.timestamp)|\(message.content)"
    }
}

struct MiniMaxVoiceOption: Equatable, Identifiable {
    var id: String
    var name: String
    var category: String
}

enum MiniMaxVoiceCatalog {
    static let defaultVoiceId = "male-qn-qingse"

    static let builtinVoices: [MiniMaxVoiceOption] = [
        MiniMaxVoiceOption(id: "male-qn-qingse", name: "青涩青年音色", category: "中文"),
        MiniMaxVoiceOption(id: "female-shaonv", name: "少女音色", category: "中文"),
        MiniMaxVoiceOption(id: "female-yujie", name: "御姐音色", category: "中文"),
        MiniMaxVoiceOption(id: "female-chengshu", name: "成熟女性音色", category: "中文"),
        MiniMaxVoiceOption(id: "female-tianmei", name: "甜美女性音色", category: "中文"),
        MiniMaxVoiceOption(id: "danya_xuejie", name: "淡雅学姐", category: "中文"),
        MiniMaxVoiceOption(id: "Chinese (Mandarin)_Reliable_Executive", name: "沉稳高管", category: "中文"),
        MiniMaxVoiceOption(id: "Chinese (Mandarin)_News_Anchor", name: "新闻女声", category: "中文"),
        MiniMaxVoiceOption(id: "Chinese (Mandarin)_Mature_Woman", name: "傲娇御姐", category: "中文"),
        MiniMaxVoiceOption(id: "Chinese (Mandarin)_HK_Flight_Attendant", name: "港普空姐", category: "中文"),
        MiniMaxVoiceOption(id: "Chinese (Mandarin)_Gentleman", name: "温润男声", category: "中文"),
        MiniMaxVoiceOption(id: "Chinese (Mandarin)_Warm_Girl", name: "温暖少女", category: "中文"),
        MiniMaxVoiceOption(id: "Chinese (Mandarin)_Lyrical_Voice", name: "抒情男声", category: "中文"),
        MiniMaxVoiceOption(id: "Cantonese_ProfessionalHost（F)", name: "专业女主持", category: "粤语"),
        MiniMaxVoiceOption(id: "Cantonese_GentleLady", name: "温柔女声", category: "粤语"),
        MiniMaxVoiceOption(id: "Cantonese_ProfessionalHost（M)", name: "专业男主持", category: "粤语"),
        MiniMaxVoiceOption(id: "Cantonese_PlayfulMan", name: "活泼男声", category: "粤语"),
        MiniMaxVoiceOption(id: "Cantonese_CuteGirl", name: "可爱女孩", category: "粤语"),
        MiniMaxVoiceOption(id: "Cantonese_KindWoman", name: "善良女声", category: "粤语"),
        MiniMaxVoiceOption(id: "Charming_Lady", name: "Charming Lady", category: "英文"),
        MiniMaxVoiceOption(id: "Sweet_Girl", name: "Sweet Girl", category: "英文"),
        MiniMaxVoiceOption(id: "Arnold", name: "Arnold", category: "英文"),
        MiniMaxVoiceOption(id: "Japanese_IntellectualSenior", name: "Intellectual Senior", category: "日文"),
        MiniMaxVoiceOption(id: "Japanese_DecisivePrincess", name: "Decisive Princess", category: "日文"),
        MiniMaxVoiceOption(id: "Japanese_LoyalKnight", name: "Loyal Knight", category: "日文"),
        MiniMaxVoiceOption(id: "Japanese_ColdQueen", name: "Cold Queen", category: "日文")
    ].uniqueBy(\.id)

    static func buildSelectableVoices(currentVoiceId: String, fetchedVoices: [MiniMaxVoiceOption]) -> [MiniMaxVoiceOption] {
        let baseVoices = fetchedVoices.isEmpty ? builtinVoices : fetchedVoices
        let trimmedCurrent = currentVoiceId.trimmingCharacters(in: .whitespacesAndNewlines)
        let current = !trimmedCurrent.isEmpty && !baseVoices.contains(where: { $0.id == trimmedCurrent })
            ? MiniMaxVoiceOption(id: trimmedCurrent, name: trimmedCurrent, category: "当前配置")
            : nil
        return ([current].compactMap { $0 } + baseVoices)
            .uniqueBy(\.id)
            .uniqueBy { "\($0.category.trimmingCharacters(in: .whitespacesAndNewlines))|\($0.name.trimmingCharacters(in: .whitespacesAndNewlines))".lowercased() }
    }

    static func fetchAvailableVoices(apiKey: String) async throws -> [MiniMaxVoiceOption] {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { return [] }
        let bodyData = try JSONSerialization.data(withJSONObject: ["voice_type": "all"])
        var request = URLRequest(url: URL(string: "https://api.minimaxi.com/v1/get_voice")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData
        let (data, response) = try await URLSession.shared.data(for: request)
        let responseText = String(data: data, encoding: .utf8) ?? ""
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw TtsPlaybackError.minimaxApiError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? -1, body: responseText)
        }
        return try parseGetVoiceResponse(responseText)
    }

    static func parseGetVoiceResponse(_ responseBody: String) throws -> [MiniMaxVoiceOption] {
        let root = try JSONSerialization.jsonObject(with: Data(responseBody.utf8)) as? [String: Any]
        guard let root else { throw TtsPlaybackError.invalidResponse("MiniMax voice list response is not an object") }
        try validateBaseResponse(root)
        let fields: [(String, String)] = [
            ("system_voice", "系统音色"),
            ("voice_cloning", "复刻音色"),
            ("voice_generation", "文生音色")
        ]
        return fields.flatMap { field, category -> [MiniMaxVoiceOption] in
            guard let array = root[field] as? [[String: Any]] else { return [] }
            return array.compactMap { item in
                let id = (item["voice_id"] as? String)?.nilIfBlank ?? (item["id"] as? String)?.nilIfBlank
                guard let id else { return nil }
                let name = (item["voice_name"] as? String)?.nilIfBlank ?? (item["name"] as? String)?.nilIfBlank ?? id
                return MiniMaxVoiceOption(id: id, name: name, category: category)
            }
        }.uniqueBy(\.id)
    }

    private static func validateBaseResponse(_ root: [String: Any]) throws {
        let baseResp = root["base_resp"] as? [String: Any]
        let statusCode = baseResp?["status_code"] as? Int ?? 0
        let statusMsg = baseResp?["status_msg"] as? String ?? ""
        if statusCode != 0 {
            throw TtsPlaybackError.providerError(statusCode: statusCode, statusMessage: statusMsg, traceId: root["trace_id"] as? String ?? "")
        }
    }
}

enum MiniMaxTtsRequestBuilder {
    static func build(text: String, voiceId: String) -> [String: Any] {
        [
            "model": "speech-2.8-hd",
            "text": text,
            "stream": false,
            "voice_setting": [
                "voice_id": voiceId,
                "speed": 1.0,
                "vol": 1.0,
                "pitch": 0.0,
                "emotion": "happy"
            ],
            "audio_setting": [
                "sample_rate": 32_000,
                "bitrate": 128_000,
                "format": "mp3",
                "channel": 1
            ],
            "subtitle_enable": false,
            "output_format": "hex"
        ]
    }
}

struct MiniMaxTtsAudio {
    var audioBytes: Data
    var traceId: String
    var audioFormat: String
    var audioSize: Int
    var sampleRate: Int
    var channelCount: Int
}

enum MiniMaxTtsResponseParser {
    static func parse(_ responseBody: String) throws -> MiniMaxTtsAudio {
        let root = try JSONSerialization.jsonObject(with: Data(responseBody.utf8)) as? [String: Any]
        guard let root else { throw TtsPlaybackError.invalidResponse("MiniMax TTS response is not an object") }
        let traceId = root["trace_id"] as? String ?? ""
        let baseResp = root["base_resp"] as? [String: Any]
        let statusCode = baseResp?["status_code"] as? Int ?? 0
        let statusMsg = baseResp?["status_msg"] as? String ?? ""
        if statusCode != 0 {
            throw TtsPlaybackError.providerError(statusCode: statusCode, statusMessage: statusMsg, traceId: traceId)
        }
        guard let dataObject = root["data"] as? [String: Any],
              let audioHex = (dataObject["audio"] as? String)?.nilIfBlank else {
            throw TtsPlaybackError.invalidResponse("MiniMax TTS response missing data.audio trace_id=\(traceId)")
        }
        let audioBytes = try decodeHex(audioHex)
        let extraInfo = root["extra_info"] as? [String: Any]
        return MiniMaxTtsAudio(
            audioBytes: audioBytes,
            traceId: traceId,
            audioFormat: (extraInfo?["audio_format"] as? String)?.nilIfBlank ?? "mp3",
            audioSize: extraInfo?["audio_size"] as? Int ?? audioBytes.count,
            sampleRate: extraInfo?["audio_sample_rate"] as? Int ?? 32_000,
            channelCount: extraInfo?["audio_channel"] as? Int ?? 1
        )
    }

    private static func decodeHex(_ hex: String) throws -> Data {
        let clean = hex.filter { !$0.isWhitespace }
        guard clean.count.isMultiple(of: 2) else {
            throw TtsPlaybackError.invalidResponse("MiniMax TTS audio hex has odd length")
        }
        var data = Data(capacity: clean.count / 2)
        var index = clean.startIndex
        while index < clean.endIndex {
            let next = clean.index(index, offsetBy: 2)
            let byteString = clean[index..<next]
            guard let byte = UInt8(byteString, radix: 16) else {
                throw TtsPlaybackError.invalidResponse("MiniMax TTS audio contains non-hex characters")
            }
            data.append(byte)
            index = next
        }
        return data
    }
}

enum TtsPlaybackError: Error, CustomStringConvertible {
    case engineUnavailable
    case engineRejectedPlayback
    case emptyResponse
    case minimaxApiError(statusCode: Int, body: String)
    case providerError(statusCode: Int, statusMessage: String, traceId: String)
    case invalidResponse(String)
    case audioPlaybackFailed

    var description: String {
        switch self {
        case .engineUnavailable:
            return "TTS engine unavailable"
        case .engineRejectedPlayback:
            return "TTS engine rejected playback"
        case .emptyResponse:
            return "Empty response"
        case .minimaxApiError(let statusCode, let body):
            return "MiniMax API error: \(statusCode), body: \(body)"
        case .providerError(let statusCode, let statusMessage, let traceId):
            return "MiniMax TTS provider error status_code=\(statusCode) status_msg=\(statusMessage) trace_id=\(traceId)"
        case .invalidResponse(let message):
            return message
        case .audioPlaybackFailed:
            return "MiniMax audio playback failed"
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

private extension Optional where Wrapped == String {
    var nilIfBlank: String? {
        flatMap(\.nilIfBlank)
    }
}

private extension Array {
    func uniqueBy<Key: Hashable>(_ keyPath: KeyPath<Element, Key>) -> [Element] {
        uniqueBy { $0[keyPath: keyPath] }
    }

    func uniqueBy<Key: Hashable>(_ key: (Element) -> Key) -> [Element] {
        var seen = Set<Key>()
        var result: [Element] = []
        for item in self where seen.insert(key(item)).inserted {
            result.append(item)
        }
        return result
    }
}
