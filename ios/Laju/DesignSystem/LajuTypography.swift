import SwiftUI

/// Laju's typography scale — see `Laju/documents/design-notes.md` §2. Plain system font (SF Pro) so Dynamic
/// Type keeps working automatically; `.rounded` design on numbers/headings is the one deliberate typographic
/// signature (no bundled font/license needed).
enum LajuFont {
    static let heroNumber = Font.system(size: 56, weight: .heavy, design: .rounded)
    static let sectionNumber = Font.system(size: 28, weight: .bold, design: .rounded)
    static let heading = Font.system(size: 22, weight: .bold, design: .rounded)
    static let body = Font.system(size: 15, weight: .regular)
    static let label = Font.system(size: 12, weight: .semibold)
}

/// A tracked uppercase label ABOVE a stat number (design-notes.md §2/§3) — never beside it.
struct LajuLabelText: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(LajuFont.label)
            .tracking(1.2)
            .foregroundStyle(LajuColor.textSecondary)
    }
}
