import SwiftUI

/// The reviewer is intentionally separate from the watch's OLED field
/// instrument theme. It is a calm, light workspace for studying video.
enum RondeReviewDesign {
    static let canvas = Color(red: 0.975, green: 0.975, blue: 0.980)
    static let surface = Color.white
    static let surfaceRaised = Color.white
    static let graphite = Color(red: 0.10, green: 0.10, blue: 0.12)
    static let graphiteMuted = Color(red: 0.36, green: 0.36, blue: 0.40)
    static let graphiteFaint = Color(red: 0.43, green: 0.43, blue: 0.47)
    static let border = Color.black.opacity(0.08)
    static let borderStrong = Color.black.opacity(0.16)
    static let fairway = graphite
    static let fairwayBright = Color(red: 0.41, green: 0.35, blue: 0.85)
    static let fairwayWash = Color(red: 0.94, green: 0.93, blue: 0.99)
    static let amber = Color(red: 0.510, green: 0.390, blue: 0.165)
    static let amberWash = Color(red: 0.949, green: 0.907, blue: 0.795)
    static let tracerPurple = Color(red: 0.570, green: 0.280, blue: 0.980)
    static let tracerPurpleSoft = Color(red: 0.740, green: 0.580, blue: 1.000)
    static let tracerPurpleWash = Color(red: 0.930, green: 0.895, blue: 1.000)
    static let red = Color(red: 0.705, green: 0.175, blue: 0.160)
    static let redWash = Color(red: 0.990, green: 0.900, blue: 0.895)
    static let blue = Color(red: 0.36, green: 0.30, blue: 0.76)
    static let blueWash = Color(red: 0.94, green: 0.93, blue: 0.99)

    static let smallRadius: CGFloat = 7
    static let cardRadius: CGFloat = 11
    static let largeRadius: CGFloat = 15

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
            if #available(iOS 26.0, *) {
                self.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
            } else {
                self.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }
        } else {
            self
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

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 16)
            .frame(minHeight: 46)
            .background(tint.opacity(configuration.isPressed ? 0.82 : 1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

struct ReviewSecondaryButtonStyle: ButtonStyle {
    var tint: Color = RondeReviewDesign.graphite
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(RondeReviewDesign.surface)
                    .overlay { RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(RondeReviewDesign.borderStrong, lineWidth: 0.8) }
            )
            .opacity(configuration.isPressed ? 0.68 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension Font {
    // Semantic styles retain Dynamic Type while keeping the reviewer compact.
    // The previous fixed 34/25 point display styles made the home surface feel
    // like a marketing landing page and overflowed quickly with larger text.
    static var reviewerDisplay: Font { .system(.title, design: .default).weight(.semibold) }
    static var reviewerTitle: Font { .system(.title3, design: .default).weight(.semibold) }
    static var reviewerSection: Font { .system(.subheadline, design: .default).weight(.semibold) }
    static var reviewerTimestamp: Font { .system(.subheadline, design: .monospaced).weight(.medium) }
}
