import Foundation
import Combine

protocol AgentTaskRequestClient: AnyObject {
    var messageChannel: AnyPublisher<WsMessageEvent, Never> { get }

    func requestTaskList(requestId: String, backendId: String, includeDisabled: Bool) -> Bool
    func createAgentTask(
        requestId: String,
        backendId: String,
        title: String,
        prompt: String,
        schedule: String?,
        enabled: Bool
    ) -> Bool
    func updateAgentTask(
        requestId: String,
        backendId: String,
        taskId: String,
        title: String,
        prompt: String,
        schedule: String,
        enabled: Bool
    ) -> Bool
    func deleteAgentTask(requestId: String, backendId: String, taskId: String) -> Bool
    func requestApprovalHistory(requestId: String, backendId: String, limit: Int) -> Bool
}

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
    private let timeoutScheduler: (TimeInterval, @escaping () -> Void) -> AnyCancellable
    private var cancellable: AnyCancellable?
    private weak var requestClient: AgentTaskRequestClient?
    private var pending: [String: PendingRequest] = [:]
    private var timeoutCancellables: [String: AnyCancellable] = [:]

    @Published private(set) var tasksByProfileId: [String: [AgentTaskItem]]
    @Published private(set) var approvalsByProfileId: [String: [ApprovalHistoryItem]]
    @Published private(set) var loadingProfileIds: Set<String> = []
    @Published private(set) var errorsByProfileId: [String: String] = [:]
    @Published private(set) var capabilityByProfileId: [String: String] = [:]
    @Published private(set) var operationMessagesByProfileId: [String: String] = [:]

    init(
        defaults: UserDefaults = .standard,
        timeoutInterval: TimeInterval = 12,
        timeoutScheduler: @escaping (TimeInterval, @escaping () -> Void) -> AnyCancellable = AgentTaskService.defaultTimeoutScheduler
    ) {
        self.defaults = defaults
        self.timeoutInterval = timeoutInterval
        self.timeoutScheduler = timeoutScheduler
        let cache = Self.loadCache(from: defaults, key: cacheKey)
        self.tasksByProfileId = cache.tasksByProfileId
        self.approvalsByProfileId = [:]
    }

    func bind(to client: AgentTaskRequestClient) {
        self.requestClient = client
        cancellable = client.messageChannel
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
        trackRequest(requestId, profileId: profile.id, kind: .list)
        errorsByProfileId[profile.id] = nil
        if requestClient?.requestTaskList(requestId: requestId, backendId: profile.backendId, includeDisabled: true) != true {
            finishRequest(requestId)
            setError("任务请求发送失败", profileId: profile.id)
        }
    }

    func refreshApprovals(for profile: AgentProfile) {
        clearExpiredRequests()
        guard canSendTaskRequest(for: profile) else { return }
        let requestId = makeRequestId("approval-list")
        trackRequest(requestId, profileId: profile.id, kind: .approvals)
        if requestClient?.requestApprovalHistory(requestId: requestId, backendId: profile.backendId, limit: 50) != true {
            finishRequest(requestId)
        }
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
        trackRequest(requestId, profileId: profile.id, kind: .create)
        operationMessagesByProfileId[profile.id] = nil
        if requestClient?.createAgentTask(
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
        trackRequest(requestId, profileId: profile.id, kind: .update)
        if requestClient?.updateAgentTask(
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
        trackRequest(requestId, profileId: profile.id, kind: .delete)
        if requestClient?.deleteAgentTask(requestId: requestId, backendId: profile.backendId, taskId: task.taskId) != true {
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
        case .error(_, let message):
            handleRouterError(message: message)
        default:
            break
        }
    }

    private func handleTaskListResponse(_ payload: TaskListResponsePayload) {
        let request = pending[payload.requestId]
        let profileId = request?.profileId ?? profileId(forBackendId: payload.backendId)
        guard let profileId else { return }
        finishRequest(payload.requestId)

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

    private func trackRequest(_ requestId: String, profileId: String, kind: RequestKind) {
        pending[requestId] = PendingRequest(
            profileId: profileId,
            kind: kind,
            deadline: Date().addingTimeInterval(timeoutInterval)
        )
        timeoutCancellables[requestId]?.cancel()
        timeoutCancellables[requestId] = timeoutScheduler(timeoutInterval) { [weak self] in
            self?.expireRequest(requestId)
        }
        refreshLoadingState(profileId: profileId)
    }

    private func finishRequest(_ requestId: String) {
        let request = pending.removeValue(forKey: requestId)
        timeoutCancellables.removeValue(forKey: requestId)?.cancel()
        if let profileId = request?.profileId {
            refreshLoadingState(profileId: profileId)
        }
    }

    private func clearExpiredRequests(now: Date = Date()) {
        let expired = pending.filter { $0.value.deadline <= now }
        for requestId in expired.keys {
            expireRequest(requestId)
        }
    }

    private func expireRequest(_ requestId: String) {
        guard let request = pending[requestId] else { return }
        finishRequest(requestId)
        setError("请求超时，请稍后重试", profileId: request.profileId)
    }

    private func handleRouterError(message: String) {
        let requestIds = Array(pending.keys)
        for requestId in requestIds {
            guard let request = pending[requestId] else { continue }
            finishRequest(requestId)
            switch request.kind {
            case .list, .create, .update, .delete:
                setError(message, profileId: request.profileId)
            case .approvals:
                break
            }
        }
    }

    private func refreshLoadingState(profileId: String) {
        let hasPendingTaskList = pending.values.contains { request in
            request.profileId == profileId && request.kind == .list
        }
        if hasPendingTaskList {
            loadingProfileIds.insert(profileId)
        } else {
            loadingProfileIds.remove(profileId)
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

    private static func defaultTimeoutScheduler(_ interval: TimeInterval, _ action: @escaping () -> Void) -> AnyCancellable {
        let workItem = DispatchWorkItem(block: action)
        DispatchQueue.main.asyncAfter(deadline: .now() + interval, execute: workItem)
        return AnyCancellable {
            workItem.cancel()
        }
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
