import Foundation

struct ApprovalRequest: Equatable, Identifiable {
    let title: String
    let command: String
    let reason: String
    let codeLines: [String]

    var id: String {
        "\(title)|\(command)|\(reason)"
    }

    var lineCount: Int {
        codeLines.count
    }

    var commandPreview: String {
        codeLines.prefix(4).joined(separator: "\n")
    }

    static func detect(in content: String) -> ApprovalRequest? {
        let lowercased = content.lowercased()
        guard lowercased.contains("/approve"),
              lowercased.contains("/deny"),
              containsApprovalCue(in: lowercased) else {
            return nil
        }
        let command = extractCommand(from: content)
        let lines = command.isEmpty ? [] : command.components(separatedBy: .newlines)
        return ApprovalRequest(
            title: "危险命令审批",
            command: command,
            reason: extractReason(from: content),
            codeLines: lines
        )
    }

    private static func containsApprovalCue(in lowercasedContent: String) -> Bool {
        [
            "dangerous command requires approval",
            "requires approval",
            "approval required",
            "needs approval",
            "需要审批",
            "需要批准",
            "需要确认",
            "需要授权",
            "危险命令",
            "审批",
            "批准",
            "拒绝",
        ].contains { lowercasedContent.contains($0) }
    }

    private static func extractCommand(from content: String) -> String {
        if let fenced = extractFencedCodeBlock(from: content) {
            return fenced
        }

        let lines = content.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if let labeled = commandAfterLabel(in: trimmed) {
                return labeled
            }
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard looksLikeCommandLine(trimmed) else { continue }
            return trimmed
        }

        return ""
    }

    private static func extractFencedCodeBlock(from content: String) -> String? {
        let lines = content.components(separatedBy: .newlines)
        var collecting = false
        var collected: [String] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                if collecting {
                    let value = collected.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                    return value.isEmpty ? nil : value
                }
                collecting = true
                collected.removeAll()
                continue
            }
            if collecting {
                collected.append(line)
            }
        }

        return nil
    }

    private static func commandAfterLabel(in line: String) -> String? {
        let labels = ["命令：", "命令:", "Command:", "command:", "Terminal:", "terminal:"]
        for label in labels where line.hasPrefix(label) {
            let value = String(line.dropFirst(label.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            let unquoted = stripWrappingQuotes(value)
            return unquoted.isEmpty ? nil : unquoted
        }
        return nil
    }

    private static func stripWrappingQuotes(_ value: String) -> String {
        guard value.count >= 2,
              let first = value.first,
              let last = value.last,
              (first == "\"" && last == "\"") || (first == "'" && last == "'") else {
            return value
        }
        return String(value.dropFirst().dropLast())
    }

    private static func looksLikeCommandLine(_ line: String) -> Bool {
        let lowercased = line.lowercased()
        guard !isActionLine(lowercased),
              !lowercased.hasPrefix("reason:"),
              !lowercased.hasPrefix("原因："),
              !lowercased.hasPrefix("原因:") else {
            return false
        }

        let prefixes = [
            "curl ", "wget ", "rm ", "sudo ", "python ", "python3 ", "node ", "npm ", "pnpm ",
            "yarn ", "git ", "docker ", "kubectl ", "ssh ", "scp ", "brew ", "chmod ", "chown ",
            "mv ", "cp ", "cat ", "bash ", "sh ", "cd ", "echo "
        ]
        return prefixes.contains { lowercased.hasPrefix($0) }
    }

    private static func extractReason(from content: String) -> String {
        let lines = content.components(separatedBy: .newlines)
        var collected: [String] = []
        var collecting = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            let lowercased = trimmed.lowercased()

            if collecting {
                if trimmed.isEmpty {
                    if collected.isEmpty {
                        continue
                    }
                    break
                }
                if isActionLine(lowercased) || lowercased.hasPrefix("```") {
                    break
                }
                collected.append(trimmed)
                continue
            }

            if let reason = reasonAfterLabel(in: trimmed) {
                if !reason.isEmpty {
                    collected.append(reason)
                }
                collecting = true
            }
        }

        return collected.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func reasonAfterLabel(in line: String) -> String? {
        let labels = ["Reason:", "reason:", "原因：", "原因:", "理由：", "理由:"]
        for label in labels where line.hasPrefix(label) {
            return String(line.dropFirst(label.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    private static func isActionLine(_ lowercasedLine: String) -> Bool {
        lowercasedLine.hasPrefix("/approve") || lowercasedLine.hasPrefix("/deny")
    }
}

struct ApprovalHandledUpdate: Equatable {
    let allowed: Bool
    let handledIds: Set<UUID>
}

func markApprovalHandledIfAllowed(
    handledIds: Set<UUID>,
    messageId: UUID
) -> ApprovalHandledUpdate {
    if handledIds.contains(messageId) {
        return ApprovalHandledUpdate(allowed: false, handledIds: handledIds)
    }
    return ApprovalHandledUpdate(allowed: true, handledIds: handledIds.union([messageId]))
}
