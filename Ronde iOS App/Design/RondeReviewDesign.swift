import SwiftUI

/// The reviewer is intentionally separate from the watch's OLED field
/// instrument theme. It is a calm, light workspace for studying video.
enum RondeReviewDesign {
    static let canvas = Color(red: 0.966, green: 0.958, blue: 0.932)
    static let surface = Color(red: 0.995, green: 0.991, blue: 0.977)
    static let surfaceRaised = Color(red: 0.982, green: 0.974, blue: 0.946)
    static let graphite = Color(red: 0.075, green: 0.180, blue: 0.135)
    static let graphiteMuted = Color(red: 0.285, green: 0.370, blue: 0.315)
    static let graphiteFaint = Color(red: 0.445, green: 0.515, blue: 0.460)
    static let border = Color(red: 0.240, green: 0.315, blue: 0.265).opacity(0.14)
    static let borderStrong = Color(red: 0.190, green: 0.270, blue: 0.220).opacity(0.25)
    static let fairway = Color(red: 0.095, green: 0.285, blue: 0.205)
    static let fairwayBright = Color(red: 0.330, green: 0.555, blue: 0.420)
    static let fairwayWash = Color(red: 0.855, green: 0.908, blue: 0.856)
    static let amber = Color(red: 0.510, green: 0.390, blue: 0.165)
    static let amberWash = Color(red: 0.949, green: 0.907, blue: 0.795)
    static let tracerPurple = Color(red: 0.570, green: 0.280, blue: 0.980)
    static let tracerPurpleSoft = Color(red: 0.740, green: 0.580, blue: 1.000)
    static let tracerPurpleWash = Color(red: 0.930, green: 0.895, blue: 1.000)
    static let red = Color(red: 0.705, green: 0.175, blue: 0.160)
    static let redWash = Color(red: 0.990, green: 0.900, blue: 0.895)
    /// Kept as a semantic compatibility name for existing controls; visually
    /// it is eucalyptus rather than productivity-app blue.
    static let blue = Color(red: 0.225, green: 0.405, blue: 0.315)
    static let blueWash = Color(red: 0.875, green: 0.920, blue: 0.870)

    // The reviewer is deliberately quieter than the Watch instrument. A
    // small family of radii keeps the source footage, rather than chrome,
    // as the visual anchor.
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
            .font(.caption.weight(.semibold))
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
    static var reviewerSection: Font { .system(.caption2, design: .default).weight(.bold) }
    static var reviewerTimestamp: Font { .system(.footnote, design: .monospaced).weight(.semibold) }
}
