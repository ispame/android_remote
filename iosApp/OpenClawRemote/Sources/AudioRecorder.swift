import AVFoundation
import Combine
import CoreGraphics

final class AudioRecorder: ObservableObject {
    private var audioRecorder: AVAudioRecorder?
    private var recordingSession: AVAudioSession?
    private var tempFile: URL?
    private var meterTimer: Timer?

    @Published var isRecording: Bool = false
    @Published var audioLevel: CGFloat = 0

    func startRecording() {
        stopMetering()

        recordingSession = AVAudioSession.sharedInstance()
        try? recordingSession?.setCategory(.playAndRecord, mode: .default)
        try? recordingSession?.setActive(true)

        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        tempFile = documentsPath.appendingPathComponent("temp_recording.wav")

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]

        guard let tempFile = tempFile else { return }
        audioRecorder = try? AVAudioRecorder(url: tempFile, settings: settings)
        audioRecorder?.isMeteringEnabled = true
        audioRecorder?.record()
        isRecording = true
        startMetering()
    }

    func stopRecording(onComplete: @escaping (Data) -> Void) {
        stopMetering()
        audioRecorder?.stop()
        audioRecorder = nil
        isRecording = false

        try? recordingSession?.setActive(false)

        guard let tempFile = tempFile else {
            onComplete(Data())
            return
        }

        if let data = try? Data(contentsOf: tempFile) {
            onComplete(data)
        } else {
            onComplete(Data())
        }
    }

    private func startMetering() {
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self = self, let recorder = self.audioRecorder else { return }
            recorder.updateMeters()

            let power = Double(recorder.averagePower(forChannel: 0))
            let clampedPower = max(-55.0, min(0.0, power))
            let normalized = pow(10.0, clampedPower / 35.0)

            DispatchQueue.main.async {
                guard self.isRecording else { return }
                self.audioLevel = CGFloat(normalized).clamp(0, 1)
            }
        }
        meterTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopMetering() {
        meterTimer?.invalidate()
        meterTimer = nil
        audioLevel = 0
    }
}
