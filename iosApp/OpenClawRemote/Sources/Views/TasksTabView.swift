import SwiftUI
import UserNotifications
import AVFoundation
#if canImport(UIKit)
import UIKit
#endif

struct TasksTabView: View {
    @ObservedObject var wsManager: WebSocketManager
    @ObservedObject var settingsManager: SettingsManager
    @ObservedObject var audioRecorder: AudioRecorder
    @ObservedObject var headsetController: HeadsetConversationController
    @ObservedObject var scheduledTaskStore: ScheduledTaskStore
    @ObservedObject var agentTaskService: AgentTaskService
    @ObservedObject var recordingStore: RecordingStore
    let colors: MochiColors

    @State private var isPhoneRecording = false
    @State private var statusMessage: String?
    @State private var typeSelectionContext: RecordingTypeSelectionContext?

    private var recordings: [RecordingItem] {
        recordingStore.items.sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        List {
            if let statusMessage {
                Section {
                    Text(statusMessage)
                        .font(.system(size: 13))
                        .foregroundColor(colors.primary)
                }
            }

            recordingsSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("录音")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: addRecording) {
                    Image(systemName: isPhoneRecording ? "stop.circle.fill" : "plus")
                }
                .accessibilityLabel(isPhoneRecording ? "停止录音" : "新增录音")
            }
        }
        .sheet(item: $typeSelectionContext) { context in
            RecordingTypeSelectionView(
                recording: context.recording,
                settings: settingsManager.recordingSettings,
                colors: colors
            ) { type in
                processRecording(context.recording, as: type)
            }
        }
    }

    private var recordingsSection: some View {
        Section("录音") {
            if recordings.isEmpty {
                Text("点击右上角 + 新增录音")
                    .foregroundColor(.secondary)
            } else {
                ForEach(recordings) { recording in
                    NavigationLink(
                        destination: RecordingDetailView(
                            recording: recording,
                            wsManager: wsManager,
                            settingsManager: settingsManager,
                            store: recordingStore,
                            colors: colors
                        )
                    ) {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(recording.createdAt.earphoneListTimeText)
                                    .font(.system(size: 15, weight: .semibold))
                                Spacer()
                                Text(recording.source.label)
                                    .font(.system(size: 12))
                                    .foregroundColor(colors.primary)
                            }
                            Text(recording.asrText.isEmpty ? "未生成 ASR 文本" : recording.asrText)
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                            HStack(spacing: 12) {
                                Label(recording.recordingType.label, systemImage: recording.recordingType.systemImage)
                                Label("\(recording.events.count)", systemImage: "list.bullet.rectangle")
                                Label("\(recording.reminders.count)", systemImage: "bell")
                                if !recording.artifacts.isEmpty {
                                    Label("\(recording.artifacts.count)", systemImage: "doc.richtext")
                                }
                            }
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            try? recordingStore.deleteRecording(id: recording.id)
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }

    private func addRecording() {
        guard let recordingProfile = settingsManager.primaryRecordingProfile else {
            statusMessage = "请先配置主 Agent"
            return
        }

        if isPhoneRecording {
            audioRecorder.stopRecording { data in
                guard let recording = try? recordingStore.createRecording(
                    agentId: recordingProfile.id,
                    audioData: data,
                    asrText: "",
                    prompt: "",
                    recordingType: .audioOnly,
                    processingStatus: .savedOnly,
                    selectedPrompt: "",
                    source: .phone
                ) else {
                    statusMessage = "手机录音保存失败"
                    return
                }
                statusMessage = "手机录音已保存"
                typeSelectionContext = RecordingTypeSelectionContext(recording: recording)
            }
            isPhoneRecording = false
        } else {
            audioRecorder.startRecording()
            isPhoneRecording = true
            statusMessage = "手机麦克风录音中，再点一次保存"
        }
    }

    private func processRecording(_ recording: RecordingItem, as type: RecordingType) {
        if type == .audioOnly {
            recordingStore.configureRecordingForProcessing(recordingId: recording.id, type: .audioOnly, prompt: "", clientMessageId: nil)
            statusMessage = "录音已保存为仅录音"
            return
        }
        guard let recordingProfile = settingsManager.primaryRecordingProfile else {
            statusMessage = "请先配置主 Agent"
            return
        }
        let settings = settingsManager.recordingSettings
        let prompt = settings.prompt(for: type)
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            statusMessage = "请先在录音设置中填写自定义 Prompt"
            return
        }
        guard let data = try? Data(contentsOf: recording.fileURL) else {
            statusMessage = "录音文件读取失败"
            return
        }
        let clientMessageId = wsManager.sendRecordingAudioForAsr(
            data,
            profileId: recordingProfile.id,
            settings: settings,
            source: recording.source,
            recordingId: recording.id,
            recordingType: type,
            prompt: prompt
        )
        recordingStore.configureRecordingForProcessing(
            recordingId: recording.id,
            type: type,
            prompt: prompt,
            clientMessageId: clientMessageId
        )
        statusMessage = clientMessageId == nil ? "录音已保存；主 Agent 未连接，未发送 ASR" : "录音已发送，等待 ASR 和 Agent 处理"
    }
}

private struct RecordingTypeSelectionContext: Identifiable {
    let recording: RecordingItem
    var id: String { recording.id }
}

private struct RecordingTypeSelectionView: View {
    let recording: RecordingItem
    let settings: RecordingSettings
    let colors: MochiColors
    let onSelect: (RecordingType) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                Section("录音类型") {
                    ForEach(RecordingType.allCases) { type in
                        Button {
                            onSelect(type)
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: type.systemImage)
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundColor(type == .audioOnly ? .secondary : colors.primary)
                                    .frame(width: 28)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(type.label)
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundColor(.primary)
                                    Text(description(for: type))
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                if type == recording.recordingType || (recording.recordingType == .audioOnly && type == .audioOnly) {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(colors.primary)
                                }
                            }
                        }
                        .disabled(type == .custom && settings.customPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .navigationTitle("选择录音类型")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private func description(for type: RecordingType) -> String {
        switch type {
        case .audioOnly:
            return "只保存音频，不转写，不发送给 Agent"
        case .meeting:
            return "生成会议纪要、待办、文件和提醒"
        case .idea:
            return "整理灵感建议，补充信息并保存 Markdown"
        case .custom:
            return settings.customPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "请先在录音设置中填写自定义 Prompt"
                : "使用录音设置中的自定义 Prompt"
        }
    }
}

private struct RecordingDetailView: View {
    let recording: RecordingItem
    @ObservedObject var wsManager: WebSocketManager
    @ObservedObject var settingsManager: SettingsManager
    @ObservedObject var store: RecordingStore
    let colors: MochiColors
    @State private var asrText: String
    @State private var isAddingReminder = false
    @State private var reminderError: String?
    @State private var typeSelectionContext: RecordingTypeSelectionContext?
    @State private var sharePayload: RecordingSharePayload?
    @StateObject private var audioPlayer = RecordingAudioPlayer()

    init(
        recording: RecordingItem,
        wsManager: WebSocketManager,
        settingsManager: SettingsManager,
        store: RecordingStore,
        colors: MochiColors
    ) {
        self.recording = recording
        self.wsManager = wsManager
        self.settingsManager = settingsManager
        self.store = store
        self.colors = colors
        _asrText = State(initialValue: recording.asrText)
    }

    private var currentRecording: RecordingItem {
        store.items.first(where: { $0.id == recording.id }) ?? recording
    }

    private var timelineEvents: [RecordingEventItem] {
        currentRecording.events.sorted { $0.createdAt < $1.createdAt }
    }

    private var scheduledEvents: [RecordingEventItem] {
        timelineEvents.filter { $0.kind == .scheduledTask }
    }

    private var reminders: [RecordingReminderItem] {
        currentRecording.reminders.sorted { $0.dueAt < $1.dueAt }
    }

    var body: some View {
        Form {
            Section("录音") {
                RecordingMetadataRow(title: "时间", value: currentRecording.createdAt.earphoneListTimeText)
                RecordingMetadataRow(title: "来源", value: currentRecording.source.label)
                RecordingMetadataRow(title: "类型", value: currentRecording.recordingType.label)
                RecordingMetadataRow(title: "状态", value: currentRecording.processingStatus.label)
                RecordingMetadataRow(
                    title: "文件",
                    value: currentRecording.fileURL.lastPathComponent,
                    valueFont: .system(size: 12, design: .monospaced)
                )
                HStack {
                    Button {
                        audioPlayer.toggle(url: currentRecording.fileURL)
                    } label: {
                        Label(audioPlayer.isPlaying ? "暂停" : "播放", systemImage: audioPlayer.isPlaying ? "pause.circle" : "play.circle")
                    }
                    Spacer()
                    Button {
                        sharePayload = RecordingSharePayload(items: [currentRecording.fileURL])
                    } label: {
                        Label("分享音频", systemImage: "square.and.arrow.up")
                    }
                }
                Button {
                    typeSelectionContext = RecordingTypeSelectionContext(recording: currentRecording)
                } label: {
                    Label(currentRecording.recordingType == .audioOnly ? "选择录音类型" : "重新处理录音", systemImage: "arrow.triangle.2.circlepath")
                }
            }
            Section("录音 Prompt") {
                Text(currentRecording.selectedPrompt.isEmpty ? "仅录音无 Prompt" : currentRecording.selectedPrompt)
                    .font(.system(size: 13))
                    .textSelection(.enabled)
            }
            Section("ASR 文本") {
                TextEditor(text: $asrText)
                    .frame(minHeight: 220)
            }
            Section("执行进度") {
                if timelineEvents.isEmpty {
                    Text("Agent 执行进度会在这里展示")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(timelineEvents) { event in
                        RecordingEventRow(event: event, colors: colors)
                    }
                }
            }
            Section("导出的定时任务") {
                if scheduledEvents.isEmpty {
                    Text("录音中创建或识别到的定时任务会在这里归档")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(scheduledEvents) { event in
                        RecordingEventRow(event: event, colors: colors)
                    }
                }
            }
            Section("导出文件") {
                if currentRecording.artifacts.isEmpty {
                    Text("Agent 生成的 Markdown 文件会在这里展示")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(currentRecording.artifacts) { artifact in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "doc.richtext")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(colors.primary)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(artifact.filename)
                                    .font(.system(size: 14, weight: .semibold))
                                if let backendPath = artifact.backendPath, !backendPath.isEmpty {
                                    Text(backendPath)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }
                                Text(artifact.createdAt.earphoneListTimeText)
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Button {
                                sharePayload = RecordingSharePayload(items: [artifact.fileURL])
                            } label: {
                                Image(systemName: "square.and.arrow.up")
                            }
                            .accessibilityLabel("分享文件")
                        }
                        .padding(.vertical, 3)
                    }
                }
            }
            Section {
                if let reminderError {
                    Text(reminderError)
                        .font(.system(size: 13))
                        .foregroundColor(colors.recordingRed)
                }
                if reminders.isEmpty {
                    Text("后续待办提醒会在这里展示")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(reminders) { reminder in
                        RecordingReminderRow(reminder: reminder, colors: colors) {
                            store.setReminderCompleted(
                                recordingId: currentRecording.id,
                                reminderId: reminder.id,
                                isCompleted: !reminder.isCompleted
                            )
                        }
                    }
                }
            } header: {
                HStack {
                    Text("后续待办提醒")
                    Spacer()
                    Button {
                        isAddingReminder = true
                    } label: {
                        Image(systemName: "plus.circle")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("新增提醒")
                }
            }
        }
        .navigationTitle("录音详情")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            asrText = currentRecording.asrText
        }
        .onChange(of: currentRecording.asrText) { value in
            if asrText != value {
                asrText = value
            }
        }
        .sheet(isPresented: $isAddingReminder) {
            RecordingReminderEditorView(colors: colors) { title, notes, dueAt in
                addReminder(title: title, notes: notes, dueAt: dueAt)
            }
        }
        .sheet(item: $typeSelectionContext) { context in
            RecordingTypeSelectionView(
                recording: context.recording,
                settings: settingsManager.recordingSettings,
                colors: colors
            ) { type in
                processRecording(context.recording, as: type)
            }
        }
        .sheet(item: $sharePayload) { payload in
            RecordingActivityView(activityItems: payload.items)
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    isAddingReminder = true
                } label: {
                    Image(systemName: "bell.badge")
                }
                .accessibilityLabel("新增提醒")
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    var copy = currentRecording
                    copy.asrText = asrText
                    store.update(copy)
                }
            }
        }
    }

    private func addReminder(title: String, notes: String, dueAt: Date) {
        let reminder = store.addReminder(
            recordingId: currentRecording.id,
            title: title,
            notes: notes,
            dueAt: dueAt
        )
        isAddingReminder = false
        reminderError = nil

        Task {
            do {
                try await RecordingReminderNotificationScheduler.shared.schedule(reminder)
            } catch {
                await MainActor.run {
                    reminderError = "提醒已保存，但通知开启失败：\(error.localizedDescription)"
                    store.appendEvent(
                        RecordingEventItem(
                            kind: .error,
                            title: "提醒通知开启失败",
                            content: error.localizedDescription,
                            status: .failed
                        ),
                        recordingId: currentRecording.id
                    )
                }
            }
        }
    }

    private func processRecording(_ recording: RecordingItem, as type: RecordingType) {
        if type == .audioOnly {
            store.configureRecordingForProcessing(recordingId: recording.id, type: .audioOnly, prompt: "", clientMessageId: nil)
            return
        }
        guard let profile = settingsManager.primaryRecordingProfile else { return }
        let settings = settingsManager.recordingSettings
        let prompt = settings.prompt(for: type)
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let data = try? Data(contentsOf: recording.fileURL) else {
            return
        }
        let clientMessageId = wsManager.sendRecordingAudioForAsr(
            data,
            profileId: profile.id,
            settings: settings,
            source: recording.source,
            recordingId: recording.id,
            recordingType: type,
            prompt: prompt
        )
        store.configureRecordingForProcessing(
            recordingId: recording.id,
            type: type,
            prompt: prompt,
            clientMessageId: clientMessageId
        )
    }
}

private struct RecordingEventRow: View {
    let event: RecordingEventItem
    let colors: MochiColors

    private var statusText: String {
        switch event.status {
        case .pending: return "待处理"
        case .running: return "进行中"
        case .completed: return "完成"
        case .failed: return "失败"
        case .cancelled: return "取消"
        }
    }

    private var statusColor: Color {
        switch event.status {
        case .pending, .running: return colors.primary
        case .completed: return colors.onlineGreen
        case .failed: return colors.recordingRed
        case .cancelled: return .secondary
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: event.kind.systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(statusColor)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(event.title.isEmpty ? event.kind.label : event.title)
                        .font(.system(size: 14, weight: .semibold))
                    Spacer()
                    Text(statusText)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(statusColor)
                }
                if !event.content.isEmpty {
                    Text(event.content)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                }
                Text(event.createdAt.earphoneListTimeText)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 3)
    }
}

private struct RecordingMetadataRow: View {
    let title: String
    let value: String
    var valueFont: Font = .system(size: 14)

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .foregroundColor(.secondary)
            Spacer(minLength: 16)
            Text(value)
                .font(valueFont)
                .multilineTextAlignment(.trailing)
                .foregroundColor(.primary)
        }
        .font(.system(size: 14))
    }
}

private struct RecordingReminderRow: View {
    let reminder: RecordingReminderItem
    let colors: MochiColors
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: reminder.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundColor(reminder.isCompleted ? colors.onlineGreen : colors.primary)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 5) {
                    Text(reminder.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)
                    if !reminder.notes.isEmpty {
                        Text(reminder.notes)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    Text(reminder.dueAt.earphoneListTimeText)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 3)
    }
}

private struct RecordingReminderEditorView: View {
    let colors: MochiColors
    let onSave: (String, String, Date) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var notes = ""
    @State private var dueAt = Date().addingTimeInterval(3600)

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedNotes: String {
        notes.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        !trimmedTitle.isEmpty && dueAt > Date()
    }

    var body: some View {
        CompatibleNavigationStack {
            Form {
                Section("提醒") {
                    TextField("标题", text: $title)
                    TextEditor(text: $notes)
                        .frame(minHeight: 100)
                }
                Section("时间") {
                    DatePicker("提醒时间", selection: $dueAt, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                    if dueAt <= Date() {
                        Text("提醒时间需要晚于当前时间")
                            .font(.system(size: 12))
                            .foregroundColor(colors.recordingRed)
                    }
                }
            }
            .navigationTitle("新增提醒")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSave(trimmedTitle, trimmedNotes, dueAt)
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
        }
    }
}

private struct RecordingSharePayload: Identifiable {
    let id = UUID()
    let items: [Any]
}

private final class RecordingAudioPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var isPlaying = false
    private var player: AVAudioPlayer?

    func toggle(url: URL) {
        if isPlaying {
            player?.pause()
            isPlaying = false
            return
        }
        do {
            if player?.url != url {
                player = try AVAudioPlayer(contentsOf: url)
                player?.delegate = self
                player?.prepareToPlay()
            }
            player?.play()
            isPlaying = true
        } catch {
            isPlaying = false
        }
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        isPlaying = false
    }
}

#if canImport(UIKit)
private struct RecordingActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif

private enum RecordingReminderNotificationError: LocalizedError {
    case denied
    case unavailable

    var errorDescription: String? {
        switch self {
        case .denied: return "未获得通知权限"
        case .unavailable: return "当前系统不支持通知"
        }
    }
}

private final class RecordingReminderNotificationScheduler {
    static let shared = RecordingReminderNotificationScheduler()

    private let center = UNUserNotificationCenter.current()

    private init() {}

    func schedule(_ reminder: RecordingReminderItem) async throws {
        let settings = await notificationSettings()
        let authorized: Bool
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            authorized = true
        case .notDetermined:
            authorized = try await requestAuthorization()
        case .denied:
            authorized = false
        @unknown default:
            authorized = false
        }

        guard authorized else {
            throw RecordingReminderNotificationError.denied
        }

        let content = UNMutableNotificationContent()
        content.title = reminder.title
        content.body = reminder.notes.isEmpty ? "录音待办提醒" : reminder.notes
        content.sound = .default

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: reminder.dueAt
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(
            identifier: reminder.notificationId,
            content: content,
            trigger: trigger
        )
        try await add(request)
    }

    func cancel(notificationId: String) {
        center.removePendingNotificationRequests(withIdentifiers: [notificationId])
    }

    private func notificationSettings() async -> UNNotificationSettings {
        await withCheckedContinuation { continuation in
            center.getNotificationSettings { settings in
                continuation.resume(returning: settings)
            }
        }
    }

    private func requestAuthorization() async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    private func add(_ request: UNNotificationRequest) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            center.add(request) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
}
