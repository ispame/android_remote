import SwiftUI

struct MessageBubbleView: View {
    let message: ChatMessage
    let colors: MochiColors
    let isSelectionMode: Bool
    let isSelected: Bool
    let onTap: () -> Void
    let onCopy: () -> Void
    let onQuote: () -> Void
    let onSelect: () -> Void
    let onApprovalCommand: (String) -> Void

    private var usesWideLayout: Bool {
        !message.isUser && message.content.prefersWideMessageLayout
    }

    private var approvalRequest: ApprovalRequest? {
        message.isUser ? nil : ApprovalRequest.detect(in: message.content)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if isSelectionMode {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(isSelected ? colors.primary : colors.textSecondary)
                    .frame(width: 28)
            }

            if message.isUser {
                Spacer(minLength: 0)
            }

            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 3) {
                CollapsibleMessageContent(
                    text: message.content,
                    textColor: message.isUser ? colors.userBubbleFg : colors.assistantFg,
                    colors: colors
                )
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedCornerShape(
                            topLeft: message.isUser ? 16 : 4,
                            topRight: message.isUser ? 4 : 16,
                            bottomLeft: 16,
                            bottomRight: 16
                        )
                        .fill(message.isUser ? colors.userBubble : colors.assistantBg)
                    )
                    .frame(
                        maxWidth: UIScreen.main.bounds.width * (usesWideLayout ? 0.94 : 0.82),
                        alignment: message.isUser ? .trailing : .leading
                    )

                Text(message.timestamp)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(colors.textSecondary)

                if let approvalRequest {
                    ApprovalActionsView(
                        request: approvalRequest,
                        colors: colors,
                        onCommand: onApprovalCommand
                    )
                    .frame(maxWidth: UIScreen.main.bounds.width * 0.82, alignment: .leading)
                }
            }

            if !message.isUser {
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .contextMenu {
            Button(action: onCopy) {
                Label("复制", systemImage: "doc.on.doc")
            }
            Button(action: onQuote) {
                Label("引用", systemImage: "quote.bubble")
            }
            Button(action: onSelect) {
                Label("选择", systemImage: "checkmark.circle")
            }
        }
    }
}

struct ApprovalRequest: Equatable {
    let title: String

    static func detect(in content: String) -> ApprovalRequest? {
        let lowercased = content.lowercased()
        guard lowercased.contains("dangerous command requires approval"),
              lowercased.contains("/approve"),
              lowercased.contains("/deny") else {
            return nil
        }
        return ApprovalRequest(title: "危险命令审批")
    }
}

private struct ApprovalActionsView: View {
    let request: ApprovalRequest
    let colors: MochiColors
    let onCommand: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(request.title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(colors.textSecondary)

            HStack(spacing: 8) {
                ApprovalCommandButton(
                    title: "批准",
                    systemImage: "checkmark",
                    foreground: colors.onPrimary,
                    background: colors.primary,
                    command: "/approve",
                    onCommand: onCommand
                )

                ApprovalCommandButton(
                    title: "本会话",
                    systemImage: "checkmark.shield",
                    foreground: colors.textPrimary,
                    background: colors.inputBg,
                    command: "/approve session",
                    onCommand: onCommand
                )

                ApprovalCommandButton(
                    title: "永久",
                    systemImage: "checkmark.seal",
                    foreground: colors.textPrimary,
                    background: colors.inputBg,
                    command: "/approve always",
                    onCommand: onCommand
                )

                ApprovalCommandButton(
                    title: "拒绝",
                    systemImage: "xmark",
                    foreground: colors.recordingRed,
                    background: colors.recordingRed.opacity(0.12),
                    command: "/deny",
                    onCommand: onCommand
                )
            }
        }
        .padding(10)
        .background(colors.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(colors.divider, lineWidth: 1)
        )
        .cornerRadius(8)
    }
}

private struct ApprovalCommandButton: View {
    let title: String
    let systemImage: String
    let foreground: Color
    let background: Color
    let command: String
    let onCommand: (String) -> Void

    var body: some View {
        Button {
            onCommand(command)
        } label: {
            Label(title, systemImage: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(foreground)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .padding(.horizontal, 9)
                .padding(.vertical, 7)
                .background(background)
                .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

private extension String {
    var prefersWideMessageLayout: Bool {
        contains("```") || parseBlocks(self).contains { block in
            if case .table = block { return true }
            return false
        }
    }
}

struct CollapsibleMessageContent: View {
    let text: String
    let textColor: Color
    let colors: MochiColors

    @State private var isExpanded = false

    private var quotedContent: ParsedQuotedMessage? {
        parseLeadingQuotedMessage(text)
    }

    private var bodyText: String {
        quotedContent?.body ?? text
    }

    private var analysis: MessageContentAnalysis {
        analyzeMessageContent(bodyText)
    }

    private var shouldShowToggle: Bool {
        analysis.kind != .normal
    }

    private var displayText: String {
        if isExpanded { return bodyText }
        switch analysis.kind {
        case .normal:
            return bodyText
        case .longText:
            return analysis.preview
        case .denseEncoded:
            return "疑似文件、音频或二进制内容，已折叠显示。"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let quotedContent {
                EmbeddedQuoteView(
                    summary: quotedContent.quote,
                    colors: colors,
                    textColor: textColor
                )
            }

            MarkdownMessageBody(
                text: displayText,
                textColor: textColor,
                colors: colors
            )

            if shouldShowToggle {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        isExpanded.toggle()
                    }
                }) {
                    HStack(spacing: 4) {
                        Text(isExpanded ? "收起" : toggleTitle)
                            .font(.system(size: 12, weight: .medium))
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(textColor.opacity(0.78))
                    .padding(.top, 2)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isExpanded ? "收起消息" : "展开全文")
            }
        }
    }

    private var toggleTitle: String {
        switch analysis.kind {
        case .denseEncoded:
            return "查看内容"
        case .longText:
            return "展开全文"
        case .normal:
            return ""
        }
    }
}

struct ParsedQuotedMessage {
    let quote: String
    let body: String
}

func parseLeadingQuotedMessage(_ text: String) -> ParsedQuotedMessage? {
    let lines = text.components(separatedBy: .newlines)
    guard let firstLine = lines.first,
          firstLine.trimmingCharacters(in: .whitespaces).hasPrefix(">") else {
        return nil
    }

    var quoteLines: [String] = []
    var index = 0
    while index < lines.count {
        let line = lines[index]
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix(">") else { break }
        var value = trimmed
        value.removeFirst()
        quoteLines.append(value.trimmingCharacters(in: .whitespaces))
        index += 1
    }

    while index < lines.count && lines[index].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        index += 1
    }

    let quote = quoteLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    let body = lines.dropFirst(index).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    guard !quote.isEmpty, !body.isEmpty else { return nil }
    return ParsedQuotedMessage(quote: quote, body: body)
}

private struct EmbeddedQuoteView: View {
    let summary: String
    let colors: MochiColors
    let textColor: Color

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(textColor.opacity(0.45))
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 2) {
                Text("引用")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(textColor.opacity(0.68))
                Text(summary)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(textColor.opacity(0.74))
                    .lineLimit(3)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(colors.surface.opacity(0.28))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

enum MessageContentKind {
    case normal
    case longText
    case denseEncoded
}

struct MessageContentAnalysis {
    let kind: MessageContentKind
    let preview: String
}

private let collapsedLineLimit = 8
private let collapsedCharacterLimit = 650
private let denseContinuousCharacterLimit = 900

func analyzeMessageContent(_ text: String) -> MessageContentAnalysis {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if looksLikeDenseEncodedContent(trimmed) {
        return MessageContentAnalysis(kind: .denseEncoded, preview: "")
    }

    let lines = text.components(separatedBy: .newlines)
    if lines.count > collapsedLineLimit || text.count > collapsedCharacterLimit {
        return MessageContentAnalysis(kind: .longText, preview: collapsedPreview(for: text))
    }

    return MessageContentAnalysis(kind: .normal, preview: text)
}

func collapsedPreview(for text: String) -> String {
    let lines = text.components(separatedBy: .newlines)
    var preview = lines.prefix(collapsedLineLimit).joined(separator: "\n")

    if preview.count > collapsedCharacterLimit {
        let endIndex = preview.index(preview.startIndex, offsetBy: collapsedCharacterLimit)
        preview = String(preview[..<endIndex])
    }

    return preview.trimmingCharacters(in: .whitespacesAndNewlines) + "\n..."
}

func looksLikeDenseEncodedContent(_ text: String) -> Bool {
    guard text.count >= denseContinuousCharacterLimit else { return false }

    let compact = text.filter { !$0.isWhitespace && !$0.isNewline }
    guard compact.count >= denseContinuousCharacterLimit else { return false }

    let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=_-")
    let encodedCount = compact.unicodeScalars.filter { allowed.contains($0) }.count
    let ratio = Double(encodedCount) / Double(compact.count)
    let hasLongUnbrokenRun = text
        .components(separatedBy: .whitespacesAndNewlines)
        .contains { $0.count >= denseContinuousCharacterLimit }

    return ratio > 0.94 && hasLongUnbrokenRun
}

struct MarkdownMessageBody: View {
    let text: String
    let textColor: Color
    let colors: MochiColors

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(parseBlocks(text).enumerated()), id: \.offset) { _, block in
                switch block {
                case .text(let value):
                    if !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        MarkdownText(text: value, textColor: textColor, font: .system(size: 15))
                    }
                case .table(let table):
                    MarkdownTableView(table: table, colors: colors, textColor: textColor)
                }
            }
        }
    }
}

struct MarkdownText: View {
    let text: String
    let textColor: Color
    let font: Font

    var body: some View {
        if let attributed = try? AttributedString(markdown: text) {
            Text(attributed)
                .font(font)
                .foregroundColor(textColor)
                .lineSpacing(7)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(text)
                .font(font)
                .foregroundColor(textColor)
                .lineSpacing(7)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct MarkdownTable {
    let headers: [String]
    let rows: [[String]]
}

struct MarkdownTableView: View {
    let table: MarkdownTable
    let colors: MochiColors
    let textColor: Color

    var body: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 0) {
                tableRow(table.headers, isHeader: true)
                ForEach(Array(table.rows.enumerated()), id: \.offset) { _, row in
                    tableRow(row, isHeader: false)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(colors.divider.opacity(0.8), lineWidth: 1)
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tableRow(_ cells: [String], isHeader: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                MarkdownText(
                    text: cell.isEmpty ? " " : cell,
                    textColor: textColor,
                    font: .system(size: 13, weight: isHeader ? .semibold : .regular)
                )
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(minWidth: 86, maxWidth: 180, alignment: .leading)
                    .background(isHeader ? colors.surface.opacity(0.45) : Color.clear)
                    .border(colors.divider.opacity(0.65), width: 0.5)
            }
        }
    }
}

enum MarkdownBlock {
    case text(String)
    case table(MarkdownTable)
}

func parseBlocks(_ text: String) -> [MarkdownBlock] {
    let lines = text.components(separatedBy: .newlines)
    var blocks: [MarkdownBlock] = []
    var buffer: [String] = []
    var index = 0

    func flushText() {
        if !buffer.isEmpty {
            blocks.append(.text(buffer.joined(separator: "\n")))
            buffer.removeAll()
        }
    }

    while index < lines.count {
        if index + 1 < lines.count,
           let table = parseTable(lines: lines, start: index) {
            flushText()
            blocks.append(.table(table.value))
            index = table.nextIndex
        } else {
            buffer.append(lines[index])
            index += 1
        }
    }
    flushText()
    return blocks
}

func parseTable(lines: [String], start: Int) -> (value: MarkdownTable, nextIndex: Int)? {
    guard start + 1 < lines.count else { return nil }
    let header = splitTableRow(lines[start])
    guard header.count >= 2, isSeparatorRow(lines[start + 1]) else { return nil }

    var rows: [[String]] = []
    var index = start + 2
    while index < lines.count {
        let row = splitTableRow(lines[index])
        if row.count < 2 { break }
        rows.append(normalizeRow(row, width: header.count))
        index += 1
    }

    return (MarkdownTable(headers: header, rows: rows), index)
}

func splitTableRow(_ line: String) -> [String] {
    var trimmed = line.trimmingCharacters(in: .whitespaces)
    guard trimmed.contains("|") else { return [] }
    if trimmed.hasPrefix("|") { trimmed.removeFirst() }
    if trimmed.hasSuffix("|") { trimmed.removeLast() }
    return trimmed.split(separator: "|", omittingEmptySubsequences: false)
        .map { String($0).trimmingCharacters(in: .whitespaces) }
}

func isSeparatorRow(_ line: String) -> Bool {
    let cells = splitTableRow(line)
    guard cells.count >= 2 else { return false }
    return cells.allSatisfy { cell in
        let stripped = cell.replacingOccurrences(of: ":", with: "")
        return stripped.count >= 3 && stripped.allSatisfy { $0 == "-" }
    }
}

func normalizeRow(_ row: [String], width: Int) -> [String] {
    if row.count == width { return row }
    if row.count > width { return Array(row.prefix(width)) }
    return row + Array(repeating: "", count: width - row.count)
}

struct AvatarChip: View {
    let label: String
    let bgColor: Color
    let textColor: Color

    var body: some View {
        Text(label)
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(textColor)
            .frame(width: 32, height: 32)
            .background(bgColor)
            .clipShape(Circle())
    }
}

struct RoundedCornerShape: Shape {
    var topLeft: CGFloat = 0
    var topRight: CGFloat = 0
    var bottomLeft: CGFloat = 0
    var bottomRight: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + topLeft, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - topRight, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + topRight), control: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - bottomRight))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - bottomRight, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + bottomLeft, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - bottomLeft), control: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + topLeft))
        path.addQuadCurve(to: CGPoint(x: rect.minX + topLeft, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}
