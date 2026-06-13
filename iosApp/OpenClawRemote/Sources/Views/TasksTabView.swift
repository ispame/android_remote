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
                    Text(isPhoneRecording ? "结束录音" : "开始录音")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(isPhoneRecording ? colors.primary : colors.textSecondary)
                }
            }
        }
        .sheet(item: $typeSelectionContext) { context in
            RecordingTypeSelectionView(
                recording: context.recording,
                settings: settingsManager.recordingSettings,
                colors: colors,
                profiles: settingsManager.profiles.filter { !$0.backendId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            ) { type, profileId in
                processRecording(context.recording, as: type, profileId: profileId)
            }
        }
        .onChange(of: headsetController.pendingHeadsetRecording) { recording in
            if let recording = recording {
                typeSelectionContext = RecordingTypeSelectionContext(recording: recording)
                headsetController.clearPendingHeadsetRecording()
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
                let settings = settingsManager.recordingSettings
                let defaultType = settings.defaultRecordingType
                let defaultPrompt = settings.prompt(for: defaultType)

                guard let recording = try? self.recordingStore.createRecording(
                    agentId: recordingProfile.id,
                    audioData: data,
                    asrText: "",
                    prompt: defaultPrompt,
                    recordingType: defaultType,
                    processingStatus: settings.defaultDeliverToAgent && defaultType != .audioOnly ? .processing : .savedOnly,
                    selectedPrompt: defaultPrompt,
                    source: .phone
                ) else {
                    self.statusMessage = "手机录音保存失败"
                    return
                }
                self.statusMessage = "手机录音已保存"
                if settings.defaultDeliverToAgent && defaultType != .audioOnly {
                    self.processRecording(recording, as: defaultType)
                } else {
                    self.typeSelectionContext = RecordingTypeSelectionContext(recording: recording)
                }
            }
            isPhoneRecording = false
        } else {
            audioRecorder.startRecording()
            isPhoneRecording = true
            statusMessage = "手机麦克风录音中，再点一次保存"
        }
    }

    private func processRecording(_ recording: RecordingItem, as type: RecordingType, profileId: String? = nil) {
        if type == .audioOnly {
            recordingStore.configureRecordingForProcessing(recordingId: recording.id, type: .audioOnly, prompt: "", clientMessageId: nil)
            statusMessage = "录音已保存为仅录音"
            return
        }
        let targetProfileId: String
        if let pid = profileId, !pid.isEmpty {
            targetProfileId = pid
        } else {
            guard let recordingProfile = settingsManager.primaryRecordingProfile else {
                statusMessage = "请先配置主 Agent"
                return
            }
            targetProfileId = recordingProfile.id
        }
        let settings = settingsManager.recordingSettings
        let prompt = settings.prompt(for: type)
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            statusMessage = "请先在录音设置中填写自定义 Prompt"
            return
        }
        var currentJobId = ""
        let clientMessageId = wsManager.sendLongRecordingAudioForAsr(
            fileURL: recording.fileURL,
            profileId: targetProfileId,
            settings: settings,
            source: recording.source,
            recordingId: recording.id,
            recordingType: type,
            prompt: prompt,
            onUploadProgress: { _, progress in
                guard !currentJobId.isEmpty else { return }
                recordingStore.updateAsrJob(recordingId: recording.id, jobId: currentJobId, uploadProgress: progress, asrProgress: 0)
            },
            onJobCreated: { _, jobId in
                currentJobId = jobId
                recordingStore.updateAsrJob(recordingId: recording.id, jobId: jobId, uploadProgress: 0, asrProgress: 0)
            },
            onJobUpdate: { payload in
                recordingStore.applyLongRecordingAsrJob(payload, fallbackRecordingId: recording.id)
            },
            onJobExpired: { recordingId in
                recordingStore.updateAsrFailure(recordingId: recordingId, error: "ASR 任务已过期，请重新转写")
            },
            onFailure: { clientMessageId, error in
                recordingStore.updateAsrFailure(clientMessageId: clientMessageId, error: error)
            }
        )
        recordingStore.configureRecordingForProcessing(
            recordingId: recording.id,
            type: type,
            prompt: prompt,
            clientMessageId: clientMessageId
        )
        statusMessage = clientMessageId == nil ? "录音已保存；Agent 未连接，未发送 ASR" : "录音已发送，等待 ASR 和 Agent 处理"
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
    let profiles: [AgentProfile]
    let onSelect: (RecordingType, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedType: RecordingType
    @State private var selectedProfileId: String

    init(
        recording: RecordingItem,
        settings: RecordingSettings,
        colors: MochiColors,
        profiles: [AgentProfile],
        onSelect: @escaping (RecordingType, String) -> Void
    ) {
        self.recording = recording
        self.settings = settings
        self.colors = colors
        self.profiles = profiles
        self.onSelect = onSelect
        _selectedType = State(initialValue: settings.defaultRecordingType == .custom && settings.customPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .audioOnly : settings.defaultRecordingType)
        _selectedProfileId = State(initialValue: settings.primaryAgentProfileId)
    }

    var body: some View {
        NavigationView {
            List {
                Section("录音类型") {
                    ForEach(availableTypes) { type in
                        Button {
                            selectedType = type
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
                                if type == selectedType {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(colors.primary)
                                }
                            }
                        }
                        .disabled(type == .custom && settings.customPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }

                if selectedType != .audioOnly {
                    Section("发送到") {
                        ForEach(profiles) { profile in
                            Button {
                                selectedProfileId = profile.id
                            } label: {
                                HStack {
                                    Text(profile.resolvedDisplayName)
                                        .foregroundColor(.primary)
                                    Spacer()
                                    if profile.id == selectedProfileId {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(colors.primary)
                                    }
                                }
                            }
                        }
                    }
                }

                Section {
                    Button {
                        onSelect(selectedType, selectedProfileId)
                        dismiss()
                    } label: {
                        HStack {
                            Spacer()
                            Text(selectedType == .audioOnly ? "保存" : "发送给 \(selectedProfileName)")
                                .font(.system(size: 15, weight: .semibold))
                            Spacer()
                        }
                    }
                    .foregroundColor(.white)
                    .listRowBackground(colors.primary)
                }
            }
            .navigationTitle("处理录音")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private var availableTypes: [RecordingType] {
        RecordingType.allCases.filter { type in
            if type == .custom {
                return !settings.customPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            return true
        }
    }

    private var selectedProfileName: String {
        profiles.first(where: { $0.id == selectedProfileId })?.resolvedDisplayName ?? "Agent"
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
    @State private var isPromptExpanded = false
    @State private var isAsrExpanded = false
    @State private var isProgressExpanded = false
    @State private var isMetadataExpanded = false
    @State private var workflowActionError: String?
    @State private var activeWorkflowActionTaskId: String?
    @State private var editingWorkflowTask: RecordingExecutionTaskSnapshot?
    @State private var isRedeliveringToAgent = false
    @State private var deliveryActionError: String?
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

    private var recordingFileExists: Bool {
        FileManager.default.fileExists(atPath: currentRecording.fileURL.path)
    }

    private var asrNeedsRetry: Bool {
        currentRecording.processingStatus == .failed
            && currentRecording.asrText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var presentation: RecordingDetailPresentation {
        RecordingDetailPresentation(recording: currentRecording)
    }

    private var reminders: [RecordingReminderItem] {
        currentRecording.reminders.sorted { $0.dueAt < $1.dueAt }
    }

    var body: some View {
        Form {
            recordingSummarySection
            agentReplySection
            agentTasksSection
            humanTodosSection
            scheduledTasksSection
            collapsedDetailSection
        }
        .navigationTitle("录音详情")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            asrText = currentRecording.asrText
            refreshWorkflowSnapshot()
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
                colors: colors,
                profiles: settingsManager.profiles.filter { !$0.backendId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            ) { type, profileId in
                processRecording(context.recording, as: type, profileId: profileId)
            }
        }
        .sheet(item: $sharePayload) { payload in
            RecordingActivityView(activityItems: payload.items)
        }
        .sheet(item: $editingWorkflowTask) { task in
            RecordingTaskEditorView(task: task, colors: colors) { prompt, executor, model, sources, maxAttempts in
                updateTask(
                    task,
                    prompt: prompt,
                    executorHint: executor,
                    modelHint: model,
                    sourceConstraints: sources,
                    maxAttempts: maxAttempts
                )
            }
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

    private var recordingSummarySection: some View {
        Section("录音") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(currentRecording.createdAt.earphoneListTimeText)
                        .font(.system(size: 15, weight: .semibold))
                    Spacer()
                    Text(currentRecording.processingStatus.label)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(colors.primary)
                }
                HStack(spacing: 12) {
                    Label(currentRecording.recordingType.label, systemImage: currentRecording.recordingType.systemImage)
                    Label(currentRecording.source.label, systemImage: "mic")
                }
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            }
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
                Label(
                    asrNeedsRetry
                        ? "重新转写"
                        : (currentRecording.recordingType == .audioOnly ? "选择录音类型" : "重新处理录音"),
                    systemImage: "arrow.triangle.2.circlepath"
                )
            }
            .disabled(!recordingFileExists)
            if asrNeedsRetry && !recordingFileExists {
                Text("本地录音文件已不存在，无法重新转写")
                    .font(.system(size: 12))
                    .foregroundColor(colors.recordingRed)
            }
            if let deliveryStatus = currentRecording.agentDeliveryStatus,
               currentRecording.recordingType.sendsToAgent,
               !currentRecording.asrText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                HStack {
                    Label(deliveryStatus.label, systemImage: deliveryStatus == .delivered ? "checkmark.circle" : "paperplane")
                    Spacer()
                    if currentRecording.agentDeliveryAttempts > 0 {
                        Text("尝试 \(currentRecording.agentDeliveryAttempts) 次")
                            .foregroundColor(.secondary)
                    }
                }
                .font(.system(size: 12))
                if let error = currentRecording.agentDeliveryError, !error.isEmpty {
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundColor(colors.recordingRed)
                }
                if deliveryStatus.canRetry,
                   currentRecording.agentDeliveryRetryable,
                   currentRecording.asrJobId?.isEmpty == false {
                    Button {
                        redeliverToAgent()
                    } label: {
                        Label(
                            isRedeliveringToAgent ? "正在重新发送..." : "重新发送给 Agent",
                            systemImage: "paperplane.circle"
                        )
                    }
                    .disabled(isRedeliveringToAgent)
                }
            }
            if let deliveryActionError {
                Text(deliveryActionError)
                    .font(.system(size: 12))
                    .foregroundColor(colors.recordingRed)
            }
        }
    }

    @ViewBuilder
    private var agentReplySection: some View {
        if let reply = presentation.latestAgentReply {
            Section("Agent 回复") {
                RecordingEventRow(event: reply, colors: colors)
            }
        }
    }

    private var agentTasksSection: some View {
        Section("Agent 执行任务") {
            if let workflow = currentRecording.workflow {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(workflow.title)
                            .font(.system(size: 14, weight: .semibold))
                        Spacer()
                        Text(workflow.status.label)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(workflowStatusColor(workflow.status))
                    }
                    ProgressView(value: workflow.progress)
                    Text(
                        "成功 \(workflow.successfulTaskCount) · 降级 \(workflow.degradedTaskCount) · " +
                        "失败 \(workflow.failedTaskCount) · 阻塞 \(workflow.blockedTaskCount)"
                    )
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Text("\(workflow.completedTaskCount) / \(workflow.businessTaskCount) 项可用于报告")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    if let summary = workflow.summary, !summary.isEmpty {
                        Text(summary)
                            .font(.system(size: 13))
                    }
                    ForEach(workflow.warnings ?? [], id: \.self) { warning in
                        Label(warning, systemImage: "exclamationmark.triangle")
                            .font(.system(size: 12))
                            .foregroundColor(colors.recordingRed)
                    }
                    if let artifact = workflow.finalArtifact {
                        VStack(alignment: .leading, spacing: 4) {
                            Label(artifact.filename, systemImage: "doc.richtext")
                                .font(.system(size: 13, weight: .semibold))
                            if let content = artifact.content, !content.isEmpty {
                                Text(content)
                                    .font(.system(size: 12))
                                    .lineLimit(8)
                                    .textSelection(.enabled)
                            }
                            if let reference = artifact.downloadUrl ?? artifact.retrievalRef,
                               !reference.isEmpty {
                                Text(reference)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                    if !workflow.status.isTerminal {
                        HStack {
                            if workflow.status == .paused {
                                Button {
                                    runWorkflowAction(.resume, workflow: workflow)
                                } label: {
                                    Label("恢复", systemImage: "play.circle")
                                }
                            } else {
                                Button {
                                    runWorkflowAction(.pause, workflow: workflow)
                                } label: {
                                    Label("暂停", systemImage: "pause.circle")
                                }
                            }
                            Button {
                                runWorkflowAction(.finalize, workflow: workflow)
                            } label: {
                                Label("立即生成报告", systemImage: "doc.badge.gearshape")
                            }
                        }
                        Button(role: .destructive) {
                            runWorkflowAction(.cancel, workflow: workflow)
                        } label: {
                            Label("立即终止", systemImage: "xmark.circle")
                        }
                    }
                }
                ForEach(workflow.tasks) { task in
                    RecordingExecutionTaskRow(
                        task: task,
                        isActing: activeWorkflowActionTaskId == task.taskId,
                        colors: colors,
                        onAction: { action in
                            runTaskAction(action, task: task, workflow: workflow)
                        },
                        onEdit: {
                            editingWorkflowTask = task
                        }
                    )
                }
                if let workflowActionError {
                    Text(workflowActionError)
                        .font(.system(size: 12))
                        .foregroundColor(colors.recordingRed)
                }
            } else if presentation.agentTaskGroups.isEmpty {
                Text(wsManager.recordingExecutionSupported
                     ? "等待 Agent 生成并提交执行计划"
                     : "当前 Agent 未声明自动执行能力，继续显示兼容录音事件")
                    .foregroundColor(.secondary)
            } else {
                ForEach(presentation.agentTaskGroups) { group in
                    RecordingAgentTaskGroupRow(group: group, colors: colors) { artifact in
                        sharePayload = RecordingSharePayload(items: [artifact.fileURL])
                    }
                }
            }
            if !presentation.unassignedArtifacts.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("未关联文件")
                        .font(.system(size: 13, weight: .semibold))
                    ForEach(presentation.unassignedArtifacts) { artifact in
                        RecordingArtifactRow(artifact: artifact, colors: colors) {
                            sharePayload = RecordingSharePayload(items: [artifact.fileURL])
                        }
                    }
                }
                .padding(.vertical, 3)
            }
        }
    }

    private func workflowStatusColor(_ status: RecordingWorkflowStatus) -> Color {
        switch status {
        case .succeeded: return colors.onlineGreen
        case .partial, .failed: return colors.recordingRed
        case .cancelled: return .secondary
        case .paused: return .secondary
        case .planning, .running, .waitingApproval: return colors.primary
        }
    }

    private func refreshWorkflowSnapshot() {
        guard wsManager.recordingExecutionSupported, currentRecording.recordingType.sendsToAgent else { return }
        Task {
            guard let workflow = try? await wsManager.fetchRecordingWorkflow(recordingId: currentRecording.id) else {
                return
            }
            await MainActor.run {
                store.upsertWorkflow(workflow)
            }
        }
    }

    private func runTaskAction(
        _ action: RecordingTaskAction,
        task: RecordingExecutionTaskSnapshot,
        workflow: RecordingWorkflowSnapshot
    ) {
        activeWorkflowActionTaskId = task.taskId
        workflowActionError = nil
        Task {
            do {
                let updated = try await wsManager.performRecordingTaskAction(
                    workflowId: workflow.workflowId,
                    taskId: task.taskId,
                    action: action,
                    expectedRevision: workflow.effectiveRevision
                )
                await MainActor.run {
                    store.upsertWorkflow(updated)
                    activeWorkflowActionTaskId = nil
                }
            } catch {
                await MainActor.run {
                    workflowActionError = error.localizedDescription
                    activeWorkflowActionTaskId = nil
                }
            }
        }
    }

    private func runWorkflowAction(
        _ action: RecordingWorkflowAction,
        workflow: RecordingWorkflowSnapshot
    ) {
        activeWorkflowActionTaskId = workflow.workflowId
        workflowActionError = nil
        Task {
            do {
                let updated = try await wsManager.performRecordingWorkflowAction(
                    workflowId: workflow.workflowId,
                    action: action,
                    expectedRevision: workflow.effectiveRevision
                )
                await MainActor.run {
                    store.upsertWorkflow(updated)
                    activeWorkflowActionTaskId = nil
                }
            } catch {
                await MainActor.run {
                    workflowActionError = error.localizedDescription
                    activeWorkflowActionTaskId = nil
                }
            }
        }
    }

    private func updateTask(
        _ task: RecordingExecutionTaskSnapshot,
        prompt: String,
        executorHint: String?,
        modelHint: String?,
        sourceConstraints: [String],
        maxAttempts: Int
    ) {
        guard let workflow = currentRecording.workflow else { return }
        activeWorkflowActionTaskId = task.taskId
        workflowActionError = nil
        Task {
            do {
                let updated = try await wsManager.updateRecordingTask(
                    workflowId: workflow.workflowId,
                    taskId: task.taskId,
                    expectedRevision: workflow.effectiveRevision,
                    prompt: prompt,
                    executorHint: executorHint,
                    modelHint: modelHint,
                    sourceConstraints: sourceConstraints,
                    maxAttempts: maxAttempts
                )
                await MainActor.run {
                    store.upsertWorkflow(updated)
                    editingWorkflowTask = nil
                    activeWorkflowActionTaskId = nil
                }
            } catch {
                await MainActor.run {
                    workflowActionError = error.localizedDescription
                    activeWorkflowActionTaskId = nil
                }
            }
        }
    }

    private var humanTodosSection: some View {
        Section {
            if let reminderError {
                Text(reminderError)
                    .font(.system(size: 13))
                    .foregroundColor(colors.recordingRed)
            }
            if presentation.humanTodos.isEmpty && reminders.isEmpty {
                Text("需要用户或其他人完成的待办会在这里展示")
                    .foregroundColor(.secondary)
            } else {
                ForEach(presentation.humanTodos) { event in
                    RecordingEventRow(event: event, colors: colors)
                }
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
                Text("需要人完成的待办")
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

    @ViewBuilder
    private var scheduledTasksSection: some View {
        if !presentation.scheduledEvents.isEmpty {
            Section("导出的定时任务") {
                ForEach(presentation.scheduledEvents) { event in
                    RecordingEventRow(event: event, colors: colors)
                }
            }
        }
    }

    private var collapsedDetailSection: some View {
        Section("更多") {
            DisclosureGroup("录音 Prompt", isExpanded: $isPromptExpanded) {
                Text(currentRecording.selectedPrompt.isEmpty ? "仅录音无 Prompt" : currentRecording.selectedPrompt)
                    .font(.system(size: 13))
                    .textSelection(.enabled)
            }
            DisclosureGroup("ASR 文本", isExpanded: $isAsrExpanded) {
                TextEditor(text: $asrText)
                    .frame(minHeight: 220)
            }
            DisclosureGroup("执行进度", isExpanded: $isProgressExpanded) {
                if presentation.generalTimelineEvents.isEmpty {
                    Text("Agent 执行进度会在这里展示")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(presentation.generalTimelineEvents) { event in
                        RecordingEventRow(event: event, colors: colors)
                    }
                }
            }
            DisclosureGroup("录音文件/元数据", isExpanded: $isMetadataExpanded) {
                RecordingMetadataRow(title: "时间", value: currentRecording.createdAt.earphoneListTimeText)
                RecordingMetadataRow(title: "来源", value: currentRecording.source.label)
                RecordingMetadataRow(title: "类型", value: currentRecording.recordingType.label)
                RecordingMetadataRow(title: "状态", value: currentRecording.processingStatus.label)
                if let jobId = currentRecording.asrJobId, !jobId.isEmpty {
                    RecordingMetadataRow(title: "ASR Job", value: jobId, valueFont: .system(size: 12, design: .monospaced))
                    ProgressView("上传 \(Int(currentRecording.uploadProgress * 100))%", value: currentRecording.uploadProgress)
                    ProgressView("转写 \(Int(currentRecording.asrProgress * 100))%", value: currentRecording.asrProgress)
                }
                if let error = currentRecording.asrError, !error.isEmpty {
                    RecordingMetadataRow(title: "错误", value: error)
                }
                if let deliveryStatus = currentRecording.agentDeliveryStatus {
                    RecordingMetadataRow(title: "Agent 投递", value: deliveryStatus.label)
                }
                if let deliveryError = currentRecording.agentDeliveryError, !deliveryError.isEmpty {
                    RecordingMetadataRow(title: "投递错误", value: deliveryError)
                }
                RecordingMetadataRow(
                    title: "文件",
                    value: currentRecording.fileURL.lastPathComponent,
                    valueFont: .system(size: 12, design: .monospaced)
                )
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

    private func processRecording(_ recording: RecordingItem, as type: RecordingType, profileId: String? = nil) {
        if type == .audioOnly {
            store.configureRecordingForProcessing(recordingId: recording.id, type: .audioOnly, prompt: "", clientMessageId: nil)
            return
        }
        let targetProfileId: String
        if let pid = profileId, !pid.isEmpty {
            targetProfileId = pid
        } else if let primary = settingsManager.primaryRecordingProfile {
            targetProfileId = primary.id
        } else {
            return
        }
        let settings = settingsManager.recordingSettings
        let prompt = settings.prompt(for: type)
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        var currentJobId = ""
        let clientMessageId = wsManager.sendLongRecordingAudioForAsr(
            fileURL: recording.fileURL,
            profileId: targetProfileId,
            settings: settings,
            source: recording.source,
            recordingId: recording.id,
            recordingType: type,
            prompt: prompt,
            onUploadProgress: { _, progress in
                guard !currentJobId.isEmpty else { return }
                store.updateAsrJob(recordingId: recording.id, jobId: currentJobId, uploadProgress: progress, asrProgress: 0)
            },
            onJobCreated: { _, jobId in
                currentJobId = jobId
                store.updateAsrJob(recordingId: recording.id, jobId: jobId, uploadProgress: 0, asrProgress: 0)
            },
            onJobUpdate: { payload in
                store.applyLongRecordingAsrJob(payload, fallbackRecordingId: recording.id)
            },
            onJobExpired: { recordingId in
                store.updateAsrFailure(recordingId: recordingId, error: "ASR 任务已过期，请重新转写")
            },
            onFailure: { clientMessageId, error in
                store.updateAsrFailure(clientMessageId: clientMessageId, error: error)
            }
        )
        store.configureRecordingForProcessing(
            recordingId: recording.id,
            type: type,
            prompt: prompt,
            clientMessageId: clientMessageId
        )
    }

    private func redeliverToAgent() {
        guard let jobId = currentRecording.asrJobId, !jobId.isEmpty else { return }
        isRedeliveringToAgent = true
        deliveryActionError = nil
        Task {
            do {
                let payload = try await wsManager.redeliverLongRecordingAsrJob(jobId: jobId)
                await MainActor.run {
                    store.applyLongRecordingAsrJob(payload, fallbackRecordingId: currentRecording.id)
                    isRedeliveringToAgent = false
                    wsManager.monitorLongRecordingAsrJob(jobId: jobId) { payload in
                        store.applyLongRecordingAsrJob(payload, fallbackRecordingId: currentRecording.id)
                    } onExpired: {
                        store.updateAsrFailure(recordingId: currentRecording.id, error: "ASR 任务已过期，请重新转写")
                    }
                }
            } catch {
                await MainActor.run {
                    deliveryActionError = error.localizedDescription
                    isRedeliveringToAgent = false
                }
            }
        }
    }
}

private struct RecordingExecutionTaskRow: View {
    let task: RecordingExecutionTaskSnapshot
    let isActing: Bool
    let colors: MochiColors
    let onAction: (RecordingTaskAction) -> Void
    let onEdit: () -> Void

    private var statusColor: Color {
        switch task.status {
        case .succeeded: return colors.onlineGreen
        case .degraded: return .orange
        case .failed, .blocked: return colors.recordingRed
        case .cancelled, .paused: return .secondary
        case .planned, .queued, .running, .waitingApproval: return colors.primary
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 5) {
                    Text(task.title)
                        .font(.system(size: 14, weight: .semibold))
                    if task.systemKind == "summary" {
                        Text("最终汇总")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                Text(task.status.label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(statusColor)
            }
            Text(task.prompt)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
            HStack(spacing: 12) {
                Text("尝试 \(task.attempt)/\(task.maxAttempts)")
                if !task.dependsOn.isEmpty {
                    Text("依赖 \(task.dependsOn.joined(separator: ", "))")
                }
            }
            .font(.system(size: 11))
            .foregroundColor(.secondary)
            HStack(spacing: 10) {
                if let criticality = task.criticality {
                    Text("级别 \(criticality)")
                }
                if let policy = task.dependencyPolicy {
                    Text("依赖策略 \(policy)")
                }
                if let confidence = task.confidence {
                    Text("置信度 \(Int(confidence * 100))%")
                }
            }
            .font(.system(size: 10))
            .foregroundColor(.secondary)
            if let executor = task.executorHint, !executor.isEmpty {
                Text("执行器：\(executor)")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            if let model = task.modelHint, !model.isEmpty {
                Text("模型：\(model)")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            if let sources = task.sourceConstraints, !sources.isEmpty {
                Text("来源约束：\(sources.joined(separator: "、"))")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            if let result = task.resultSummary, !result.isEmpty {
                Text(result)
                    .font(.system(size: 13))
            }
            if let error = task.lastError, !error.isEmpty {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundColor(colors.recordingRed)
            }
            if let riskReason = task.riskReason, !riskReason.isEmpty {
                Label(riskReason, systemImage: "exclamationmark.shield")
                    .font(.system(size: 12))
                    .foregroundColor(colors.primary)
            }
            ForEach(task.warnings ?? [], id: \.self) { warning in
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 12))
                    .foregroundColor(.orange)
            }
            if let blockers = task.blockingTaskIds, !blockers.isEmpty {
                Label("阻塞来源：\(blockers.joined(separator: ", "))", systemImage: "link.badge.plus")
                    .font(.system(size: 12))
                    .foregroundColor(colors.recordingRed)
            }
            if !task.evidence.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("证据")
                        .font(.system(size: 12, weight: .semibold))
                    ForEach(task.evidence) { evidence in
                        Text(evidenceText(evidence))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }
            if !task.artifacts.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("产物")
                        .font(.system(size: 12, weight: .semibold))
                    ForEach(task.artifacts) { artifact in
                        VStack(alignment: .leading, spacing: 2) {
                            Label(artifact.filename, systemImage: "doc")
                            if let path = artifact.backendPath, !path.isEmpty {
                                Text(path)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .textSelection(.enabled)
                            }
                            if let sha256 = artifact.sha256, !sha256.isEmpty {
                                Text("SHA256 \(sha256)")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .textSelection(.enabled)
                            }
                        }
                        .font(.system(size: 12))
                    }
                }
            }

            if isActing {
                ProgressView()
            } else {
                if isEditable {
                    Button {
                        onEdit()
                    } label: {
                        Label("编辑任务", systemImage: "slider.horizontal.3")
                    }
                }
                actionButtons
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var actionButtons: some View {
        if supportedActions.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(supportedActions, id: \.rawValue) { action in
                    Button(role: action == .reject || action == .cancel ? .destructive : nil) {
                        onAction(action)
                    } label: {
                        Label(action.label, systemImage: action.systemImage)
                    }
                }
            }
        }
    }

    private var supportedActions: [RecordingTaskAction] {
        let advertised = (task.availableActions ?? []).compactMap { value in
            RecordingTaskAction(rawValue: value.replacingOccurrences(of: "_", with: "-"))
        }
        if !advertised.isEmpty { return advertised }
        switch task.status {
        case .waitingApproval: return [.approve, .reject, .skip]
        case .failed, .degraded: return [.retry, .skip]
        case .blocked: return [.retryBlockers, .skip]
        case .cancelled: return [.reopen, .skip]
        case .running, .queued: return [.cancel]
        case .planned, .paused, .succeeded: return []
        }
    }

    private var isEditable: Bool {
        task.systemKind != "summary" && ![.running, .succeeded, .degraded].contains(task.status)
    }

    private func evidenceText(_ evidence: RecordingTaskEvidence) -> String {
        var parts = [evidence.description]
        if let path = evidence.path, !path.isEmpty { parts.append(path) }
        if let exitCode = evidence.exitCode { parts.append("exit=\(exitCode)") }
        if let passed = evidence.passed { parts.append(passed ? "passed" : "failed") }
        if let receiptId = evidence.receiptId, !receiptId.isEmpty { parts.append("receipt=\(receiptId)") }
        if let url = evidence.url, !url.isEmpty { parts.append(url) }
        if evidence.verified == false { parts.append("未验证") }
        return parts.joined(separator: " · ")
    }
}

private struct RecordingTaskEditorView: View {
    let task: RecordingExecutionTaskSnapshot
    let colors: MochiColors
    let onSave: (String, String?, String?, [String], Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var prompt: String
    @State private var executorHint: String
    @State private var modelHint: String
    @State private var sourceConstraints: String
    @State private var maxAttempts: Int

    init(
        task: RecordingExecutionTaskSnapshot,
        colors: MochiColors,
        onSave: @escaping (String, String?, String?, [String], Int) -> Void
    ) {
        self.task = task
        self.colors = colors
        self.onSave = onSave
        _prompt = State(initialValue: task.prompt)
        _executorHint = State(initialValue: task.executorHint ?? "")
        _modelHint = State(initialValue: task.modelHint ?? "")
        _sourceConstraints = State(initialValue: (task.sourceConstraints ?? []).joined(separator: ", "))
        _maxAttempts = State(initialValue: min(2, max(1, task.maxAttempts)))
    }

    var body: some View {
        NavigationView {
            Form {
                Section("任务") {
                    Text(task.title)
                    TextEditor(text: $prompt)
                        .frame(minHeight: 140)
                }
                Section("执行约束") {
                    TextField("执行器，例如 hermes", text: $executorHint)
                    TextField("模型名称", text: $modelHint)
                    TextField("来源约束，逗号分隔", text: $sourceConstraints)
                    Picker("最多执行次数", selection: $maxAttempts) {
                        Text("1 次").tag(1)
                        Text("2 次").tag(2)
                    }
                }
                Text("已完成任务不可修改；本次保存会创建新的 workflow revision。")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .navigationTitle("编辑任务")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSave(
                            prompt.trimmingCharacters(in: .whitespacesAndNewlines),
                            nilIfBlank(executorHint),
                            nilIfBlank(modelHint),
                            sourceConstraints
                                .split(separator: ",")
                                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                                .filter { !$0.isEmpty },
                            maxAttempts
                        )
                    }
                    .disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func nilIfBlank(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
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
                if let nextAction = event.recordingNextAction {
                    Text("下一步：\(nextAction)")
                        .font(.system(size: 12))
                        .foregroundColor(colors.primary)
                        .textSelection(.enabled)
                }
                if let assumptions = event.recordingAssumptions {
                    Text("假设：\(assumptions)")
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

private struct RecordingAgentTaskGroupRow: View {
    let group: RecordingAgentTaskGroup
    let colors: MochiColors
    let onShareArtifact: (RecordingArtifactItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RecordingEventRow(event: group.event, colors: colors)
            if !group.artifacts.isEmpty {
                Divider()
                Text("文件结果")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                ForEach(group.artifacts) { artifact in
                    RecordingArtifactRow(artifact: artifact, colors: colors) {
                        onShareArtifact(artifact)
                    }
                }
            }
        }
        .padding(.vertical, 3)
    }
}

private struct RecordingArtifactRow: View {
    let artifact: RecordingArtifactItem
    let colors: MochiColors
    let onShare: () -> Void

    var body: some View {
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
            Button(action: onShare) {
                Image(systemName: "square.and.arrow.up")
            }
            .accessibilityLabel("分享文件")
        }
        .padding(.vertical, 3)
    }
}

private extension RecordingEventItem {
    var recordingOwner: String {
        metadata["owner"]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    }

    var recordingNeedsUserInput: Bool {
        let rawValue = metadata["needs_user_input"]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return rawValue == "true" || rawValue == "1" || rawValue == "yes"
    }

    var recordingNextAction: String? {
        displayMetadataValue(for: "next_action")
    }

    var recordingAssumptions: String? {
        displayMetadataValue(for: "assumptions")
    }

    private func displayMetadataValue(for key: String) -> String? {
        guard let value = metadata[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
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
