import SwiftUI

/// Ronde's field-instrument design system.
///
/// The watch is used outdoors, one-handed, and often at a glance. The palette
/// therefore starts with the OLED-black watch face, uses high-contrast type,
/// reserves green for golf actions and score state, and reserves orange for
/// the Apple Watch Ultra Action Button.
enum Theme {

    // MARK: - Surfaces

    static let surface = Color(red: 0.018, green: 0.027, blue: 0.021)          // #050705
    static let surfaceMuted = Color(red: 0.039, green: 0.059, blue: 0.045)     // #0A0F0B
    static let cardSurface = Color(red: 0.067, green: 0.094, blue: 0.075)      // #111813
    static let cardSurfacePressed = Color(red: 0.094, green: 0.129, blue: 0.102)
    static let separator = Color.white.opacity(0.10)

    // MARK: - Text

    static let textPrimary = Color(red: 0.953, green: 0.973, blue: 0.957)
    static let textSecondary = Color(red: 0.686, green: 0.733, blue: 0.698)
    static let textTertiary = Color(red: 0.486, green: 0.533, blue: 0.498)
    static let textFaint = Color(red: 0.294, green: 0.337, blue: 0.306)

    static let mutedText = textSecondary
    static let dimText = textTertiary
    static let faintText = textFaint

    // MARK: - Functional colours

    static let fairway = Color(red: 0.267, green: 0.808, blue: 0.463)          // #44CE76
    static let fairwayBright = Color(red: 0.416, green: 0.906, blue: 0.596)    // #6AE798
    static let fairwayDeep = Color(red: 0.078, green: 0.431, blue: 0.231)      // #146E3B
    static let action = Color(red: 1.000, green: 0.502, blue: 0.094)           // Ultra orange
    static let bunker = Color(red: 1.000, green: 0.706, blue: 0.286)
    static let eagleGold = Color(red: 1.000, green: 0.812, blue: 0.357)
    static let sky = Color(red: 0.365, green: 0.686, blue: 1.000)
    static let rough = Color(red: 1.000, green: 0.376, blue: 0.392)

    // MARK: - Score semantics

    static func scoreColor(forDelta delta: Int, hasShots: Bool = true) -> Color {
        guard hasShots else { return textTertiary }
        switch delta {
        case ...(-2): return eagleGold
        case -1:      return fairwayBright
        case 0:       return fairway
        case 1:       return bunker
        default:      return rough
        }
    }

    static func scoreName(forDelta delta: Int) -> String {
        switch delta {
        case ...(-3): return "Albatross"
        case -2:      return "Eagle"
        case -1:      return "Birdie"
        case 0:       return "Par"
        case 1:       return "Bogey"
        case 2:       return "Double"
        case 3:       return "Triple"
        default:      return "+\(delta)"
        }
    }

    static func compactScore(_ delta: Int, hasShots: Bool = true) -> String {
        guard hasShots else { return "—" }
        if delta == 0 { return "E" }
        return delta > 0 ? "+\(delta)" : "\(delta)"
    }

    // MARK: - Symbols

    enum Symbol {
        static let golfer = "figure.golf"
        static let flag = "flag.checkered"
        static let pin = "flag.fill"
        static let teeBox = "square.dashed"
        static let undo = "arrow.uturn.backward"
        static let walking = "figure.walk"
        static let location = "location.fill"
        static let calendar = "calendar"
        static let course = "leaf.fill"
        static let actionButton = "button.horizontal.top.press.fill"
    }

    // MARK: - Backgrounds

    @ViewBuilder
    static var fairwayBackdrop: some View {
        ZStack {
            surface
            RadialGradient(
                colors: [fairwayDeep.opacity(0.16), .clear, .clear],
                center: .topLeading,
                startRadius: 0,
                endRadius: 250
            )
        }
    }

    @ViewBuilder
    static func scoreBackdrop(forDelta delta: Int, hasShots: Bool = true) -> some View {
        let tint = scoreColor(forDelta: delta, hasShots: hasShots)
        ZStack {
            surface
            if hasShots {
                RadialGradient(
                    colors: [tint.opacity(0.14), tint.opacity(0.035), .clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: 230
                )
            }
        }
    }

    static var cardSurfaceShape: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(cardSurface)
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(separator, lineWidth: 1)
            }
    }
}

// MARK: - Convenience modifiers

extension View {
    func fairwayBackground() -> some View {
        background { Theme.fairwayBackdrop.ignoresSafeArea() }
    }

    func fairwayContainerBackground() -> some View {
        containerBackground(Theme.surface.gradient, for: .navigation)
    }

    func clearListBackground() -> some View {
        scrollContentBackground(.hidden)
            .background(Theme.surface)
    }

    func cardSurface(cornerRadius: CGFloat = 16) -> some View {
        background {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Theme.cardSurface)
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(Theme.separator, lineWidth: 1)
                }
        }
    }
}

// MARK: - Typography

extension Font {
    static func scoreNumeral(size: CGFloat) -> Font {
        .system(size: size, weight: .bold, design: .rounded).monospacedDigit()
    }

    static func microLabel() -> Font {
        .system(size: 9, weight: .semibold, design: .rounded)
    }

    static let titleLarge = Font.system(size: 22, weight: .bold)
    static let titleSmall = Font.system(size: 16, weight: .bold)
    static let bodyEmphasized = Font.system(size: 14, weight: .semibold)
    static let body = Font.system(size: 13, weight: .regular)
    static let caption = Font.system(size: 11, weight: .regular)
    static let micro = Font.system(size: 9, weight: .semibold)
}

// MARK: - Interaction styles

struct RondePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.9), value: configuration.isPressed)
    }
}

struct CardRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.72 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension Text {
    func sectionHeaderStyle() -> some View {
        self
            .font(.micro)
            .foregroundStyle(Theme.textTertiary)
            .tracking(1.1)
            .textCase(.uppercase)
    }
}
