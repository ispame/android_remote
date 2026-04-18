import UIKit
import SwiftUI
import shared

class ComposeViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()

        let settingsManager = SettingsManager()
        let viewModel = ChatViewModel(settingsManager: settingsManager)
        let audioRecorder = AudioRecorder()

        let composeView = MainScreenKotlinWrapper(
            viewModel: viewModel,
            audioRecorder: audioRecorder
        )

        let hostingController = UIHostingController(rootView: composeView)
        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        hostingController.didMove(toParent: self)
    }
}

struct MainScreenKotlinWrapper: View {
    let viewModel: ChatViewModel
    let audioRecorder: AudioRecorder

    @State private var isDark = false
    @State private var showSettings = false
    @State private var showQRScanner = false

    var body: some View {
        MainScreenSwift(
            messages: viewModel.messages,
            isRecording: audioRecorder.isRecording.value,
            connectionState: viewModel.connectionState.value,
            pairingState: viewModel.pairingState.value,
            pairedBackendLabel: viewModel.pairedBackendLabel.value,
            isDark: isDark,
            isLoadingHistory: viewModel.isLoadingHistory.value,
            hasMoreHistory: viewModel.hasMoreHistory.value,
            onToggleTheme: { isDark.toggle() },
            onNavigateToSettings: { showSettings = true }
        )
    }
}
