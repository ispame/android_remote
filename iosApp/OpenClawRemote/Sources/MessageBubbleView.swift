import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct MessageBubbleView: View {
    let message: ChatMessage
    let colors: MochiColors
    let isSelectionMode: Bool
    let isSelected: Bool
    let onTap: () -> Void
    let onCopy: () -> Void
    let onQuote: () -> Void
    let onSelect: () -> Void
    let onSpeak: () -> Void
    let onApprovalCommand: (String) -> Void
    let isApprovalHandled: Bool
    let onInspectApprovalCode: (ApprovalRequest) -> Void
    let onCopyTable: (MarkdownTable) -> Void
    let onDownloadTable: (MarkdownTable) -> Void
    let onFullscreenTable: (MarkdownTable) -> Void

    private var usesWideLayout: Bool {
        !message.isUser && (approvalRequest != nil || message.content.prefersWideMessageLayout)
    }

    private var approvalRequest: ApprovalRequest? {
        message.isUser ? nil : ApprovalRequest.detect(in: message.content)
    }

    private var maxBubbleWidth: CGFloat {
        messageBubbleMaxWidth(usesWideLayout: usesWideLayout)
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
                if let approvalRequest {
                    ApprovalActionsView(
                        request: approvalRequest,
                        colors: colors,
                        isHandled: isApprovalHandled,
                        onCommand: onApprovalCommand,
                        onInspectCode: onInspectApprovalCode
                    )
                    .frame(maxWidth: messageBubbleMaxWidth(usesWideLayout: true), alignment: .leading)
                } else if let recordingContent = RecordingChatContent.parse(message.content) {
                    RecordingChatBubbleContent(
                        content: recordingContent,
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
                        maxWidth: maxBubbleWidth,
                        alignment: message.isUser ? .trailing : .leading
                    )
                } else {
                    CollapsibleMessageContent(
                        text: message.content,
                        textColor: message.isUser ? colors.userBubbleFg : colors.assistantFg,
                        colors: colors,
                        onCopyTable: onCopyTable,
                        onDownloadTable: onDownloadTable,
                        onFullscreenTable: onFullscreenTable
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
                            maxWidth: maxBubbleWidth,
                            alignment: message.isUser ? .trailing : .leading
                        )
                }

                if !message.trace.isEmpty {
                    MessageTraceDisclosureView(trace: message.trace, colors: colors)
                        .frame(maxWidth: maxBubbleWidth, alignment: .leading)
                }

                Text(message.timestamp)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(colors.textSecondary)
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
            Button(action: onSpeak) {
                Label("朗读", systemImage: "speaker.wave.2")
            }
            Button(action: onSelect) {
                Label("选择", systemImage: "checkmark.circle")
            }
        }
    }
}

private struct MessageTraceDisclosureView: View {
    let trace: [MessageTraceItem]
    let colors: MochiColors

    @State private var isExpanded = false

    private var summary: String {
        let counts = Dictionary(grouping: trace, by: \.kind).mapValues(\.count)
        let parts = [MessageTraceKind.reasoning, .toolCall, .toolResult, .system, .other].compactMap { kind -> String? in
            guard let count = counts[kind], count > 0 else { return nil }
            return "\(kind.label) \(count)"
        }
        return parts.joined(separator: " / ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.16)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 12)
                    Image(systemName: "point.3.connected.trianglepath.dotted")
                        .font(.system(size: 12, weight: .semibold))
                    Text(summary.isEmpty ? "执行过程 \(trace.count)" : summary)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .foregroundColor(colors.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(colors.inputBg.opacity(0.72))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(trace) { item in
                        MessageTraceRow(item: item, colors: colors)
                    }
                }
                .padding(10)
                .background(colors.inputBg.opacity(0.52))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(colors.divider.opacity(0.8), lineWidth: 1)
                )
            }
        }
    }
}

private struct RecordingChatBubbleContent: View {
    let content: RecordingChatContent
    let textColor: Color
    let colors: MochiColors

    @State private var showsPrompt = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: "waveform")
                    .font(.system(size: 13, weight: .semibold))
                Text("录音")
                    .font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 0)
                Button {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        showsPrompt.toggle()
                    }
                } label: {
                    Image(systemName: showsPrompt ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(showsPrompt ? "收起录音 Prompt" : "展开录音 Prompt")
            }
            .foregroundColor(textColor)

            if showsPrompt {
                VStack(alignment: .leading, spacing: 4) {
                    Text("录音 Prompt")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(textColor.opacity(0.72))
                    Text(content.prompt.isEmpty ? "未设置" : content.prompt)
                        .font(.system(size: 12))
                        .foregroundColor(textColor.opacity(0.82))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(8)
                .background(colors.inputBg.opacity(0.18))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            Text(content.transcript.isEmpty ? "等待 ASR 文本" : content.transcript)
                .font(.system(size: 14))
                .foregroundColor(textColor)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }
}

private struct MessageTraceRow: View {
    let item: MessageTraceItem
    let colors: MochiColors

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Image(systemName: item.kind.systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(colors.primary)
                    .frame(width: 14)
                Text(item.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(colors.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if item.content.count > 120 || item.content.contains("\n") {
                    Button {
                        withAnimation(.easeInOut(duration: 0.16)) {
                            isExpanded.toggle()
                        }
                    } label: {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(colors.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            Text(isExpanded ? item.content : item.preview)
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundColor(colors.textSecondary)
                .lineLimit(isExpanded ? nil : 3)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
    }
}

private func messageBubbleMaxWidth(usesWideLayout: Bool) -> CGFloat {
    #if os(iOS)
    UIScreen.main.bounds.width * (usesWideLayout ? 0.94 : 0.82)
    #else
    usesWideLayout ? 620 : 320
    #endif
}

private struct ApprovalActionsView: View {
    let request: ApprovalRequest
    let colors: MochiColors
    let isHandled: Bool
    let onCommand: (String) -> Void
    let onInspectCode: (ApprovalRequest) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 15, weight: .semibold))
                Text(request.title)
                    .font(.system(size: 15, weight: .semibold))
                Spacer(minLength: 0)
            }
            .foregroundColor(Color(red: 1.0, green: 0.76, blue: 0.29))
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(red: 0.37, green: 0.18, blue: 0.04))

            VStack(alignment: .leading, spacing: 12) {
                if !request.command.isEmpty {
                    Button {
                        onInspectCode(request)
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(request.commandPreview)
                                .font(.system(size: 13, weight: .regular, design: .monospaced))
                                .foregroundColor(Color.white.opacity(0.88))
                                .lineLimit(4)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Divider().background(Color.white.opacity(0.18))

                            HStack {
                                Text("\(request.lineCount) 行代码")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(colors.textSecondary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(colors.textSecondary)
                            }
                        }
                        .padding(10)
                        .background(Color.black.opacity(0.55))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.white.opacity(0.14), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }

                if !request.reason.isEmpty {
                    Text("Reason: \(request.reason)")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(colors.textPrimary)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if isHandled {
                    Text("已处理，本条审批不会再次发送")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(colors.textSecondary)
                }

                ApprovalButtonGrid(
                    colors: colors,
                    isDisabled: isHandled,
                    onCommand: onCommand
                )
            }
            .padding(12)
        }
        .background(colors.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(colors.divider, lineWidth: 1)
        )
        .cornerRadius(8)
    }
}

private struct ApprovalButtonGrid: View {
    let colors: MochiColors
    let isDisabled: Bool
    let onCommand: (String) -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ApprovalCommandButton(
                title: "Allow Once",
                systemImage: "checkmark",
                foreground: colors.onPrimary,
                background: colors.primary,
                command: "/approve",
                isDisabled: isDisabled,
                onCommand: onCommand
            )

            ApprovalCommandButton(
                title: "Session",
                systemImage: "checkmark.shield",
                foreground: colors.textPrimary,
                background: colors.inputBg,
                command: "/approve session",
                isDisabled: isDisabled,
                onCommand: onCommand
            )

            ApprovalCommandButton(
                title: "Always",
                systemImage: "checkmark.seal",
                foreground: colors.textPrimary,
                background: colors.inputBg,
                command: "/approve always",
                isDisabled: isDisabled,
                onCommand: onCommand
            )

            ApprovalCommandButton(
                title: "Deny",
                systemImage: "xmark",
                foreground: colors.recordingRed,
                background: colors.recordingRed.opacity(0.12),
                command: "/deny",
                isDisabled: isDisabled,
                onCommand: onCommand
            )
        }
    }
}

private struct ApprovalCommandButton: View {
    let title: String
    let systemImage: String
    let foreground: Color
    let background: Color
    let command: String
    let isDisabled: Bool
    let onCommand: (String) -> Void

    var body: some View {
        Button {
            guard !isDisabled else { return }
            onCommand(command)
        } label: {
            HStack(spacing: 7) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .bold))
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundColor(foreground)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 9)
            .padding(.vertical, 10)
            .background(background)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.45 : 1)
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
    let onCopyTable: (MarkdownTable) -> Void
    let onDownloadTable: (MarkdownTable) -> Void
    let onFullscreenTable: (MarkdownTable) -> Void

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
                colors: colors,
                onCopyTable: onCopyTable,
                onDownloadTable: onDownloadTable,
                onFullscreenTable: onFullscreenTable
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

private let collapsedLineLimit = 10
private let markdownTableFoldRowLimit = 10
private let collapsedCharacterLimit = 650
private let denseContinuousCharacterLimit = 900

func analyzeMessageContent(_ text: String) -> MessageContentAnalysis {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if looksLikeDenseEncodedContent(trimmed) {
        return MessageContentAnalysis(kind: .denseEncoded, preview: "")
    }

    if containsMarkdownTable(text) {
        return MessageContentAnalysis(kind: .normal, preview: text)
    }

    let lines = text.components(separatedBy: .newlines)
    if lines.count > collapsedLineLimit || text.count > collapsedCharacterLimit {
        return MessageContentAnalysis(kind: .longText, preview: collapsedPreview(for: text))
    }

    return MessageContentAnalysis(kind: .normal, preview: text)
}

func containsMarkdownTable(_ text: String) -> Bool {
    parseBlocks(text).contains { block in
        if case .table = block { return true }
        return false
    }
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
    let onCopyTable: (MarkdownTable) -> Void
    let onDownloadTable: (MarkdownTable) -> Void
    let onFullscreenTable: (MarkdownTable) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(parseBlocks(text).enumerated()), id: \.offset) { _, block in
                switch block {
                case .text(let value):
                    if !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        MarkdownText(text: value, textColor: textColor, font: .system(size: 15))
                    }
                case .table(let table):
                    MarkdownTableView(
                        table: table,
                        colors: colors,
                        textColor: textColor,
                        onCopy: onCopyTable,
                        onDownload: onDownloadTable,
                        onFullscreen: onFullscreenTable
                    )
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

struct MarkdownTable: Identifiable, Equatable {
    let headers: [String]
    let rows: [[String]]

    var id: String {
        markdownSource
    }

    var markdownSource: String {
        let allRows = [headers] + rows
        return allRows.enumerated().map { index, row in
            let cells = normalizedCells(row, width: headers.count)
                .map { $0.replacingOccurrences(of: "\n", with: " ") }
            let line = "| " + cells.joined(separator: " | ") + " |"
            if index == 0 {
                let separator = "| " + Array(repeating: "---", count: headers.count).joined(separator: " | ") + " |"
                return line + "\n" + separator
            }
            return line
        }
        .joined(separator: "\n")
    }

    var csvSource: String {
        ([headers] + rows)
            .map { row in
                normalizedCells(row, width: headers.count)
                    .map(csvEscapedCell)
                    .joined(separator: ",")
            }
            .joined(separator: "\n")
    }

    var shouldFoldRows: Bool {
        rows.count > markdownTableFoldRowLimit
    }

    var hiddenRowCount: Int {
        max(0, rows.count - markdownTableFoldRowLimit)
    }

    func visibleRows(isExpanded: Bool) -> [[String]] {
        guard shouldFoldRows, !isExpanded else { return rows }
        return Array(rows.prefix(markdownTableFoldRowLimit))
    }

    private func normalizedCells(_ cells: [String], width: Int) -> [String] {
        if cells.count == width { return cells }
        if cells.count > width { return Array(cells.prefix(width)) }
        return cells + Array(repeating: "", count: width - cells.count)
    }

    private func csvEscapedCell(_ value: String) -> String {
        let normalized = value.replacingOccurrences(of: "\r\n", with: "\n")
        let needsEscaping = normalized.contains(",") || normalized.contains("\"") || normalized.contains("\n")
        guard needsEscaping else { return normalized }
        return "\"" + normalized.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

struct MarkdownTableView: View {
    let table: MarkdownTable
    let colors: MochiColors
    let textColor: Color
    let onCopy: (MarkdownTable) -> Void
    let onDownload: (MarkdownTable) -> Void
    let onFullscreen: (MarkdownTable) -> Void
    @State private var isExpanded = false

    private var visibleTable: MarkdownTable {
        MarkdownTable(headers: table.headers, rows: table.visibleRows(isExpanded: isExpanded))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("表格")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(textColor.opacity(0.72))
                Spacer()
                TableToolButton(systemImage: "doc.on.doc", accessibilityLabel: "复制表格") {
                    onCopy(table)
                }
                TableToolButton(systemImage: "square.and.arrow.down", accessibilityLabel: "下载表格") {
                    onDownload(table)
                }
                TableToolButton(systemImage: "arrow.up.left.and.arrow.down.right", accessibilityLabel: "全屏查看表格") {
                    onFullscreen(table)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(colors.surface.opacity(0.72))

            ScrollView(.horizontal, showsIndicators: true) {
                MarkdownTableGrid(table: visibleTable, colors: colors, textColor: textColor)
            }

            if table.shouldFoldRows {
                Button {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text(isExpanded ? "收起表格" : "展开全部 \(table.rows.count) 行")
                            .font(.system(size: 12, weight: .medium))
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(textColor.opacity(0.78))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(colors.surface.opacity(0.42))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(colors.divider.opacity(0.8), lineWidth: 1)
        )
    }
}

private struct TableToolButton: View {
    let systemImage: String
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 30, height: 30)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

struct MarkdownTableGrid: View {
    let table: MarkdownTable
    let colors: MochiColors
    let textColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            tableRow(table.headers, isHeader: true)
            ForEach(Array(table.rows.enumerated()), id: \.offset) { _, row in
                tableRow(row, isHeader: false)
            }
        }
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
