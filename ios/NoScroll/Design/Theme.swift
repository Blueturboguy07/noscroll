import SwiftUI

/// The visual language.
///
/// Warm paper rather than the usual wellness-app white: the whole point is that
/// this should not feel like another productivity dashboard scoring you.
enum Theme {

    // MARK: - Colour

    static let paper = Color(hex: 0xF7EFE0)
    static let paperRaised = Color(hex: 0xFDF8EF)
    static let ink = Color(hex: 0x141414)
    static let inkSoft = Color(hex: 0x8A8578)

    /// Life-grid bands. Ordered as they stack, top to bottom.
    static let past = Color(hex: 0xC0574A)
    static let sleep = Color(hex: 0x1E3A5C)
    static let work = Color(hex: 0x4E8577)
    static let hygiene = Color(hex: 0xA99BD4)
    static let scrolling = Color(hex: 0xD4402F)
    static let free = Color(hex: 0x3FA968)

    // MARK: - Type

    /// Display face. The system rounded weightings carry the same friendly-but-
    /// blunt tone as the reference without shipping a licensed font.
    static func display(_ size: CGFloat, _ weight: Font.Weight = .black) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    static func body(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    /// Small letterspaced caps used for section eyebrows ("THIS IS YOUR LIFE").
    static func eyebrow(_ size: CGFloat = 13) -> Font {
        .system(size: size, weight: .semibold, design: .rounded)
    }

    // MARK: - Shape

    static let cardRadius: CGFloat = 22
    static let buttonRadius: CGFloat = 32
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

// MARK: - Shared controls

/// The primary action button: full-width, heavy, high contrast.
struct PrimaryButton: View {
    let title: String
    var tint: Color = Theme.ink
    var foreground: Color = Theme.paperRaised
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Theme.display(19, .bold))
                .foregroundStyle(foreground)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 19)
                .background(tint, in: RoundedRectangle(cornerRadius: Theme.buttonRadius))
        }
        .buttonStyle(.plain)
    }
}

struct SecondaryButton: View {
    let title: String
    var outlined = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Theme.display(18, .bold))
                .foregroundStyle(Theme.inkSoft)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 17)
                .background {
                    if outlined {
                        RoundedRectangle(cornerRadius: Theme.buttonRadius)
                            .strokeBorder(Theme.inkSoft.opacity(0.45), lineWidth: 1.5)
                    }
                }
        }
        .buttonStyle(.plain)
    }
}

/// The three-dot progress indicator used across the permission pages.
struct PageDots: View {
    let count: Int
    let index: Int

    var body: some View {
        HStack(spacing: 7) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(i == index ? Theme.ink : Theme.inkSoft.opacity(0.4))
                    .frame(width: i == index ? 26 : 7, height: 7)
                    .animation(.snappy, value: index)
            }
        }
    }
}
