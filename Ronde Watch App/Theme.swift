import SwiftUI

/// Golf-themed design tokens used throughout the app — light theme.
/// Colours are tuned for a paper-scorecard aesthetic: warm cream surface,
/// deep fairway-green typography, vintage red for over-par.
enum Theme {

    // MARK: - Surfaces

    /// Soft fairway-grass sage — the canvas everything sits on.
    static let surface = Color(red: 0.871, green: 0.906, blue: 0.835) // #DEE7D5

    /// Slightly deeper sage for subtle vignette / muted regions.
    static let surfaceMuted = Color(red: 0.835, green: 0.871, blue: 0.788) // #D5DEC9

    /// Warm cream card surface — used for list rows that sit on the sage canvas.
    static let cardSurface = Color(red: 0.969, green: 0.949, blue: 0.894) // #F7F2E4

    // MARK: - Text

    /// Primary text — deep forest green, near-black, for max readability.
    static let textPrimary = Color(red: 0.055, green: 0.141, blue: 0.090) // #0E2417

    /// Secondary text — muted forest for labels and hints.
    static let textSecondary = Color(red: 0.227, green: 0.290, blue: 0.243) // #3A4A3E

    /// Tertiary text — soft greyish-green for supplementary text.
    static let textTertiary = Color(red: 0.353, green: 0.396, blue: 0.333) // #5A6555

    /// Faint text — barely visible, for placeholders / inactive dots.
    static let textFaint = Color(red: 0.627, green: 0.667, blue: 0.627) // #A0AAA0

    /// Legacy aliases used across views — keep semantic.
    static let mutedText = textSecondary
    static let dimText = textTertiary
    static let faintText = textFaint

    // MARK: - Brand colours

    /// Refined fairway green — primary brand colour for actions and "good" states.
    static let fairway = Color(red: 0.106, green: 0.431, blue: 0.200) // #1B6E33

    /// Brighter fairway accent for highlights and birdies.
    static let fairwayBright = Color(red: 0.165, green: 0.533, blue: 0.278) // #2A8847

    /// Very deep fairway used for accents on light backdrops.
    static let fairwayDeep = Color(red: 0.043, green: 0.180, blue: 0.090) // #0B2E17

    /// Sand bunker amber — warning / bogey state.
    static let bunker = Color(red: 0.549, green: 0.376, blue: 0.063) // #8C6010

    /// Eagle gold — albatross/eagle celebrations and the highlighted -2 badge.
    static let eagleGold = Color(red: 0.761, green: 0.541, blue: 0.055) // #C28A0E

    /// Sky blue — secondary accent for navigation chrome and informational chips.
    static let sky = Color(red: 0.161, green: 0.420, blue: 0.690) // #296BB0

    /// Rough red — destructive / serious "over par" states.
    static let rough = Color(red: 0.659, green: 0.157, blue: 0.157) // #A82828

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

    /// Cream surface with a faint vignette — the canonical full-screen backdrop.
    @ViewBuilder
    static var fairwayBackdrop: some View {
        ZStack {
            surface
            RadialGradient(
                colors: [.clear, .clear, surfaceMuted.opacity(0.6)],
                center: .center,
                startRadius: 5,
                endRadius: 240
            )
        }
    }

    /// Score-tinted radial backdrop for in-round screens. Always opaque cream
    /// underneath so the watch's black system background never bleeds through.
    @ViewBuilder
    static func scoreBackdrop(forDelta delta: Int, hasShots: Bool = true) -> some View {
        let tint = scoreColor(forDelta: delta, hasShots: hasShots)
        ZStack {
            surface
            if hasShots {
                RadialGradient(
                    colors: [tint.opacity(0.22), tint.opacity(0.06), .clear],
                    center: .center,
                    startRadius: 5,
                    endRadius: 220
                )
            } else {
                RadialGradient(
                    colors: [.clear, .clear, surfaceMuted.opacity(0.6)],
                    center: .center,
                    startRadius: 5,
                    endRadius: 240
                )
            }
        }
    }
}

// MARK: - Convenience modifiers

extension View {
    /// Applies the cream backdrop ignoring safe areas — for full-screen views.
    func fairwayBackground() -> some View {
        background {
            Theme.fairwayBackdrop.ignoresSafeArea()
        }
    }

    /// Applies the cream backdrop as the watchOS container background so the
    /// nav-bar gradient and pull-down area also pick up our light theme.
    func fairwayContainerBackground() -> some View {
        containerBackground(Theme.surface.gradient, for: .navigation)
    }

    /// Hides the system List/Form scroll background so our cream surface shows
    /// through. Lists otherwise paint their own opaque background.
    func clearListBackground() -> some View {
        scrollContentBackground(.hidden)
            .background(Theme.surface)
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

// MARK: - Button styles

/// Card-style row button with our own pressed treatment. Avoids the watchOS
/// system "focus dim" overlay that makes plain-style buttons in a List
/// look pre-selected when the digital crown lands on them.
struct CardRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.65 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// Section-header text style — uppercase, tracked, deep forest secondary.
extension Text {
    func sectionHeaderStyle() -> some View {
        self
            .font(.system(size: 10, weight: .heavy, design: .rounded))
            .foregroundStyle(Theme.textSecondary)
            .tracking(1.2)
            .textCase(.uppercase)
    }
}
