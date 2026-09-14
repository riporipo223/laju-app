import SwiftUI

// Component library button styles — design-notes.md §3.

/// Full `accent` fill, black text — the ONE primary action per screen.
struct LajuPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.title3.bold())
            .foregroundStyle(LajuColor.background)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 52)
            .background(LajuColor.accent.opacity(configuration.isPressed ? 0.8 : 1), in: Capsule())
    }
}

/// Dark surface fill with a thin `accent` line across the TOP edge only — #6(bottom)'s signature detail.
/// Secondary actions (Pause/Resume, onboarding "back"/skip).
struct LajuSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.title3.bold())
            .foregroundStyle(LajuColor.textPrimary)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 52)
            .background(LajuColor.surface.opacity(configuration.isPressed ? 0.7 : 1), in: Capsule())
            .overlay(alignment: .top) {
                // Inset from the capsule's rounded ends so this reads as a straight line sitting ON the flat
                // top, not an attempt to trace the curve itself.
                Capsule()
                    .fill(LajuColor.accent)
                    .frame(height: 2)
                    .padding(.horizontal, 20)
                    .padding(.top, 1)
            }
    }
}

/// `error`-red fill — Finish/discard confirmations only.
struct LajuDestructiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.title3.bold())
            .foregroundStyle(LajuColor.textPrimary)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 52)
            .background(LajuColor.error.opacity(configuration.isPressed ? 0.8 : 1), in: Capsule())
    }
}

extension ButtonStyle where Self == LajuPrimaryButtonStyle {
    static var lajuPrimary: LajuPrimaryButtonStyle {
        LajuPrimaryButtonStyle()
    }
}

extension ButtonStyle where Self == LajuSecondaryButtonStyle {
    static var lajuSecondary: LajuSecondaryButtonStyle {
        LajuSecondaryButtonStyle()
    }
}

extension ButtonStyle where Self == LajuDestructiveButtonStyle {
    static var lajuDestructive: LajuDestructiveButtonStyle {
        LajuDestructiveButtonStyle()
    }
}
