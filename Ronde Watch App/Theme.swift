import SwiftUI

/// Golf-themed design tokens used throughout the app — light theme.
/// Colours are tuned for a paper-scorecard aesthetic: warm cream surface,
/// deep fairway-green typography, vintage red for over-par.
enum Theme {

    // MARK: - Surfaces

    /// Warm off-white scorecard background — primary canvas.
    static let surface = Color(red: 0.98, green: 0.96, blue: 0.91)

    /// Pure white card surface — for list rows / elevated content.
    static let cardSurface = Color.white

    /// Slightly darker tinted surface for subtle separation.
    static let surfaceMuted = Color(red: 0.94, green: 0.92, blue: 0.86)

    // MARK: - Text

    /// Primary text — very dark green, near black, for max readability.
    static let textPrimary = Color(red: 0.08, green: 0.16, blue: 0.10)

    /// Secondary text — muted dark green for labels and hints.
    static let textSecondary = Color(red: 0.32, green: 0.40, blue: 0.34)

    /// Tertiary text — soft greyish-green for disabled or supplementary text.
    static let textTertiary = Color(red: 0.55, green: 0.60, blue: 0.55)

    /// Faint text — barely visible, for placeholders and dot indicators.
    static let textFaint = Color(red: 0.78, green: 0.80, blue: 0.76)

    /// Legacy aliases used across views — keep semantic.
    static let mutedText = textSecondary
    static let dimText = textTertiary
    static let faintText = textFaint

    // MARK: - Brand colours

    /// Deep fairway green — primary brand colour, used for actions and "good" states.
    static let fairway = Color(red: 0.13, green: 0.45, blue: 0.25)

    /// Brighter fairway accent for highlights and birdies.
    static let fairwayBright = Color(red: 0.20, green: 0.62, blue: 0.32)

    /// Very deep fairway tint used for backdrop gradients.
    static let fairwayDeep = Color(red: 0.10, green: 0.32, blue: 0.18)

    /// Sand bunker amber — warning / over-par.
    static let bunker = Color(red: 0.78, green: 0.55, blue: 0.18)

    /// Eagle gold — albatross/eagle celebrations.
    static let eagleGold = Color(red: 0.82, green: 0.62, blue: 0.10)

    /// Sky blue — secondary accent for navigation chrome and informational chips.
    static let sky = Color(red: 0.16, green: 0.45, blue: 0.78)

    /// Rough red — destructive / serious "over par" states.
    static let rough = Color(red: 0.74, green: 0.18, blue: 0.18)

    // MARK: - Score colour

    /// Maps a score-to-par delta to a colour using the golf vocabulary.
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

    /// Long-form name for a score-to-par delta.
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

    // MARK: - Symbols

    /// Canonical SF Symbol names used in golf-specific UI.
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
    }

    // MARK: - Backgrounds

    /// Subtle vignette gradient — cream centre, slightly tinted edges.
    static var fairwayBackdrop: some ShapeStyle {
        RadialGradient(
            colors: [
                surface,
                surface,
                surfaceMuted,
            ],
            center: .center,
            startRadius: 5,
            endRadius: 220
        )
    }

    /// Score-tinted radial backdrop for in-round screens.
    /// Stays light and readable — a faint wash of the score colour over cream.
    static func scoreBackdrop(forDelta delta: Int, hasShots: Bool = true) -> some ShapeStyle {
        let tint = scoreColor(forDelta: delta, hasShots: hasShots)
        return RadialGradient(
            colors: hasShots
                ? [tint.opacity(0.18), tint.opacity(0.05), surface]
                : [surface, surface, surfaceMuted],
            center: .center,
            startRadius: 5,
            endRadius: 200
        )
    }
}

// MARK: - Convenience modifiers

extension View {
    /// Applies the cream backdrop ignoring safe areas — for full-screen views.
    func fairwayBackground() -> some View {
        background {
            Rectangle().fill(Theme.fairwayBackdrop).ignoresSafeArea()
        }
    }
}

// MARK: - Typography

extension Font {
    /// Golf-card style: tight rounded heavy numerals.
    static func scoreNumeral(size: CGFloat) -> Font {
        .system(size: size, weight: .heavy, design: .rounded).monospacedDigit()
    }

    /// Small uppercase tracking label, e.g. "PAR", "HOLE".
    static func microLabel() -> Font {
        .system(size: 9, weight: .heavy, design: .rounded)
    }
}
