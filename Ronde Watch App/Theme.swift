import SwiftUI

/// Golf-themed design tokens used throughout the app.
/// Centralised so that colour, typography, and copy stay consistent.
enum Theme {

    // MARK: - Palette

    /// Deep fairway green — primary brand colour, used for actions and "good" states.
    static let fairway = Color(red: 0.18, green: 0.55, blue: 0.32)

    /// Lighter, brighter fairway accent for highlights and birdies.
    static let fairwayBright = Color(red: 0.36, green: 0.78, blue: 0.45)

    /// Rich green-tinted gradient backdrop colour.
    static let fairwayDeep = Color(red: 0.05, green: 0.18, blue: 0.10)

    /// Sand bunker gold — for warnings, bogeys, and "over par" states.
    static let bunker = Color(red: 0.95, green: 0.74, blue: 0.30)

    /// Eagle gold — for albatross/eagle celebration moments.
    static let eagleGold = Color(red: 1.0, green: 0.84, blue: 0.27)

    /// Sky blue — secondary accent for navigation and informational chips.
    static let sky = Color(red: 0.40, green: 0.70, blue: 0.95)

    /// Rough red — for serious "over par" / destructive states.
    static let rough = Color(red: 0.92, green: 0.31, blue: 0.30)

    /// Subtle muted text colour — replaces ad-hoc `.white.opacity(0.4)`.
    static let mutedText = Color.white.opacity(0.45)
    static let dimText = Color.white.opacity(0.30)
    static let faintText = Color.white.opacity(0.15)

    // MARK: - Score colour

    /// Maps a score-to-par delta to a colour using the golf vocabulary.
    static func scoreColor(forDelta delta: Int, hasShots: Bool = true) -> Color {
        guard hasShots else { return mutedText }
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

    /// Subtle vignette gradient that gives every screen a fairway-green glow
    /// at the edges without competing with content.
    static var fairwayBackdrop: some ShapeStyle {
        RadialGradient(
            colors: [
                fairwayDeep.opacity(0.55),
                fairwayDeep.opacity(0.20),
                .black,
            ],
            center: .center,
            startRadius: 5,
            endRadius: 220
        )
    }

    /// Score-tinted radial backdrop for in-round screens.
    static func scoreBackdrop(forDelta delta: Int, hasShots: Bool = true) -> some ShapeStyle {
        let tint = scoreColor(forDelta: delta, hasShots: hasShots)
        return RadialGradient(
            colors: hasShots
                ? [tint.opacity(0.22), tint.opacity(0.06), .clear]
                : [fairwayDeep.opacity(0.4), fairwayDeep.opacity(0.10), .clear],
            center: .center,
            startRadius: 5,
            endRadius: 200
        )
    }
}

// MARK: - Convenience modifiers

extension View {
    /// Applies the fairway backdrop ignoring safe areas — for full-screen views.
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
