import SwiftUI

struct MessageBubbleView: View {
    let message: ChatMessage
    let colors: MochiColors

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if !message.isUser {
                AvatarChip(label: "M", bgColor: colors.secondary, textColor: colors.onSecondary)
            } else {
                Spacer(minLength: 44)
            }

            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 3) {
                MarkdownMessageBody(
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
                    .frame(maxWidth: UIScreen.main.bounds.width * 0.74, alignment: message.isUser ? .trailing : .leading)

                Text(message.timestamp)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(colors.textSecondary)
            }

            if message.isUser {
                AvatarChip(label: "你", bgColor: colors.primary, textColor: colors.onPrimary)
            } else {
                Spacer(minLength: 44)
            }
        }
        .frame(maxWidth: .infinity)
    }
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
