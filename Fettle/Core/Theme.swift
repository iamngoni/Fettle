import SwiftUI

/// Centralized design tokens, mirrored from the Pencil designs.
enum Theme {
    static let bg = Color(hex: 0x1B1B1F)
    static let card = Color.white.opacity(0.04)
    static let cardElevated = Color.white.opacity(0.06)
    static let hairline = Color.white.opacity(0.06)
    static let stroke = Color.white.opacity(0.08)
    static let fieldStroke = Color.white.opacity(0.14)

    static let textPrimary = Color(hex: 0xF5F5F7)
    static let textSecondary = Color(hex: 0x9A9AA2)
    static let textMuted = Color(hex: 0x8E8E96)
    static let textTertiary = Color(hex: 0x6E6E78)

    static let accent = Color(hex: 0xFF8A00)
    static let accentLight = Color(hex: 0xFFB060)
    static let green = Color(hex: 0x34C759)
    static let greenLight = Color(hex: 0x7DE08F)
    static let red = Color(hex: 0xFF453A)
    static let redLight = Color(hex: 0xFF6B61)

    static let panelWidth: CGFloat = 320
    static let corner: CGFloat = 12

    static let accentGradient = LinearGradient(
        colors: [Color(hex: 0xFFB347), Color(hex: 0xFF8A00)],
        startPoint: .topLeading, endPoint: .bottomTrailing)
}

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: alpha)
    }
}
