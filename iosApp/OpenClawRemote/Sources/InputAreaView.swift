import SwiftUI

enum InputMode { case voice, text }

struct InputAreaView: View {
    @Binding var inputMode: InputMode
    let isRecording: Bool
    let isPaired: Bool
    let colors: MochiColors
    let onSendText: (String) -> Void
    let onMicPress: () -> Void
    let onMicRelease: (Bool) -> Void
    let audioRecorder: AudioRecorder

    @State private var textFieldValue = ""
    @State private var dragOffsetY: CGFloat = 0
    @State private var isDragging = false

    private var isCancelled: Bool { dragOffsetY < -80 && isDragging }

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
                    isCancelled: isCancelled,
                    isDragging: isDragging,
                    dragOffsetY: dragOffsetY,
                    theme: colors,
                    onMicPress: onMicPress,
                    onMicRelease: { cancelled in
                        dragOffsetY = 0
                        isDragging = false
                        onMicRelease(cancelled)
                    },
                    onDrag: { delta in
                        dragOffsetY += delta
                        isDragging = dragOffsetY < -30
                    },
                    onSwitchToText: { inputMode = .text }
                )
            }
        }
        .background(colors.surface)
        .onChange(of: inputMode) { newValue in
            if newValue == .text {
                textFieldValue = ""
            }
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
    let isCancelled: Bool
    let isDragging: Bool
    let dragOffsetY: CGFloat
    let theme: MochiColors
    let onMicPress: () -> Void
    let onMicRelease: (Bool) -> Void
    let onDrag: (CGFloat) -> Void
    let onSwitchToText: () -> Void

    var body: some View {
        VStack(spacing: 8) {
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
                    isCancelled: isCancelled,
                    isDragging: isDragging,
                    dragOffsetY: dragOffsetY,
                    theme: theme,
                    onPress: onMicPress,
                    onRelease: onMicRelease,
                    onDrag: onDrag
                )

                Spacer()
                Spacer().frame(width: 44, height: 44)
            }

            if isRecording {
                CancelProgressView(
                    isDragging: isDragging,
                    isCancelled: isCancelled,
                    dragOffsetY: dragOffsetY,
                    theme: theme
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

struct VoiceMicButtonView: View {
    let isRecording: Bool
    let isCancelled: Bool
    let isDragging: Bool
    let dragOffsetY: CGFloat
    let theme: MochiColors
    let onPress: () -> Void
    let onRelease: (Bool) -> Void
    let onDrag: (CGFloat) -> Void

    private var backgroundColor: Color {
        if isCancelled { return theme.recordingRed.opacity(0.8) }
        if isRecording { return theme.recordingRed }
        return theme.secondary
    }

    var body: some View {
        Image(systemName: "mic.fill")
            .font(.system(size: 24))
            .foregroundColor(isRecording ? .white : theme.onSecondary)
            .rotationEffect(.degrees(isCancelled ? 45 : 0))
            .frame(width: 56, height: 56)
            .background(backgroundColor)
            .clipShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !isRecording {
                            onPress()
                        }
                        onDrag(value.translation.height)
                    }
                    .onEnded { value in
                        let cancelled = value.translation.height < -80
                        onRelease(cancelled)
                    }
            )
    }
}

struct CancelProgressView: View {
    let isDragging: Bool
    let isCancelled: Bool
    let dragOffsetY: CGFloat
    let theme: MochiColors

    private var cancelProgress: CGFloat {
        (-dragOffsetY / 80).clamp(0, 1)
    }

    var body: some View {
        if isDragging {
            VStack(spacing: 4) {
                GeometryReader { _ in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(theme.inputBorder)
                            .frame(width: 120, height: 3)

                        RoundedRectangle(cornerRadius: 2)
                            .fill(theme.recordingRed)
                            .frame(width: 120 * cancelProgress, height: 3)
                    }
                }
                .frame(width: 120, height: 3)

                Text(isCancelled ? "松开取消" : "上划取消")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(isCancelled ? theme.recordingRed : theme.textSecondary)
            }
        } else {
            Text("松手发送，上滑取消")
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(theme.textSecondary)
        }
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
