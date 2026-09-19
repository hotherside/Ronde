import SwiftUI

/// Clubhouse identity with an opaque content plane and native glass controls.
enum RondeReviewDesign {
    static let canvas = Color(red: 247 / 255, green: 248 / 255, blue: 242 / 255)
    static let surface = Color.white
    static let surfaceRaised = Color.white
    static let surfaceInset = Color(red: 238 / 255, green: 241 / 255, blue: 231 / 255)
    static let graphite = Color(red: 23 / 255, green: 59 / 255, blue: 48 / 255)
    static let graphiteMuted = Color(red: 91 / 255, green: 105 / 255, blue: 94 / 255)
    static let graphiteFaint = Color(red: 103 / 255, green: 117 / 255, blue: 106 / 255)
    static let border = Color(red: 223 / 255, green: 228 / 255, blue: 217 / 255)
    static let borderStrong = Color(red: 161 / 255, green: 174 / 255, blue: 157 / 255)
    static let fairway = Color(red: 36 / 255, green: 83 / 255, blue: 64 / 255)
    static let fairwayBright = Color(red: 54 / 255, green: 112 / 255, blue: 77 / 255)
    static let fairwayWash = Color(red: 232 / 255, green: 241 / 255, blue: 184 / 255)
    static let mediaStage = Color(red: 24 / 255, green: 35 / 255, blue: 35 / 255)
    static let amber = Color(red: 0.510, green: 0.390, blue: 0.165)
    static let amberWash = Color(red: 0.949, green: 0.907, blue: 0.795)
    static let tracerPurple = Color(red: 0.570, green: 0.280, blue: 0.980)
    static let tracerPurpleSoft = Color(red: 0.740, green: 0.580, blue: 1.000)
    static let tracerPurpleWash = Color(red: 0.930, green: 0.895, blue: 1.000)
    static let red = Color(red: 0.705, green: 0.175, blue: 0.160)
    static let redWash = Color(red: 0.990, green: 0.900, blue: 0.895)
    // Retained names for existing analysis views; app actions share one accent.
    static let blue = fairway
    static let blueWash = surfaceInset

    static let smallRadius: CGFloat = 8
    static let controlRadius: CGFloat = 12
    static let cardRadius: CGFloat = 12
    static let largeRadius: CGFloat = 16
    static let minimumTouchTarget: CGFloat = 44
    static let compactPageInset: CGFloat = 16
    static let regularPageInset: CGFloat = 28
    static let inspectorWidth: CGFloat = 320

    static func statusColor(for status: ReviewStatus) -> Color {
        switch status {
        case .ready, .complete: return fairway
        case .analysing, .capturing, .reviewing: return blue
        case .paused, .needsAttention: return amber
        case .failed: return red
        }
    }

    static func classificationColor(for classification: ShotClassification) -> Color {
        switch classification {
        case .likelyShot: return fairway
        case .practice: return graphiteMuted
        case .uncertain: return amber
        }
    }
}

extension View {
    func reviewCanvasBackground() -> some View {
        background(RondeReviewDesign.canvas.ignoresSafeArea())
    }

    func reviewCard(cardPadding: CGFloat = 16) -> some View {
        self.padding(cardPadding)
            .background(
                RoundedRectangle(cornerRadius: RondeReviewDesign.cardRadius, style: .continuous)
                    .fill(RondeReviewDesign.surfaceRaised)
                    .overlay {
                        RoundedRectangle(cornerRadius: RondeReviewDesign.cardRadius, style: .continuous)
                            .stroke(RondeReviewDesign.border, lineWidth: 0.8)
                    }
            )
    }

    @ViewBuilder
    func rondeConditionalGlass(isEnabled: Bool, cornerRadius: CGFloat) -> some View {
        if isEnabled {
            rondeControlSurface(cornerRadius: cornerRadius)
        } else {
            self
        }
    }

    /// Apply after layout to a floating control island, never a media/content card.
    /// Leave `interactive` false for a group containing independent controls.
    func rondeControlSurface(
        interactive: Bool = false,
        tint: Color? = nil,
        cornerRadius: CGFloat = RondeReviewDesign.controlRadius
    ) -> some View {
        modifier(RondeControlSurface(interactive: interactive, tint: tint, cornerRadius: cornerRadius))
    }

    func rondePrimaryAction(tint: Color = RondeReviewDesign.fairway) -> some View {
        modifier(RondeActionStyle(prominent: true, tint: tint))
    }

    func rondeSecondaryAction(tint: Color = RondeReviewDesign.fairway) -> some View {
        modifier(RondeActionStyle(prominent: false, tint: tint))
    }

    /// Format tiles and other choices remain opaque, with a strong selection edge.
    func rondeSelectionSurface(isSelected: Bool, cornerRadius: CGFloat = RondeReviewDesign.controlRadius) -> some View {
        background(isSelected ? RondeReviewDesign.fairwayWash : RondeReviewDesign.surface,
                   in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(isSelected ? RondeReviewDesign.fairway : RondeReviewDesign.border,
                                  lineWidth: isSelected ? 2 : 1)
            }
    }
}

/// Groups sibling glass controls; content views still own their stack/layout.
struct RondeGlassGroup<Content: View>: View {
    var spacing: CGFloat = 12
    @ViewBuilder var content: () -> Content

    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content() }
        } else {
            content()
        }
    }
}

private struct RondeControlSurface: ViewModifier {
    let interactive: Bool
    let tint: Color?
    let cornerRadius: CGFloat
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(tint ?? RondeReviewDesign.surface, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(RondeReviewDesign.borderStrong, lineWidth: 1)
                }
        } else if #available(iOS 26.0, *) {
            content.glassEffect(.regular.tint(tint).interactive(interactive), in: .rect(cornerRadius: cornerRadius))
        } else if let tint {
            content.background(tint, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            content.background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }
}

private struct RondeActionStyle: ViewModifier {
    let prominent: Bool
    let tint: Color
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *), !reduceTransparency {
            if prominent {
                // A parent content colour otherwise overrides the system's contrast
                // choice, making forest labels disappear on the forest glass tint.
                content.foregroundStyle(Color.white).buttonStyle(.glassProminent).tint(tint)
            } else {
                content.buttonStyle(.glass).tint(tint)
            }
        } else if prominent {
            content.buttonStyle(ReviewPrimaryButtonStyle(tint: tint))
        } else {
            content.buttonStyle(ReviewSecondaryButtonStyle(tint: tint))
        }
    }
}

struct ReviewTag: View {
    let title: String
    let systemImage: String?
    let tint: Color

    init(_ title: String, systemImage: String? = nil, tint: Color) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
    }

    var body: some View {
        HStack(spacing: 5) {
            if let systemImage {
                Image(systemName: systemImage)
            }
            Text(title)
        }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(tint.opacity(0.085), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .accessibilityElement(children: .combine)
    }
}

struct ReviewPrimaryButtonStyle: ButtonStyle {
    var tint: Color = RondeReviewDesign.fairway
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 16)
            .frame(minHeight: 46)
            .background(tint.opacity(configuration.isPressed ? 0.82 : 1), in: RoundedRectangle(cornerRadius: RondeReviewDesign.controlRadius, style: .continuous))
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

struct ReviewSecondaryButtonStyle: ButtonStyle {
    var tint: Color = RondeReviewDesign.graphite
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 14)
            .frame(minHeight: RondeReviewDesign.minimumTouchTarget)
            .background(
                RoundedRectangle(cornerRadius: RondeReviewDesign.controlRadius, style: .continuous)
                    .fill(RondeReviewDesign.surface)
                    .overlay { RoundedRectangle(cornerRadius: RondeReviewDesign.controlRadius, style: .continuous).stroke(RondeReviewDesign.borderStrong, lineWidth: 0.8) }
            )
            .opacity(isEnabled ? (configuration.isPressed ? 0.68 : 1) : 0.45)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension Font {
    // Clubhouse uses Avenir Next: the same identity as the selected HTML concept.
    // Relative styles retain the user's text-size preference throughout the library.
    static var rondeBrand: Font { .custom("AvenirNext-Bold", size: 29, relativeTo: .title2) }
    static var rondePageTitle: Font { .custom("AvenirNext-Bold", size: 26, relativeTo: .title2) }
    static var rondeCardTitle: Font { .custom("AvenirNext-DemiBold", size: 21, relativeTo: .title3) }
    static var rondeSectionTitle: Font { .custom("AvenirNext-Bold", size: 18, relativeTo: .headline) }
    static var rondeBody: Font { .custom("AvenirNext-Medium", size: 15, relativeTo: .body) }
    static var rondeLabel: Font { .custom("AvenirNext-DemiBold", size: 14, relativeTo: .subheadline) }
    static var rondeCaption: Font { .custom("AvenirNext-Medium", size: 12, relativeTo: .caption) }
    static var rondeMicro: Font { .custom("AvenirNext-DemiBold", size: 10, relativeTo: .caption2) }
    static var reviewerDisplay: Font { .system(.title, design: .default).weight(.semibold) }
    static var reviewerTitle: Font { .system(.title3, design: .default).weight(.semibold) }
    static var reviewerSection: Font { .system(.subheadline, design: .default).weight(.semibold) }
    static var reviewerTimestamp: Font { .system(.subheadline, design: .monospaced).weight(.medium) }
}
