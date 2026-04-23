import SwiftUI

struct MessageBubbleView: View {
    let message: ChatMessage
    let colors: MochiColors

    var body: some View {
        HStack {
            if !message.isUser {
                AvatarChip(label: "M", bgColor: colors.secondary, textColor: colors.onSecondary)
                Spacer(minLength: 8)
            }

            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 3) {
                BoldText(text: message.content, textColor: message.isUser ? colors.userBubbleFg : colors.assistantFg)
                    .font(.system(size: 15))
                    .lineSpacing(7)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedCornerShape(
                            topLeft: message.isUser ? 16 : 4,
                            topRight: message.isUser ? 4 : 16,
                            bottomLeft: 16,
                            bottomRight: 16
                        )
                    )
                    .background(message.isUser ? colors.userBubble : colors.assistantBg)

                Text(message.timestamp)
                    .font(.system(size: 11))
                    .foregroundColor(colors.textSecondary)
            }

            if message.isUser {
                Spacer(minLength: 8)
                AvatarChip(label: "你", bgColor: colors.primary, textColor: colors.onPrimary)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct BoldText: View {
    let text: String
    let textColor: Color

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(parsedSegments.enumerated()), id: \.offset) { _, segment in
                if segment.isBold {
                    Text(segment.text)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(textColor)
                } else {
                    Text(segment.text)
                        .font(.system(size: 15))
                        .foregroundColor(textColor)
                }
            }
        }
    }

    private var parsedSegments: [(text: String, isBold: Bool)] {
        var result: [(text: String, isBold: Bool)] = []
        let pattern = "\\*\\*(.+?)\\*\\*"
        var currentIndex = text.startIndex
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return [(text, false)]
        }
        let nsRange = NSRange(text.unicodeScalars.startIndex..., in: text)
        for match in regex.matches(in: text, range: nsRange) {
            guard let swiftRange = Range(match.range, in: text),
                  let innerRange = Range(match.range(at: 1), in: text) else { continue }
            if currentIndex < swiftRange.lowerBound {
                result.append((String(text[currentIndex..<swiftRange.lowerBound]), false))
            }
            result.append((String(text[innerRange]), true))
            currentIndex = swiftRange.upperBound
        }
        if currentIndex < text.endIndex {
            result.append((String(text[currentIndex...]), false))
        }
        return result
    }
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