import SwiftUI

enum InputMode { case voice, text }

enum VoiceRecordingState {
    case idle
    case recordingSend
    case recordingCancel

    var isRecording: Bool {
        self != .idle
    }

    var isCancelled: Bool {
        self == .recordingCancel
    }
}

struct InputAreaView: View {
    @Binding var inputMode: InputMode
    let isRecording: Bool
    let isPaired: Bool
    let colors: MochiColors
    let quoteDraft: String?
    let onSendText: (String) -> Void
    let onQuoteDraftConsumed: () -> Void
    let onMicPress: () -> Void
    let onMicRelease: (Bool) -> Void
    @ObservedObject var audioRecorder: AudioRecorder

    @State private var textFieldValue = ""
    @State private var touchLocationY: CGFloat = UIScreen.main.bounds.height
    @State private var isMicGestureActive = false

    private var recordingPanelHeight: CGFloat {
        UIScreen.main.bounds.height * 0.26
    }

    private var recordingPanelTopY: CGFloat {
        UIScreen.main.bounds.height - recordingPanelHeight
    }

    private var bottomSafeAreaInset: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }?
            .safeAreaInsets.bottom ?? 0
    }

    private var recordingState: VoiceRecordingState {
        guard isRecording else { return .idle }
        if isMicGestureActive && touchLocationY < recordingPanelTopY {
            return .recordingCancel
        }
        return .recordingSend
    }

    var body: some View {
        VStack(spacing: 0) {
            Divider().background(colors.divider)

            if inputMode == .text {
                TextInputRowView(
                    textFieldValue: $textFieldValue,
                    colors: colors,
                    onSend: { text in
                        onSendText(text)
                        textFieldValue = ""
                    },
                    onSwitchToVoice: { inputMode = .voice }
                )
            } else {
                VoiceInputRowView(
                    isRecording: isRecording,
                    recordingState: recordingState,
                    theme: colors,
                    onMicPress: {
                        touchLocationY = UIScreen.main.bounds.height
                        isMicGestureActive = true
                        onMicPress()
                    },
                    onMicRelease: { finalLocationY in
                        touchLocationY = finalLocationY
                        let cancelled = finalLocationY < recordingPanelTopY
                        isMicGestureActive = false
                        touchLocationY = UIScreen.main.bounds.height
                        onMicRelease(cancelled)
                    },
                    onMicDrag: { locationY in
                        touchLocationY = locationY
                        isMicGestureActive = true
                    },
                    onSwitchToText: { inputMode = .text }
                )
            }
        }
        .background(colors.surface)
        .overlay(alignment: .bottom) {
            if isRecording {
                RecordingOverlayView(
                    state: recordingState,
                    audioLevel: audioRecorder.audioLevel,
                    panelHeight: recordingPanelHeight,
                    theme: colors
                )
                .offset(y: bottomSafeAreaInset)
                .allowsHitTesting(false)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.16), value: recordingState.isCancelled)
        .animation(.easeOut(duration: 0.18), value: isRecording)
        .onChange(of: inputMode) { newValue in
            if newValue == .text && quoteDraft == nil {
                textFieldValue = ""
            }
        }
        .onChange(of: quoteDraft) { draft in
            guard let draft else { return }
            inputMode = .text
            textFieldValue = draft
            onQuoteDraftConsumed()
        }
    }
}

// MARK: - Text Input Row

struct TextInputRowView: View {
    @Binding var textFieldValue: String
    let colors: MochiColors
    let onSend: (String) -> Void
    let onSwitchToVoice: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            // Voice mode toggle button
            Button(action: onSwitchToVoice) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 22))
                    .foregroundColor(colors.icon)
            }
            .frame(width: 44, height: 44)

            // Input field — matches Android's RoundedCornerShape + border style
            ZStack(alignment: .leading) {
                if textFieldValue.isEmpty {
                    Text("输入消息...")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundColor(colors.inputPlaceholder)
                        .padding(.horizontal, 16)
                }
                TextField("", text: $textFieldValue)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(colors.inputText)
                    .lineLimit(3)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 0)
            }
            .frame(height: 56)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 22)
                        .fill(colors.inputBg)
                    RoundedRectangle(cornerRadius: 22)
                        .strokeBorder(colors.inputBorder, lineWidth: 1)
                }
            )

            // Send button — matches Android's circular SendButton
            Button(action: {
                let trimmed = textFieldValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    onSend(trimmed)
                }
            }) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 18))
                    .foregroundColor(textFieldValue.isBlank ? colors.textSecondary : colors.onPrimary)
            }
            .frame(width: 44, height: 44)
            .background(textFieldValue.isBlank ? colors.inputBorder : colors.primary)
            .clipShape(Circle())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Voice Input Row

struct VoiceInputRowView: View {
    let isRecording: Bool
    let recordingState: VoiceRecordingState
    let theme: MochiColors
    let onMicPress: () -> Void
    let onMicRelease: (CGFloat) -> Void
    let onMicDrag: (CGFloat) -> Void
    let onSwitchToText: () -> Void

    var body: some View {
        HStack {
            Button(action: onSwitchToText) {
                Image(systemName: "keyboard")
                    .font(.system(size: 22))
                    .foregroundColor(theme.icon)
            }
            .frame(width: 44, height: 44)

            Spacer()

            VoiceMicButtonView(
                isRecording: isRecording,
                recordingState: recordingState,
                theme: theme,
                onPress: onMicPress,
                onRelease: onMicRelease,
                onDrag: onMicDrag
            )

            Spacer()
            Spacer().frame(width: 44, height: 44)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

struct VoiceMicButtonView: View {
    let isRecording: Bool
    let recordingState: VoiceRecordingState
    let theme: MochiColors
    let onPress: () -> Void
    let onRelease: (CGFloat) -> Void
    let onDrag: (CGFloat) -> Void

    @State private var hasStartedGesture = false

    private var backgroundColor: Color {
        if recordingState.isCancelled { return theme.recordingRed.opacity(0.92) }
        if isRecording { return Color(hex: "1E9BFF") }
        return theme.secondary
    }

    var body: some View {
        Image(systemName: "mic.fill")
            .font(.system(size: 24))
            .foregroundColor(isRecording ? .white : theme.onSecondary)
            .rotationEffect(.degrees(recordingState.isCancelled ? 45 : 0))
            .frame(width: 56, height: 56)
            .background(backgroundColor)
            .clipShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .global)
                    .onChanged { value in
                        if !hasStartedGesture {
                            hasStartedGesture = true
                            onPress()
                        }
                        onDrag(value.location.y)
                    }
                    .onEnded { value in
                        hasStartedGesture = false
                        onRelease(value.location.y)
                    }
            )
    }
}

struct RecordingOverlayView: View {
    let state: VoiceRecordingState
    let audioLevel: CGFloat
    let panelHeight: CGFloat
    let theme: MochiColors

    @State private var glowPulse: CGFloat = 0

    private var promptText: String {
        state.isCancelled ? "松手取消" : "松手发送，上移取消"
    }

    private var promptColor: Color {
        state.isCancelled ? theme.recordingRed : .white
    }

    private var backgroundGradient: LinearGradient {
        if state.isCancelled {
            return LinearGradient(
                colors: [
                    Color.black.opacity(0),
                    theme.recordingRed.opacity(0.28),
                    Color(hex: "2B0606").opacity(0.95)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }

        return LinearGradient(
            colors: [
                Color(hex: "0D7FFF").opacity(0),
                Color(hex: "1597FF").opacity(0.56),
                Color(hex: "238CFF").opacity(0.98)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    var body: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 18)

            Text(promptText)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(promptColor.opacity(state.isCancelled ? 0.95 : 0.82))
                .shadow(color: .black.opacity(0.18), radius: 8, x: 0, y: 2)

            VoiceWaveformView(
                audioLevel: audioLevel,
                isCancelled: state.isCancelled,
                theme: theme
            )
            .frame(height: 52)
            .padding(.horizontal, 42)
            .padding(.bottom, 30)
        }
        .frame(maxWidth: .infinity)
        .frame(height: panelHeight)
        .background(backgroundGradient)
        .overlay(alignment: .bottom) {
            Circle()
                .fill((state.isCancelled ? theme.recordingRed : Color(hex: "4FB7FF")).opacity(0.2 + glowPulse * 0.1))
                .blur(radius: 46)
                .frame(width: 320, height: 120)
                .offset(y: 42)
        }
        .ignoresSafeArea(edges: .bottom)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.15).repeatForever(autoreverses: true)) {
                glowPulse = 1
            }
        }
    }
}

struct VoiceWaveformView: View {
    let audioLevel: CGFloat
    let isCancelled: Bool
    let theme: MochiColors

    @State private var phase: CGFloat = 0

    private let barCount = 54

    var body: some View {
        GeometryReader { geometry in
            HStack(alignment: .center, spacing: 3) {
                ForEach(0..<barCount, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(isCancelled ? theme.recordingRed : .white)
                        .frame(width: 3, height: barHeight(index: index, maxHeight: geometry.size.height))
                        .opacity(isCancelled ? 0.9 : 0.94)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .onAppear {
            phase = 0
            withAnimation(.linear(duration: 0.85).repeatForever(autoreverses: false)) {
                phase = .pi * 2
            }
        }
    }

    private func barHeight(index: Int, maxHeight: CGFloat) -> CGFloat {
        let position = CGFloat(index) / CGFloat(barCount - 1)
        let distanceFromCenter = abs(position - 0.5) * 2
        let centerBias = (1 - distanceFromCenter).clamp(0.12, 1)
        let voiceEnergy = max(audioLevel.clamp(0, 1), 0.08)
        let primaryWave = (sin(CGFloat(index) * 0.48 + phase) + 1) / 2
        let secondaryWave = (sin(CGFloat(index) * 1.13 + phase * 1.7) + 1) / 2

        let idleMotion = 2 + 5 * primaryWave
        let liveMotion = maxHeight * 0.72 * voiceEnergy * centerBias * (0.42 + 0.58 * primaryWave)
        let detailMotion = maxHeight * 0.16 * voiceEnergy * secondaryWave

        return (idleMotion + liveMotion + detailMotion).clamp(5, maxHeight)
    }
}

extension CGFloat {
    func clamp(_ min: CGFloat, _ max: CGFloat) -> CGFloat {
        Swift.min(Swift.max(self, min), max)
    }
}

extension String {
    var isBlank: Bool { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}
