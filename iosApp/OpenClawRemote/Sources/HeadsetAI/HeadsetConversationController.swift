import AVFoundation
import Combine
import Foundation
import MediaPlayer
import UIKit

enum HeadsetSessionState: Equatable {
    case idle
    case recording(HeadsetSide)
    case processing(HeadsetSide)
    case speaking(HeadsetSide)
    case error(String)

    var label: String {
        switch self {
        case .idle:
            return "待机"
        case .recording(let side):
            return "\(side.displayName)录音中"
        case .processing(let side):
            return "\(side.displayName)处理中"
        case .speaking(let side):
            return "\(side.displayName)播报中"
        case .error(let message):
            return message
        }
    }
}

final class HeadsetConversationController: NSObject, ObservableObject {
    @Published private(set) var sessionState: HeadsetSessionState = .idle
    @Published private(set) var connectionState: HeadsetConnectionState = .idle
    @Published private(set) var isDebugRecordingProbeActive = false
    @Published private(set) var lastHeadsetCommandLabel: String?
    @Published private(set) var inputDiagnostics = HeadsetInputDiagnostics()
    @Published private(set) var headsetKeyConfigurationLabel: String?

    let bleManager: A9UltraBLEManager

    private let wsManager: WebSocketManager
    private let settingsManager: SettingsManager
    private let synthesizer = AVSpeechSynthesizer()
    private let mediaCommandBridge = HeadsetMediaCommandBridge()
    private let promptTonePlayer = HeadsetPromptTonePlayer()
    private var cancellables = Set<AnyCancellable>()
    private var activeSide: HeadsetSide?
    private var activePCM = Data()
    private var decoders: [HeadsetSide: HeadsetOpusDecoder] = [:]
    private var finishWorkItem: DispatchWorkItem?
    private var sessionDeadlineWorkItem: DispatchWorkItem?
    private var pendingReplyProfileToSide: [String: HeadsetSide] = [:]
    private var voiceActivityDetector = HeadsetVoiceActivityDetector(config: .demoDefault)
    private var audioSessionObservers: [NSObjectProtocol] = []
    private var headsetReadyForMedia = false

    private let silenceTimeout: TimeInterval = 1.8
    private let vadDrainDuration: TimeInterval = 0.18
    private let maxRecordingDuration: TimeInterval = 20
    private let minimumASRPCMBytes = 16_000
    private let shortReplyLimit = 80

    var headsetStatusLabel: String {
        switch sessionState {
        case .idle:
            let parts = [
                lastHeadsetCommandLabel,
                headsetKeyConfigurationLabel,
                inputDiagnostics.label
            ].compactMap { $0 }
            return parts.isEmpty ? sessionState.label : parts.joined(separator: " | ")
        default:
            return sessionState.label
        }
    }

    init(
        wsManager: WebSocketManager,
        settingsManager: SettingsManager,
        bleManager: A9UltraBLEManager = A9UltraBLEManager()
    ) {
        self.wsManager = wsManager
        self.settingsManager = settingsManager
        self.bleManager = bleManager
        super.init()
        synthesizer.delegate = self
        bind()
    }

    func start() {
        observeAudioSessionChanges()
        mediaCommandBridge.start(activateNow: true) { [weak self] command in
            self?.handleRemoteCommand(command)
        }
        lastHeadsetCommandLabel = mediaCommandBridge.statusLabel
        bleManager.start()
    }

    func stop() {
        finishWorkItem?.cancel()
        sessionDeadlineWorkItem?.cancel()
        removeAudioSessionObservers()
        mediaCommandBridge.stop()
        bleManager.stop()
        synthesizer.stopSpeaking(at: .immediate)
        headsetReadyForMedia = false
        inputDiagnostics.reset()
        headsetKeyConfigurationLabel = nil
        isDebugRecordingProbeActive = false
        sessionState = .idle
    }

    private func handleRemoteCommand(
        _ command: HeadsetRemoteCommandKind,
        source: HeadsetMediaCommandSource = .commandCenter
    ) {
        reassertHeadsetMediaSession()
        recordMediaCommand(command, source: source)
        guard HeadsetMediaActivationPolicy.shouldOwnMedia(headsetReady: headsetReadyForMedia) else {
            lastHeadsetCommandLabel = "耳机未就绪"
            return
        }
        guard let side = command.activationSide else { return }
        activateFromHeadsetButton(side: side)
    }

    private func activateFromHeadsetButton(side: HeadsetSide) {
        isDebugRecordingProbeActive = false
        if let currentSide = activeSide {
            finishCurrentSession(speakIfEmpty: false)
            if currentSide == side {
                return
            }
        }
        startSession(side: side)
    }

    func debugRestartHeadset() {
        isDebugRecordingProbeActive = false
        inputDiagnostics.reset()
        resetActiveSession()
        bleManager.restartScan()
    }

    func debugRetryHandshake() {
        bleManager.retryHandshake()
    }

    func debugForceReady() {
        bleManager.forceReadyForDebug()
    }

    func debugStartRecordingProbe() {
        isDebugRecordingProbeActive = true
        bleManager.setOpusRecording(enabled: true)
    }

    func debugStopRecordingProbe() {
        isDebugRecordingProbeActive = false
        bleManager.setOpusRecording(enabled: false)
        if activeSide != nil {
            finishCurrentSession()
        } else {
            sessionState = .idle
        }
    }

    private func bind() {
        bleManager.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.connectionState = state
            }
            .store(in: &cancellables)

        bleManager.events
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                self?.handleBLEEvent(event)
            }
            .store(in: &cancellables)

        wsManager.messageChannel
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                self?.handleWebSocketEvent(event)
            }
            .store(in: &cancellables)
    }

    private func handleBLEEvent(_ event: HeadsetBLEEvent) {
        switch event {
        case .ready:
            headsetReadyForMedia = true
            sessionState = .idle
            reassertHeadsetMediaSession()
        case .disconnected:
            headsetReadyForMedia = false
            mediaCommandBridge.suspendNowPlaying()
            resetActiveSession()
        case .wake(_, let payload):
            isDebugRecordingProbeActive = false
            recordBLESignal(.wake, payload: payload)
        case .sleep(let payload):
            isDebugRecordingProbeActive = false
            recordBLESignal(.sleep, payload: payload)
        case .keySettingsAck(let success, let payload):
            recordBLESignal(.keySettingsAck, payload: payload)
            headsetKeyConfigurationLabel = success ? "按键写入成功" : "按键写入失败"
        case .keyConfiguration(let payload):
            recordBLESignal(.keyConfiguration, payload: payload)
            headsetKeyConfigurationLabel = "按键 \(A9UltraKeyConfiguration.summary(payload))"
        case .rawNotify(let label, let payload):
            recordBLESignal(.raw(label), payload: payload)
        case .audioChunk(let side, let opusData, let frameCount, let frameSize):
            handleAudioChunk(side: side, opusData: opusData, frameCount: frameCount, frameSize: frameSize)
        case .error(let message):
            sessionState = .error(message)
        }
    }

    private func handleWebSocketEvent(_ event: WsMessageEvent) {
        guard case .newMessage(let profileId, let message) = event,
              !message.isUser,
              let side = pendingReplyProfileToSide.removeValue(forKey: profileId) else {
            return
        }
        speakReply(message.content, side: side)
    }

    private func handleAudioChunk(side: HeadsetSide, opusData: Data, frameCount: Int, frameSize: Int) {
        guard let activeSide, HeadsetAudioRoutingPolicy.shouldAcceptAudioChunk(activeSide: activeSide) else { return }
        let sessionSide = HeadsetAudioRoutingPolicy.sessionSide(activeSide: activeSide, reportedAudioSide: side)

        do {
            let decoder = try decoder(for: sessionSide)
            let pcm = try decoder.decodePackets(opusData, frameCount: frameCount, frameSize: frameSize)
            activePCM.append(pcm)
            sessionState = .recording(sessionSide)
            let decision = voiceActivityDetector.analyze(pcm16Mono: pcm)
            scheduleFinishTimer(after: decision == .finishRecording ? vadDrainDuration : silenceTimeout)
        } catch {
            sessionState = .error("耳机音频解码失败")
            speak("耳机音频解码失败", side: sessionSide, forceShort: true)
            resetActiveSession()
        }
    }

    private func startSession(side: HeadsetSide) {
        synthesizer.stopSpeaking(at: .immediate)
        finishWorkItem?.cancel()
        sessionDeadlineWorkItem?.cancel()
        activeSide = side
        activePCM = Data()
        voiceActivityDetector.reset()
        lastHeadsetCommandLabel = nil
        decoders[side]?.reset()
        reassertHeadsetMediaSession()
        bleManager.setOpusRecording(enabled: true)
        playStartPrompt(for: side)
        sessionState = .recording(side)

        let deadline = DispatchWorkItem { [weak self] in
            self?.finishCurrentSession()
        }
        sessionDeadlineWorkItem = deadline
        DispatchQueue.main.asyncAfter(deadline: .now() + maxRecordingDuration, execute: deadline)
    }

    private func scheduleFinishTimer(after delay: TimeInterval) {
        finishWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.finishCurrentSession()
        }
        finishWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func finishCurrentSession(speakIfEmpty: Bool = true) {
        guard let side = activeSide else { return }
        finishWorkItem?.cancel()
        sessionDeadlineWorkItem?.cancel()
        bleManager.setOpusRecording(enabled: false)
        playEndPrompt()
        isDebugRecordingProbeActive = false

        let pcm = activePCM
        let shouldSubmit = voiceActivityDetector.shouldSubmitForASR(
            pcmByteCount: pcm.count,
            minimumPCMBytes: minimumASRPCMBytes
        )
        activeSide = nil
        activePCM = Data()
        voiceActivityDetector.reset()

        guard shouldSubmit else {
            sessionState = .idle
            if speakIfEmpty {
                speak("没有听清", side: side, forceShort: true)
            }
            return
        }

        guard let profile = profile(for: side) else {
            sessionState = .idle
            speak("\(side.displayName)未配置 Agent", side: side, forceShort: true)
            return
        }

        sessionState = .processing(side)
        let wav = WAVEncoder.encodePCM16Mono16k(pcm)
        if wsManager.sendAudio(wav, profileId: profile.id) {
            pendingReplyProfileToSide[profile.id] = side
        } else {
            sessionState = .idle
            speak("\(side.displayName)Agent 未连接", side: side, forceShort: true)
        }
    }

    private func resetActiveSession() {
        finishWorkItem?.cancel()
        sessionDeadlineWorkItem?.cancel()
        activeSide = nil
        activePCM = Data()
        voiceActivityDetector.reset()
        pendingReplyProfileToSide.removeAll()
        isDebugRecordingProbeActive = false
        sessionState = .idle
    }

    private func decoder(for side: HeadsetSide) throws -> HeadsetOpusDecoder {
        if let decoder = decoders[side] {
            return decoder
        }
        let decoder = try HeadsetOpusDecoder()
        decoders[side] = decoder
        return decoder
    }

    private func profile(for side: HeadsetSide) -> AgentProfile? {
        let profiles = settingsManager.profiles
        guard profiles.indices.contains(side.agentIndex) else { return nil }
        let profile = profiles[side.agentIndex]
        guard !profile.backendId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return profile
    }

    private func speakReply(_ content: String, side: HeadsetSide) {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            sessionState = .idle
            return
        }

        let spoken = shouldSummarize(trimmed)
            ? "收到一条较长回复，请在 App 上查看。"
            : trimmed
        speak(spoken, side: side, forceShort: true)
    }

    private func speak(_ text: String, side: HeadsetSide, forceShort _: Bool = false) {
        reassertHeadsetMediaSession()
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "zh-CN")
        utterance.rate = 0.48
        utterance.pitchMultiplier = 1.0
        sessionState = .speaking(side)
        synthesizer.speak(utterance)
    }

    private func configureSpeechSession() {
        HeadsetAudioSessionCoordinator.activate()
    }

    private func reassertHeadsetMediaSession() {
        configureSpeechSession()
        mediaCommandBridge.reassertNowPlaying()
        if case .idle = sessionState,
           lastHeadsetCommandLabel == nil || lastHeadsetCommandLabel?.hasPrefix("媒体") == true {
            lastHeadsetCommandLabel = mediaCommandBridge.statusLabel
        }
    }

    private func recordMediaCommand(
        _ command: HeadsetRemoteCommandKind,
        source: HeadsetMediaCommandSource = .commandCenter
    ) {
        var diagnostics = inputDiagnostics
        diagnostics.recordMedia(command, source: source)
        inputDiagnostics = diagnostics
    }

    private func recordBLESignal(_ signal: HeadsetBLESignalKind, payload: Data) {
        var diagnostics = inputDiagnostics
        diagnostics.recordBLE(signal, payload: payload)
        inputDiagnostics = diagnostics
    }

    private func observeAudioSessionChanges() {
        guard audioSessionObservers.isEmpty else { return }
        let center = NotificationCenter.default

        audioSessionObservers.append(center.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reassertHeadsetMediaSession()
        })

        audioSessionObservers.append(center.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reassertHeadsetMediaSession()
        })

        audioSessionObservers.append(center.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleAudioSessionInterruption(notification)
        })

        audioSessionObservers.append(center.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reassertHeadsetMediaSession()
        })

        audioSessionObservers.append(center.addObserver(
            forName: .headsetLegacyRemoteControlEvent,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleLegacyRemoteControlEvent(notification)
        })
    }

    private func removeAudioSessionObservers() {
        let center = NotificationCenter.default
        audioSessionObservers.forEach { center.removeObserver($0) }
        audioSessionObservers.removeAll()
    }

    private func handleAudioSessionInterruption(_ notification: Notification) {
        guard let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: rawType) else {
            return
        }

        switch type {
        case .began:
            lastHeadsetCommandLabel = "音频中断"
            if activeSide != nil {
                bleManager.setOpusRecording(enabled: false)
                resetActiveSession()
            }
        case .ended:
            lastHeadsetCommandLabel = "媒体接管恢复"
            reassertHeadsetMediaSession()
        @unknown default:
            reassertHeadsetMediaSession()
        }
    }

    private func handleLegacyRemoteControlEvent(_ notification: Notification) {
        guard let rawEvent = notification.userInfo?[HeadsetLegacyRemoteControlEvent.userInfoKey] as? String,
              let event = HeadsetLegacyRemoteControlEvent(rawValue: rawEvent) else {
            return
        }
        handleRemoteCommand(event.commandKind, source: .legacyResponder)
    }

    private func playStartPrompt(for side: HeadsetSide) {
        reassertHeadsetMediaSession()
        promptTonePlayer.play(channel: side.promptToneChannel, frequency: 880, duration: 0.10)
    }

    private func playEndPrompt() {
        reassertHeadsetMediaSession()
        promptTonePlayer.play(channel: .both, frequency: 660, duration: 0.10)
    }

    private func shouldSummarize(_ content: String) -> Bool {
        if content.count > shortReplyLimit { return true }
        let endings = CharacterSet(charactersIn: "。！？!?")
        let sentenceCount = content.unicodeScalars.filter { endings.contains($0) }.count
        return sentenceCount > 2
    }
}

private final class HeadsetMediaCommandBridge {
    private var commandTokens: [(command: MPRemoteCommand, token: Any)] = []
    private var silentPlayer: AVAudioPlayer?
    private var isActive = false
    private var onCommand: ((HeadsetRemoteCommandKind) -> Void)?

    var statusLabel: String {
        silentPlayer?.isPlaying == true ? "媒体接管中" : "媒体接管重试中"
    }

    func start(activateNow: Bool = true, onCommand: @escaping (HeadsetRemoteCommandKind) -> Void) {
        self.onCommand = onCommand
        guard !isActive else {
            if activateNow {
                reassertNowPlaying()
            }
            return
        }
        isActive = true

        installCommandHandlers()
        if activateNow {
            reassertNowPlaying()
        }
    }

    func reassertNowPlaying() {
        guard isActive else { return }
        HeadsetAudioSessionCoordinator.activate()
        publishNowPlayingInfo()
        ensureKeepAlivePlayer()
        UIApplication.shared.beginReceivingRemoteControlEvents()
    }

    func suspendNowPlaying() {
        silentPlayer?.stop()
        silentPlayer = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        if #available(iOS 13.0, *) {
            MPNowPlayingInfoCenter.default().playbackState = .stopped
        }
    }

    private func installCommandHandlers() {
        guard commandTokens.isEmpty else { return }
        let center = MPRemoteCommandCenter.shared()
        center.previousTrackCommand.isEnabled = true
        center.nextTrackCommand.isEnabled = true
        center.playCommand.isEnabled = true
        center.pauseCommand.isEnabled = true
        center.togglePlayPauseCommand.isEnabled = true

        commandTokens = [
            (center.previousTrackCommand, center.previousTrackCommand.addTarget { [weak self] _ in
                self?.emit(.previousTrack) ?? .commandFailed
            }),
            (center.nextTrackCommand, center.nextTrackCommand.addTarget { [weak self] _ in
                self?.emit(.nextTrack) ?? .commandFailed
            }),
            (center.playCommand, center.playCommand.addTarget { [weak self] _ in
                self?.emit(.play) ?? .commandFailed
            }),
            (center.pauseCommand, center.pauseCommand.addTarget { [weak self] _ in
                self?.emit(.pause) ?? .commandFailed
            }),
            (center.togglePlayPauseCommand, center.togglePlayPauseCommand.addTarget { [weak self] _ in
                self?.emit(.togglePlayPause) ?? .commandFailed
            })
        ]
    }

    func stop() {
        guard isActive else { return }
        isActive = false

        let center = MPRemoteCommandCenter.shared()
        for entry in commandTokens {
            entry.command.removeTarget(entry.token)
        }
        commandTokens.removeAll()
        center.previousTrackCommand.isEnabled = false
        center.nextTrackCommand.isEnabled = false
        center.playCommand.isEnabled = false
        center.pauseCommand.isEnabled = false
        center.togglePlayPauseCommand.isEnabled = false

        silentPlayer?.stop()
        silentPlayer = nil
        onCommand = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        if #available(iOS 13.0, *) {
            MPNowPlayingInfoCenter.default().playbackState = .stopped
        }
        UIApplication.shared.endReceivingRemoteControlEvents()
    }

    private func emit(_ command: HeadsetRemoteCommandKind) -> MPRemoteCommandHandlerStatus {
        guard isActive else { return .commandFailed }
        reassertNowPlaying()
        DispatchQueue.main.async { [onCommand] in
            onCommand?(command)
        }
        return .success
    }

    private func publishNowPlayingInfo() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: HeadsetNowPlayingMetadata.title,
            MPMediaItemPropertyArtist: HeadsetNowPlayingMetadata.artist,
            MPMediaItemPropertyAlbumTitle: HeadsetNowPlayingMetadata.album,
            MPMediaItemPropertyPlaybackDuration: HeadsetNowPlayingMetadata.playbackDuration,
            MPNowPlayingInfoPropertyPlaybackRate: HeadsetNowPlayingMetadata.playbackRate,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: HeadsetNowPlayingMetadata.playbackRate,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: Date().timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: HeadsetNowPlayingMetadata.playbackDuration),
            MPNowPlayingInfoPropertyPlaybackQueueCount: HeadsetNowPlayingMetadata.playbackQueueCount,
            MPNowPlayingInfoPropertyPlaybackQueueIndex: HeadsetNowPlayingMetadata.playbackQueueIndex
        ]

        if #available(iOS 13.0, *) {
            MPNowPlayingInfoCenter.default().playbackState = .playing
        }
    }

    private func ensureKeepAlivePlayer() {
        if let player = silentPlayer {
            if !player.isPlaying {
                player.play()
            }
            return
        }

        guard let player = try? AVAudioPlayer(data: Self.keepAliveWavData()) else { return }
        player.numberOfLoops = -1
        player.volume = 1.0
        player.prepareToPlay()
        player.play()
        silentPlayer = player
    }

    private static func keepAliveWavData() -> Data {
        let sampleRate = 16_000
        let seconds = 2
        let channels = 1
        let bitsPerSample = 16
        let byteRate = sampleRate * channels * bitsPerSample / 8
        let blockAlign = channels * bitsPerSample / 8
        let dataSize = sampleRate * seconds * blockAlign
        let riffSize = 36 + dataSize

        var data = Data()
        data.append(contentsOf: "RIFF".utf8)
        data.appendMediaUInt32LE(UInt32(riffSize))
        data.append(contentsOf: "WAVEfmt ".utf8)
        data.appendMediaUInt32LE(16)
        data.appendMediaUInt16LE(1)
        data.appendMediaUInt16LE(UInt16(channels))
        data.appendMediaUInt32LE(UInt32(sampleRate))
        data.appendMediaUInt32LE(UInt32(byteRate))
        data.appendMediaUInt16LE(UInt16(blockAlign))
        data.appendMediaUInt16LE(UInt16(bitsPerSample))
        data.append(contentsOf: "data".utf8)
        data.appendMediaUInt32LE(UInt32(dataSize))
        for index in 0..<(sampleRate * seconds) {
            let sample: Int16
            switch index & 0x03 {
            case 0: sample = 1
            case 1: sample = -1
            case 2: sample = 2
            default: sample = -2
            }
            data.appendMediaUInt16LE(UInt16(bitPattern: sample))
        }
        return data
    }
}

private enum HeadsetAudioSessionCoordinator {
    static func activate() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(
            .playAndRecord,
            mode: .voiceChat,
            options: [.allowBluetoothHFP, .allowBluetoothA2DP]
        )
        try? session.setActive(true)
    }
}

private extension Data {
    mutating func appendMediaUInt16LE(_ value: UInt16) {
        append(UInt8(value & 0x00FF))
        append(UInt8((value >> 8) & 0x00FF))
    }

    mutating func appendMediaUInt32LE(_ value: UInt32) {
        append(UInt8(value & 0x000000FF))
        append(UInt8((value >> 8) & 0x000000FF))
        append(UInt8((value >> 16) & 0x000000FF))
        append(UInt8((value >> 24) & 0x000000FF))
    }
}

private extension HeadsetSide {
    var promptToneChannel: HeadsetPromptToneChannel {
        switch self {
        case .left: return .left
        case .right: return .right
        }
    }
}

extension HeadsetConversationController: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        sessionState = .idle
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        sessionState = .idle
    }
}
