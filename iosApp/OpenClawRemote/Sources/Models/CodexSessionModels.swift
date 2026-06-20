import Foundation

struct CodexSessionSummary: Identifiable, Codable, Equatable {
    var sessionId: String
    var title: String
    var preview: String
    var lastAssistantPreview: String
    var projectPath: String
    var projectName: String?
    var createdAt: String
    var updatedAt: String
    var status: String
    var archived: Bool
    var model: String?

    var id: String { sessionId }

    var displayTitle: String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedTitle.isEmpty ? "未命名会话" : trimmedTitle
    }

    var displayPreview: String {
        let assistant = lastAssistantPreview.trimmingCharacters(in: .whitespacesAndNewlines)
        if !assistant.isEmpty { return assistant }
        let fallback = preview.trimmingCharacters(in: .whitespacesAndNewlines)
        return fallback.isEmpty ? "暂无回复" : fallback
    }

    var displayProjectName: String {
        let explicit = (projectName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !explicit.isEmpty { return explicit }
        let path = projectPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return "聊天" }
        let lastSegment = URL(fileURLWithPath: path).lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return lastSegment.isEmpty ? "聊天" : lastSegment
    }

    var updatedDate: Date {
        Self.date(from: updatedAt) ?? Self.date(from: createdAt) ?? .distantPast
    }

    init(
        sessionId: String,
        title: String,
        preview: String,
        lastAssistantPreview: String,
        projectPath: String,
        projectName: String?,
        createdAt: String,
        updatedAt: String,
        status: String,
        archived: Bool,
        model: String?
    ) {
        self.sessionId = sessionId
        self.title = title
        self.preview = preview
        self.lastAssistantPreview = lastAssistantPreview
        self.projectPath = projectPath
        self.projectName = projectName
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.status = status
        self.archived = archived
        self.model = model
    }

    init?(json: [String: Any]) {
        guard let sessionId = Self.string(json["session_id"]), !sessionId.isEmpty else {
            return nil
        }
        self.init(
            sessionId: sessionId,
            title: Self.string(json["title"]) ?? "",
            preview: Self.string(json["preview"]) ?? "",
            lastAssistantPreview: Self.string(json["last_assistant_preview"]) ?? "",
            projectPath: Self.string(json["project_path"]) ?? "",
            projectName: Self.string(json["project_name"]),
            createdAt: Self.string(json["created_at"]) ?? "",
            updatedAt: Self.string(json["updated_at"]) ?? "",
            status: Self.string(json["status"]) ?? "",
            archived: Self.bool(json["archived"]),
            model: Self.string(json["model"])
        )
    }

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case title
        case preview
        case lastAssistantPreview = "last_assistant_preview"
        case projectPath = "project_path"
        case projectName = "project_name"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case status
        case archived
        case model
    }

    static func date(from value: String) -> Date? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: trimmed) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: trimmed)
    }

    private static func string(_ value: Any?) -> String? {
        if let value = value as? String { return value }
        if let value = value as? NSNumber { return value.stringValue }
        return nil
    }

    private static func bool(_ value: Any?) -> Bool {
        if let value = value as? Bool { return value }
        if let value = value as? NSNumber { return value.boolValue }
        if let value = value as? String {
            return ["1", "true", "yes"].contains(value.lowercased())
        }
        return false
    }
}

enum CodexSessionGroupingMode: String, Codable, CaseIterable, Identifiable {
    case time
    case project

    var id: String { rawValue }
}

struct CodexSessionGroup: Identifiable, Equatable {
    var id: String { title }
    let title: String
    let sessions: [CodexSessionSummary]
}

enum CodexSessionGrouping {
    static func groups(
        for sessions: [CodexSessionSummary],
        mode: CodexSessionGroupingMode,
        now: Date = Date()
    ) -> [CodexSessionGroup] {
        let sorted = sessions.sorted { lhs, rhs in
            lhs.updatedDate > rhs.updatedDate
        }
        switch mode {
        case .time:
            return timeGroups(for: sorted, now: now)
        case .project:
            return projectGroups(for: sorted)
        }
    }

    private static func timeGroups(
        for sessions: [CodexSessionSummary],
        now: Date
    ) -> [CodexSessionGroup] {
        let titles = sessions.map { title(for: $0.updatedDate, now: now) }
        let orderedTitles = titles.reduce(into: [String]()) { result, title in
            if !result.contains(title) {
                result.append(title)
            }
        }
        return orderedTitles.map { title in
            CodexSessionGroup(
                title: title,
                sessions: sessions.enumerated().compactMap { index, session in
                    titles[index] == title ? session : nil
                }
            )
        }
    }

    private static func projectGroups(for sessions: [CodexSessionSummary]) -> [CodexSessionGroup] {
        let grouped = Dictionary(grouping: sessions, by: \.displayProjectName)
        return grouped
            .map { title, sessions in
                CodexSessionGroup(title: title, sessions: sessions.sorted { $0.updatedDate > $1.updatedDate })
            }
            .sorted { lhs, rhs in
                let lhsDate = lhs.sessions.first?.updatedDate ?? .distantPast
                let rhsDate = rhs.sessions.first?.updatedDate ?? .distantPast
                if lhsDate == rhsDate {
                    return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
                }
                return lhsDate > rhsDate
            }
    }

    private static func title(for date: Date, now: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let startOfNow = calendar.startOfDay(for: now)
        let startOfDate = calendar.startOfDay(for: date)
        let dayDiff = max(0, calendar.dateComponents([.day], from: startOfDate, to: startOfNow).day ?? 0)
        switch dayDiff {
        case 0:
            return "今天"
        case 1:
            return "昨天"
        case 2...6:
            return "\(dayDiff)天前"
        case 7...13:
            return "上周"
        case 14...30:
            return "\(dayDiff / 7)周前"
        default:
            return "上个月"
        }
    }
}
