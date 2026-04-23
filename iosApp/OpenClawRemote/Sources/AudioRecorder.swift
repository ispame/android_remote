import AVFoundation
import Combine

final class AudioRecorder: ObservableObject {
    private var audioRecorder: AVAudioRecorder?
    private var recordingSession: AVAudioSession?
    private var tempFile: URL?

    @Published var isRecording: Bool = false

    func startRecording() {
        recordingSession = AVAudioSession.sharedInstance()
        try? recordingSession?.setCategory(.playAndRecord, mode: .default)
        try? recordingSession?.setActive(true)

        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        tempFile = documentsPath.appendingPathComponent("temp_recording.m4a")

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        guard let tempFile = tempFile else { return }
        audioRecorder = try? AVAudioRecorder(url: tempFile, settings: settings)
        audioRecorder?.record()
        isRecording = true
    }

    func stopRecording(onComplete: @escaping (Data) -> Void) {
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
}