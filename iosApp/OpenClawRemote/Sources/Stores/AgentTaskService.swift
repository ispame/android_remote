import Foundation
import Combine

final class AgentTaskService: ObservableObject {
    private enum RequestKind {
        case list
        case create
        case update
        case delete
        case approvals
    }

    private struct PendingRequest {
        let profileId: String
        let kind: RequestKind
        let deadline: Date
    }

    private let defaults: UserDefaults
    private let cacheKey = "agent_task_cache_v1"
    private let timeoutInterval: TimeInterval
    private var cancellable: AnyCancellable?
    private weak var wsManager: WebSocketManager?
    private var pending: [String: PendingRequest] = [:]

    @Published private(set) var tasksByProfileId: [String: [AgentTaskItem]]
    @Published private(set) var approvalsByProfileId: [String: [ApprovalHistoryItem]]
    @Published private(set) var loadingProfileIds: Set<String> = []
    @Published private(set) var errorsByProfileId: [String: String] = [:]
    @Published private(set) var capabilityByProfileId: [String: String] = [:]
    @Published private(set) var operationMessagesByProfileId: [String: String] = [:]

    init(defaults: UserDefaults = .standard, timeoutInterval: TimeInterval = 12) {
        self.defaults = defaults
        self.timeoutInterval = timeoutInterval
        let cache = Self.loadCache(from: defaults, key: cacheKey)
        self.tasksByProfileId = cache.tasksByProfileId
        self.approvalsByProfileId = [:]
    }

    func bind(to wsManager: WebSocketManager) {
        self.wsManager = wsManager
        cancellable = wsManager.messageChannel
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                self?.handle(event)
            }
    }

    func tasks(for profileId: String) -> [AgentTaskItem] {
        tasksByProfileId[profileId] ?? []
    }

    func approvals(for profileId: String) -> [ApprovalHistoryItem] {
        approvalsByProfileId[profileId] ?? []
    }

    func isLoading(_ profileId: String) -> Bool {
        loadingProfileIds.contains(profileId)
    }

    func refreshTasks(for profile: AgentProfile) {
        clearExpiredRequests()
        guard canSendTaskRequest(for: profile) else {
            setError("请先配对 Agent", profileId: profile.id)
            return
        }
        let requestId = makeRequestId("task-list")
        pending[requestId] = PendingRequest(
            profileId: profile.id,
            kind: .list,
            deadline: Date().addingTimeInterval(timeoutInterval)
        )
        loadingProfileIds.insert(profile.id)
        errorsByProfileId[profile.id] = nil
        if wsManager?.requestTaskList(requestId: requestId, backendId: profile.backendId, includeDisabled: true) != true {
            finishRequest(requestId)
            setError("任务请求发送失败", profileId: profile.id)
        }
    }

    func refreshApprovals(for profile: AgentProfile) {
        clearExpiredRequests()
        guard canSendTaskRequest(for: profile) else { return }
        let requestId = makeRequestId("approval-list")
        pending[requestId] = PendingRequest(
            profileId: profile.id,
            kind: .approvals,
            deadline: Date().addingTimeInterval(timeoutInterval)
        )
        _ = wsManager?.requestApprovalHistory(requestId: requestId, backendId: profile.backendId, limit: 50)
    }

    func createTask(
        for profile: AgentProfile,
        title: String,
        prompt: String,
        schedule: String?,
        enabled: Bool
    ) {
        clearExpiredRequests()
        guard canSendTaskRequest(for: profile) else {
            setError("请先配对 Agent", profileId: profile.id)
            return
        }
        let requestId = makeRequestId("task-create")
        pending[requestId] = PendingRequest(
            profileId: profile.id,
            kind: .create,
            deadline: Date().addingTimeInterval(timeoutInterval)
        )
        operationMessagesByProfileId[profile.id] = nil
        if wsManager?.createAgentTask(
            requestId: requestId,
            backendId: profile.backendId,
            title: title,
            prompt: prompt,
            schedule: schedule,
            enabled: enabled
        ) != true {
            finishRequest(requestId)
            setError("新增任务请求发送失败", profileId: profile.id)
        }
    }

    func updateTask(
        for profile: AgentProfile,
        task: AgentTaskItem,
        title: String,
        prompt: String,
        schedule: String,
        enabled: Bool
    ) {
        clearExpiredRequests()
        guard canSendTaskRequest(for: profile) else {
            setError("请先配对 Agent", profileId: profile.id)
            return
        }
        let requestId = makeRequestId("task-update")
        pending[requestId] = PendingRequest(
            profileId: profile.id,
            kind: .update,
            deadline: Date().addingTimeInterval(timeoutInterval)
        )
        if wsManager?.updateAgentTask(
            requestId: requestId,
            backendId: profile.backendId,
            taskId: task.taskId,
            title: title,
            prompt: prompt,
            schedule: schedule,
            enabled: enabled
        ) != true {
            finishRequest(requestId)
            setError("保存任务请求发送失败", profileId: profile.id)
        }
    }

    func deleteTask(for profile: AgentProfile, task: AgentTaskItem) {
        clearExpiredRequests()
        guard canSendTaskRequest(for: profile) else {
            setError("请先配对 Agent", profileId: profile.id)
            return
        }
        let requestId = makeRequestId("task-delete")
        pending[requestId] = PendingRequest(
            profileId: profile.id,
            kind: .delete,
            deadline: Date().addingTimeInterval(timeoutInterval)
        )
        if wsManager?.deleteAgentTask(requestId: requestId, backendId: profile.backendId, taskId: task.taskId) != true {
            finishRequest(requestId)
            setError("删除任务请求发送失败", profileId: profile.id)
        }
    }

    private func handle(_ event: WsMessageEvent) {
        clearExpiredRequests()
        switch event {
        case .taskListResponse(let payload):
            handleTaskListResponse(payload)
        case .taskCreateResponse(let payload):
            handleTaskMutationResponse(payload)
        case .taskUpdateResponse(let payload):
            handleTaskMutationResponse(payload)
        case .taskDeleteResponse(let payload):
            handleTaskDeleteResponse(payload)
        case .approvalHistoryResponse(let payload):
            handleApprovalHistoryResponse(payload)
        default:
            break
        }
    }

    private func handleTaskListResponse(_ payload: TaskListResponsePayload) {
        let request = pending[payload.requestId]
        let profileId = request?.profileId ?? profileId(forBackendId: payload.backendId)
        guard let profileId else { return }
        finishRequest(payload.requestId)
        loadingProfileIds.remove(profileId)

        if let error = payload.error, !error.isEmpty {
            setError(error, profileId: profileId)
            return
        }

        tasksByProfileId[profileId] = payload.tasks.sortedForTaskList()
        capabilityByProfileId[profileId] = payload.capability
        errorsByProfileId[profileId] = nil
        persistCache()
    }

    private func handleTaskMutationResponse(_ payload: TaskMutationResponsePayload) {
        let request = pending[payload.requestId]
        let profileId = request?.profileId ?? profileId(forBackendId: payload.backendId)
        guard let profileId else { return }
        finishRequest(payload.requestId)

        if let error = payload.error, !error.isEmpty {
            setError(error, profileId: profileId)
            return
        }

        if let task = payload.task {
            upsert(task, profileId: profileId)
        }
        if let message = payload.message, !message.isEmpty {
            operationMessagesByProfileId[profileId] = message
        } else if payload.requiresAgentConfirmation {
            operationMessagesByProfileId[profileId] = "已发送给 Agent，请在对话中确认频率或执行时间。"
        }
        errorsByProfileId[profileId] = nil
        persistCache()
    }

    private func handleTaskDeleteResponse(_ payload: TaskMutationResponsePayload) {
        let request = pending[payload.requestId]
        let profileId = request?.profileId ?? profileId(forBackendId: payload.backendId)
        guard let profileId else { return }
        finishRequest(payload.requestId)

        if let error = payload.error, !error.isEmpty {
            setError(error, profileId: profileId)
            return
        }

        if payload.deleted, let taskId = payload.taskId {
            tasksByProfileId[profileId] = (tasksByProfileId[profileId] ?? []).filter { $0.taskId != taskId }
            persistCache()
        }
        if let message = payload.message, !message.isEmpty {
            operationMessagesByProfileId[profileId] = message
        }
    }

    private func handleApprovalHistoryResponse(_ payload: ApprovalHistoryResponsePayload) {
        let request = pending[payload.requestId]
        let profileId = request?.profileId ?? profileId(forBackendId: payload.backendId)
        guard let profileId else { return }
        finishRequest(payload.requestId)

        if let error = payload.error, !error.isEmpty {
            setError(error, profileId: profileId)
            return
        }

        approvalsByProfileId[profileId] = payload.approvals.map { item in
            ApprovalHistoryItem(
                id: item.approvalId,
                agentId: profileId,
                title: item.title,
                command: item.command,
                decision: item.decision,
                createdAt: HistoryMessagePayload.date(from: item.createdAt) ?? Date()
            )
        }
    }

    private func upsert(_ task: AgentTaskItem, profileId: String) {
        var tasks = tasksByProfileId[profileId] ?? []
        if let index = tasks.firstIndex(where: { $0.taskId == task.taskId }) {
            tasks[index] = task
        } else {
            tasks.insert(task, at: 0)
        }
        tasksByProfileId[profileId] = tasks.sortedForTaskList()
    }

    private func setError(_ error: String, profileId: String) {
        loadingProfileIds.remove(profileId)
        errorsByProfileId[profileId] = error
    }

    private func finishRequest(_ requestId: String) {
        if let profileId = pending[requestId]?.profileId {
            loadingProfileIds.remove(profileId)
        }
        pending.removeValue(forKey: requestId)
    }

    private func clearExpiredRequests(now: Date = Date()) {
        let expired = pending.filter { $0.value.deadline <= now }
        for (requestId, request) in expired {
            pending.removeValue(forKey: requestId)
            setError("请求超时，请稍后重试", profileId: request.profileId)
        }
    }

    private func canSendTaskRequest(for profile: AgentProfile) -> Bool {
        profile.isPaired && !profile.backendId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func profileId(forBackendId backendId: String) -> String? {
        tasksByProfileId.first { _, tasks in
            tasks.contains { $0.backendId == backendId }
        }?.key
    }

    private func makeRequestId(_ prefix: String) -> String {
        "\(prefix)-\(UUID().uuidString)"
    }

    private func persistCache() {
        let cache = AgentTaskCache(tasksByProfileId: tasksByProfileId)
        if let data = try? JSONEncoder().encode(cache) {
            defaults.set(data, forKey: cacheKey)
        }
    }

    private static func loadCache(from defaults: UserDefaults, key: String) -> AgentTaskCache {
        guard let data = defaults.data(forKey: key),
              let cache = try? JSONDecoder().decode(AgentTaskCache.self, from: data) else {
            return AgentTaskCache(tasksByProfileId: [:])
        }
        return cache
    }
}

private struct AgentTaskCache: Codable {
    var tasksByProfileId: [String: [AgentTaskItem]]
}

extension Array where Element == AgentTaskItem {
    func sortedForTaskList() -> [AgentTaskItem] {
        sorted { lhs, rhs in
            if lhs.enabled != rhs.enabled { return lhs.enabled && !rhs.enabled }
            let lhsTime = lhs.updatedAt ?? lhs.nextRunAt ?? ""
            let rhsTime = rhs.updatedAt ?? rhs.nextRunAt ?? ""
            if lhsTime != rhsTime { return lhsTime > rhsTime }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }
}
