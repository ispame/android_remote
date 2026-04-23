import SwiftUI
import AVFoundation

struct QRScannerScreenView: View {
    let onQRCodeScanned: (String) -> Void
    let onClose: () -> Void

    @State private var hasPermission = false
    @State private var isCheckingPermission = true
    @State private var lastScannedValue: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if isCheckingPermission {
                ProgressView()
                    .tint(.white)
            } else if hasPermission {
                QRScannerViewWrapper(
                    onQRCodeScanned: { value in
                        if value != lastScannedValue {
                            lastScannedValue = value
                            onQRCodeScanned(value)
                        }
                    }
                )
                .ignoresSafeArea()

                VStack {
                    HStack {
                        Spacer()
                        Button(action: onClose) {
                            Image(systemName: "xmark")
                                .font(.system(size: 20))
                                .foregroundColor(.white)
                                .padding(16)
                        }
                    }
                    Spacer()
                    Text("将 QR 码放入框内")
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                        .padding(.bottom, 100)
                }
            } else {
                VStack(spacing: 16) {
                    Text("相机权限被拒绝，请在设置中开启")
                        .foregroundColor(.white)
                    Button("返回") { onClose() }
                }
            }
        }
        .onAppear {
            checkCameraPermission()
        }
    }

    private func checkCameraPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            hasPermission = true
            isCheckingPermission = false
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    hasPermission = granted
                    isCheckingPermission = false
                }
            }
        default:
            hasPermission = false
            isCheckingPermission = false
        }
    }
}

struct QRScannerViewWrapper: UIViewRepresentable {
    let onQRCodeScanned: (String) -> Void

    func makeUIView(context: Context) -> QRScannerUIView {
        QRScannerUIView(onQRCodeScanned: onQRCodeScanned)
    }

    func updateUIView(_ uiView: QRScannerUIView, context: Context) {}
}

class QRScannerUIView: UIView {
    private var captureSession: AVCaptureSession?
    private var onQRCodeScanned: ((String) -> Void)?

    init(onQRCodeScanned: @escaping (String) -> Void) {
        self.onQRCodeScanned = onQRCodeScanned
        super.init(frame: .zero)
        setupCamera()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupCamera() {
        let session = AVCaptureSession()
        captureSession = session

        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else { return }

        if session.canAddInput(input) { session.addInput(input) }

        let output = AVCaptureMetadataOutput()
        if session.canAddOutput(output) {
            session.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: .main)
            output.metadataObjectTypes = [.qr]
        }

        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.frame = UIScreen.main.bounds
        previewLayer.videoGravity = .resizeAspectFill
        layer.addSublayer(previewLayer)

        DispatchQueue.global(qos: .userInitiated).async {
            session.startRunning()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if let layer = layer.sublayers?.first as? AVCaptureVideoPreviewLayer {
            layer.frame = bounds
        }
    }
}

extension QRScannerUIView: AVCaptureMetadataOutputObjectsDelegate {
    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        for metadata in metadataObjects {
            if let qrCode = metadata as? AVMetadataMachineReadableCodeObject,
               let value = qrCode.stringValue {
                onQRCodeScanned?(value)
            }
        }
    }
}