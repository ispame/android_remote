import SwiftUI

struct MochiColors {
    let background: Color
    let surface: Color
    let primary: Color
    let onPrimary: Color
    let secondary: Color
    let onSecondary: Color
    let accent: Color
    let userBubble: Color
    let userBubbleFg: Color
    let assistantBg: Color
    let assistantFg: Color
    let textPrimary: Color
    let textSecondary: Color
    let divider: Color
    let inputBg: Color
    let inputBorder: Color
    let inputText: Color
    let inputPlaceholder: Color
    let icon: Color
    let onlineGreen: Color
    let recordingRed: Color

    static let light = MochiColors(
        background: Color(hex: "FAF7F2"),
        surface: Color(hex: "FDFCF9"),
        primary: Color(hex: "B85C38"),
        onPrimary: .white,
        secondary: Color(hex: "E8DED0"),
        onSecondary: Color(hex: "3D2B1F"),
        accent: Color(hex: "E8A87C"),
        userBubble: Color(hex: "B85C38"),
        userBubbleFg: .white,
        assistantBg: Color(hex: "F0EBE3"),
        assistantFg: Color(hex: "3D2B1F"),
        textPrimary: Color(hex: "3D2B1F"),
        textSecondary: Color(hex: "7A6555"),
        divider: Color(hex: "E0D6C8"),
        inputBg: Color(hex: "F5F1EC"),
        inputBorder: Color(hex: "E0D6C8"),
        inputText: Color(hex: "3D2B1F"),
        inputPlaceholder: Color(hex: "9A8575"),
        icon: Color(hex: "7A6555"),
        onlineGreen: Color(hex: "4CAF50"),
        recordingRed: Color(hex: "E53935")
    )

    static let dark = MochiColors(
        background: .black,
        surface: Color(hex: "0D0D0D"),
        primary: Color(hex: "C9884A"),
        onPrimary: .black,
        secondary: Color(hex: "1A1A1A"),
        onSecondary: Color(hex: "EBEBEB"),
        accent: Color(hex: "E8A87C"),
        userBubble: Color(hex: "C9884A"),
        userBubbleFg: .black,
        assistantBg: Color(hex: "141414"),
        assistantFg: Color(hex: "EBEBEB"),
        textPrimary: Color(hex: "EBEBEB"),
        textSecondary: Color(hex: "888888"),
        divider: Color(hex: "1F1F1F"),
        inputBg: Color(hex: "141414"),
        inputBorder: Color(hex: "2A2A2A"),
        inputText: Color(hex: "EBEBEB"),
        inputPlaceholder: Color(hex: "555555"),
        icon: Color(hex: "888888"),
        onlineGreen: Color(hex: "4CAF50"),
        recordingRed: Color(hex: "E53935")
    )
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}