import SwiftUI

/// Laju's fixed dark-native brand palette — see `Laju/documents/design-notes.md` §1. Forced dark by brand
/// identity (not system-appearance-following), so these are plain fixed colors, not light/dark pairs.
enum LajuColor {
    static let background = Color(hex: 0x000000)
    static let surface = Color(hex: 0x141414)
    static let surfaceRaised = Color(hex: 0x1E1E1E)
    static let hairline = Color(hex: 0x2A2A2A)

    static let accent = Color(hex: 0xC6FF00)
    static let accentDim = Color(hex: 0x8FB800)

    static let textPrimary = Color(hex: 0xFFFFFF)
    static let textSecondary = Color(hex: 0x8A8A8E)
    static let textDisabled = Color(hex: 0x4A4A4C)

    /// Run flagged/pending anti-cheat verification (user-flow.md §2.2) — Fase 2, reserved now.
    static let warning = Color(hex: 0xFF9F1C)
    /// Destructive actions (Finish/discard confirmation) — replaces the old placeholder `.red` tint.
    static let error = Color(hex: 0xFF453A)
    /// Locked/premium CTA (Fase 2 monetization) — a hue family with no other current use, reserved now.
    static let premium = Color(hex: 0xB983FF)
}

private extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
