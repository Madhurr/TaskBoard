import SwiftUI

/// Visual constants. Colours are light/dark pairs resolved through the trait
/// collection, so the palette lives in one file rather than the asset catalog.
enum Theme {

    // MARK: - Palette

    static let canvas = adaptive(light: 0xF4F5F9, dark: 0x0E1014)
    static let canvasElevated = adaptive(light: 0xFFFFFF, dark: 0x171A21)
    static let surface = adaptive(light: 0xFFFFFF, dark: 0x1C2029)
    static let surfacePressed = adaptive(light: 0xEEF0F6, dark: 0x232833)
    static let hairline = adaptive(light: 0xE2E5EE, dark: 0x2A303C)

    static let textPrimary = adaptive(light: 0x14161C, dark: 0xF2F4F8)
    static let textSecondary = adaptive(light: 0x5C6478, dark: 0x99A1B3)
    static let textTertiary = adaptive(light: 0x8B92A5, dark: 0x6B7387)

    static let accent = adaptive(light: 0x4A63E7, dark: 0x6B84FF)
    static let warning = adaptive(light: 0xB86A00, dark: 0xFFB454)
    static let danger = adaptive(light: 0xC0392B, dark: 0xFF6B5B)
    static let success = adaptive(light: 0x1E8E5A, dark: 0x4ED9A0)

    // MARK: - Metrics

    enum Radius {
        static let card: CGFloat = 16
        static let column: CGFloat = 22
        static let control: CGFloat = 12
        static let pill: CGFloat = 999
    }

    enum Spacing {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
    }

    static let columnWidth: CGFloat = 300

    // MARK: - Motion

    /// One spring for everything, so all motion shares a sense of weight.
    static let motion = Animation.spring(response: 0.34, dampingFraction: 0.78)
    static let quickMotion = Animation.spring(response: 0.22, dampingFraction: 0.85)

    // MARK: - Helpers

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

// MARK: - Shared modifiers

extension View {
    /// The standard raised surface used by cards and sheets.
    ///
    /// `accent` draws the leading status stripe. It goes inside the clipped
    /// surface — layered behind the card it would overhang the rounded corners.
    func cardSurface(
        cornerRadius: CGFloat = Theme.Radius.card,
        accent: Color? = nil,
        elevated: Bool = false
    ) -> some View {
        background {
            ZStack(alignment: .leading) {
                Theme.surface
                if let accent {
                    Rectangle()
                        .fill(accent)
                        .frame(width: 3)
                }
            }
            .clipShape(.rect(cornerRadius: cornerRadius))
        }
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(Theme.hairline, lineWidth: 1)
        }
        .shadow(
            color: .black.opacity(elevated ? 0.22 : 0.06),
            radius: elevated ? 18 : 6,
            y: elevated ? 10 : 2
        )
    }
}
