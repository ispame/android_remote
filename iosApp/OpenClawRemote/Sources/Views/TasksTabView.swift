import SwiftUI

struct TasksTabView: View {
    @ObservedObject var wsManager: WebSocketManager
    @ObservedObject var settingsManager: SettingsManager
    @ObservedObject var audioRecorder: AudioRecorder
    @ObservedObject var headsetController: HeadsetConversationController
    @ObservedObject var scheduledTaskStore: ScheduledTaskStore
    @ObservedObject var recordingStore: RecordingStore
    let colors: MochiColors

    @State private var section: TaskListSection = .approvals
    @State private var showTaskEditor = false
    @State private var isPhoneRecording = false
    @State private var statusMessage: String?

    private var selectedAgent: AgentProfile {
        settingsManager.selectedProfile
    }

    private var approvalItems: [ApprovalHistoryItem] {
        let parsed = wsManager.messages.compactMap { message -> ApprovalHistoryItem? in
            guard let request = ApprovalRequest.detect(in: message.content) else { return nil }
            return ApprovalHistoryItem(
                id: message.id.uuidString,
                agentId: selectedAgent.id,
                title: request.title,
                command: request.command.isEmpty ? message.content : request.command,
                decision: "待审批",
                createdAt: HistoryMessagePayload.date(from: message.rawTimestamp ?? "") ?? Date()
            )
        }

        if !parsed.isEmpty {
            return parsed
        }
        return [
            ApprovalHistoryItem(
                id: "sample-approval-\(selectedAgent.id)",
                agentId: selectedAgent.id,
                title: "危险命令审批",
                command: "sudo systemctl restart openclaw-agent",
                decision: "示例",
                createdAt: Date()
            )
        ]
    }

    private var scheduledTasks: [ScheduledTask] {
        scheduledTaskStore.tasks(for: selectedAgent.id)
    }

    private var recordings: [RecordingItem] {
        recordingStore.recordings(for: selectedAgent.id)
    }

    var body: some View {
        List {
            Section {
                Picker("任务类型", selection: $section) {
                    ForEach(TaskListSection.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented)
            }

            if let statusMessage {
                Section {
                    Text(statusMessage)
                        .font(.system(size: 13))
                        .foregroundColor(colors.primary)
                }
            }

            switch section {
            case .approvals:
                approvalSection
            case .scheduled:
                scheduledSection
            case .recordings:
                recordingsSection
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("任务")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: addAction) {
                    Image(systemName: section == .recordings && isPhoneRecording ? "stop.circle.fill" : "plus")
                }
                .disabled(section == .approvals)
                .accessibilityLabel(section.addAccessibilityLabel)
            }
        }
        .sheet(isPresented: $showTaskEditor) {
            CompatibleNavigationStack {
                ScheduledTaskDetailView(
                    task: ScheduledTask(
                        agentId: selectedAgent.id,
                        title: "",
                        prompt: "",
                        cronExpression: "0 9 * * 1-5"
                    ),
                    store: scheduledTaskStore,
                    colors: colors
                )
            }
        }
    }

    private var approvalSection: some View {
        Section("审批历史") {
            ForEach(approvalItems) { item in
                NavigationLink(destination: ApprovalHistoryDetailView(item: item)) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(item.title)
                                .font(.system(size: 15, weight: .semibold))
                            Spacer()
                            Text(item.decision)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(colors.primary)
                        }
                        Text(item.command)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                        Text(item.createdAt.earphoneListTimeText)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private var scheduledSection: some View {
        Section("定时任务") {
            if scheduledTasks.isEmpty {
                Text("点击右上角 + 新增定时任务")
                    .foregroundColor(.secondary)
            } else {
                ForEach(scheduledTasks) { task in
                    NavigationLink(
                        destination: ScheduledTaskDetailView(
                            task: task,
                            store: scheduledTaskStore,
                            colors: colors
                        )
                    ) {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(task.title.isEmpty ? "未命名任务" : task.title)
                                    .font(.system(size: 15, weight: .semibold))
                                Spacer()
                                Text(task.isEnabled ? "启用" : "暂停")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(task.isEnabled ? colors.onlineGreen : .secondary)
                            }
                            Text(task.cronExpression)
                                .font(.system(size: 13, design: .monospaced))
                                .foregroundColor(colors.primary)
                            Text(task.prompt)
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
                .onDelete { offsets in
                    offsets.map { scheduledTasks[$0].id }.forEach(scheduledTaskStore.delete)
                }
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

    private func addAction() {
        switch section {
        case .approvals:
            break
        case .scheduled:
            showTaskEditor = true
        case .recordings:
            addRecording()
        }
    }

    private func addRecording() {
        if headsetIsReady {
            _ = try? recordingStore.createRecording(
                agentId: selectedAgent.id,
                audioData: Data(),
                asrText: "耳机录音已开启，等待 ASR 文本生成。",
                source: .headset
            )
            statusMessage = "已创建耳机录音记录"
            return
        }

        if isPhoneRecording {
            audioRecorder.stopRecording { data in
                _ = try? recordingStore.createRecording(
                    agentId: selectedAgent.id,
                    audioData: data,
                    asrText: "",
                    source: .phone
                )
                statusMessage = "手机录音已保存"
            }
            isPhoneRecording = false
        } else {
            audioRecorder.startRecording()
            isPhoneRecording = true
            statusMessage = "手机麦克风录音中，再点一次保存"
        }
    }

    private var headsetIsReady: Bool {
        if case .ready = headsetController.connectionState {
            return true
        }
        return false
    }
}

private enum TaskListSection: String, CaseIterable, Identifiable {
    case approvals
    case scheduled
    case recordings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .approvals: return "审批"
        case .scheduled: return "定时"
        case .recordings: return "录音"
        }
    }

    var addAccessibilityLabel: String {
        switch self {
        case .approvals: return "审批历史不可新增"
        case .scheduled: return "新增定时任务"
        case .recordings: return "新增录音"
        }
    }
}

private struct ApprovalHistoryDetailView: View {
    let item: ApprovalHistoryItem

    var body: some View {
        List {
            Section("状态") {
                Text(item.decision)
                Text(item.createdAt.earphoneListTimeText)
            }
            Section("命令") {
                Text(item.command)
                    .font(.system(size: 13, design: .monospaced))
            }
        }
        .navigationTitle(item.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ScheduledTaskDetailView: View {
    @ObservedObject var store: ScheduledTaskStore
    let colors: MochiColors
    @Environment(\.dismiss) private var dismiss

    @State private var editingTask: ScheduledTask
    @State private var title: String
    @State private var prompt: String
    @State private var cronExpression: String
    @State private var isEnabled: Bool

    init(task: ScheduledTask, store: ScheduledTaskStore, colors: MochiColors) {
        self.store = store
        self.colors = colors
        _editingTask = State(initialValue: task)
        _title = State(initialValue: task.title)
        _prompt = State(initialValue: task.prompt)
        _cronExpression = State(initialValue: task.cronExpression)
        _isEnabled = State(initialValue: task.isEnabled)
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        CronExpressionValidator.isValid(cronExpression)
    }

    var body: some View {
        Form {
            Section("任务") {
                TextField("标题", text: $title)
                TextEditor(text: $prompt)
                    .frame(minHeight: 140)
                Toggle("启用", isOn: $isEnabled)
            }
            Section("Cron") {
                TextField("0 9 * * 1-5", text: $cronExpression)
                    .font(.system(size: 14, design: .monospaced))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if !CronExpressionValidator.isValid(cronExpression) {
                    Text("请输入 5 段 cron，例如 */15 * * * *")
                        .font(.system(size: 12))
                        .foregroundColor(colors.recordingRed)
                }
            }
        }
        .navigationTitle(editingTask.title.isEmpty ? "新增定时任务" : "定时任务")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("返回") { dismiss() }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    startNewTaskDraft()
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("新增定时任务")
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    store.save(
                        ScheduledTask(
                            id: editingTask.id,
                            agentId: editingTask.agentId,
                            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                            prompt: prompt.trimmingCharacters(in: .whitespacesAndNewlines),
                            cronExpression: cronExpression.trimmingCharacters(in: .whitespacesAndNewlines),
                            isEnabled: isEnabled,
                            createdAt: editingTask.createdAt
                        )
                    )
                    dismiss()
                }
                .disabled(!canSave)
            }
        }
    }

    private func startNewTaskDraft() {
        editingTask = ScheduledTask(
            agentId: editingTask.agentId,
            title: "",
            prompt: "",
            cronExpression: "0 9 * * 1-5"
        )
        title = ""
        prompt = ""
        cronExpression = editingTask.cronExpression
        isEnabled = true
    }
}

private struct RecordingDetailView: View {
    let recording: RecordingItem
    @ObservedObject var store: RecordingStore
    let colors: MochiColors
    @State private var asrText: String

    init(recording: RecordingItem, store: RecordingStore, colors: MochiColors) {
        self.recording = recording
        self.store = store
        self.colors = colors
        _asrText = State(initialValue: recording.asrText)
    }

    var body: some View {
        Form {
            Section("录音") {
                Text(recording.createdAt.earphoneListTimeText)
                Text(recording.source.label)
                Text(recording.fileURL.lastPathComponent)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            Section("ASR 文本") {
                TextEditor(text: $asrText)
                    .frame(minHeight: 220)
            }
        }
        .navigationTitle("录音详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    var copy = recording
                    copy.asrText = asrText
                    store.update(copy)
                }
            }
        }
    }
}
