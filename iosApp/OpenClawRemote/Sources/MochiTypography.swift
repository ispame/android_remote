import SwiftUI

/// MochiTypography — mirrors MochiTypography (Kotlin) for SwiftUI consistency
/// All text in the app should use these styles instead of raw .system(size: X)
struct MochiTypography {
    // MARK: - headlineSmall
    // fontSize: 18, fontWeight: .medium, lineHeight: 24
    static let headlineSmall = TypographyStyle(size: 18, weight: .medium, lineHeight: 24)

    // MARK: - bodyMedium
    // fontSize: 15, fontWeight: .normal, lineHeight: 22
    static let bodyMedium = TypographyStyle(size: 15, weight: .regular, lineHeight: 22)

    // MARK: - bodySmall
    // fontSize: 11, fontWeight: .normal, lineHeight: 14
    static let bodySmall = TypographyStyle(size: 11, weight: .regular, lineHeight: 14)

    // MARK: - labelMedium
    // fontSize: 15, fontWeight: .normal, lineHeight: 20
    static let labelMedium = TypographyStyle(size: 15, weight: .regular, lineHeight: 20)

    // MARK: - labelLarge
    // fontSize: 14, fontWeight: .medium, lineHeight: 20
    static let labelLarge = TypographyStyle(size: 14, weight: .medium, lineHeight: 20)
}

struct TypographyStyle {
    let size: CGFloat
    let weight: Font.Weight
    let lineHeight: CGFloat

    /// Returns a SwiftUI Font at the defined size and weight
    var font: Font {
        .system(size: size, weight: weight)
    }

    /// Returns the line spacing (lineHeight - size)
    var lineSpacing: CGFloat {
        lineHeight - size
    }
}

// MARK: - View Extension for Easy Typography

extension View {
    /// Apply Mochi headlineSmall style
    func mochiHeadlineSmall() -> some View {
        self.font(.system(size: 18, weight: .medium))
            .lineSpacing(24 - 18)
    }

    /// Apply Mochi bodyMedium style
    func mochiBodyMedium() -> some View {
        self.font(.system(size: 15, weight: .regular))
            .lineSpacing(22 - 15)
    }

    /// Apply Mochi bodySmall style
    func mochiBodySmall() -> some View {
        self.font(.system(size: 11, weight: .regular))
            .lineSpacing(14 - 11)
    }

    /// Apply Mochi labelMedium style
    func mochiLabelMedium() -> some View {
        self.font(.system(size: 15, weight: .regular))
            .lineSpacing(20 - 15)
    }

    /// Apply Mochi labelLarge style
    func mochiLabelLarge() -> some View {
        self.font(.system(size: 14, weight: .medium))
            .lineSpacing(20 - 14)
    }
}
