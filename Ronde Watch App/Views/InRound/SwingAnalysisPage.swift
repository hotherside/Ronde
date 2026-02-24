import SwiftUI

/// Full-screen page showing the current hole's swing data.
///
/// Displayed as page 2 in the in-round `TabView`. The user scrolls
/// here via the Digital Crown to review swing metrics mid-hole.
struct SwingAnalysisPage: View {
    let hole: HoleScore

    var body: some View {
        if hole.swingData.isEmpty {
            emptyState
        } else {
            swingContent
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()

            Image(systemName: "waveform.path")
                .font(.system(size: 28))
                .foregroundStyle(.white.opacity(0.15))

            Text("No swings detected")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.3))

            Text("Swings appear here automatically")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.15))

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Swing Content

    private var swingContent: some View {
        ScrollView {
            VStack(spacing: 10) {
                // ── Header ──
                HStack {
                    Text("HOLE \(hole.holeNumber)")
                        .font(.system(size: 9, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white.opacity(0.4))
                        .tracking(1.5)
                    Spacer()
                    Text("\(hole.swingCount) SWING\(hole.swingCount == 1 ? "" : "S")")
                        .font(.system(size: 9, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white.opacity(0.4))
                        .tracking(1.5)
                }
                .padding(.horizontal, 4)

                // ── Stats row: avg | best ──
                HStack(spacing: 0) {
                    VStack(spacing: 0) {
                        Text(String(format: "%.0f", hole.averageSpeedKMH))
                            .font(.system(size: 20, weight: .heavy, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.cyan)
                        Text("AVG KM/H")
                            .font(.system(size: 7, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.3))
                            .tracking(0.8)
                    }
                    .frame(maxWidth: .infinity)

                    Rectangle()
                        .fill(.white.opacity(0.12))
                        .frame(width: 1, height: 26)

                    VStack(spacing: 0) {
                        Text(String(format: "%.0f", hole.fastestSpeedKMH))
                            .font(.system(size: 20, weight: .heavy, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.green)
                        Text("BEST KM/H")
                            .font(.system(size: 7, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.3))
                            .tracking(0.8)
                    }
                    .frame(maxWidth: .infinity)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(
                    "Average speed \(String(format: "%.0f", hole.averageSpeedKMH)) kilometres per hour, "
                    + "best \(String(format: "%.0f", hole.fastestSpeedKMH)) kilometres per hour"
                )

                // ── Per-swing list ──
                ForEach(Array(hole.swingData.enumerated()), id: \.element.id) { index, swing in
                    SwingRow(index: index + 1, metrics: swing)
                }
            }
            .padding(.horizontal, 6)
            .padding(.top, 4)
            .padding(.bottom, 16)
        }
    }
}

// MARK: - Swing Row

private struct SwingRow: View {
    let index: Int
    let metrics: SwingMetrics

    var body: some View {
        HStack(spacing: 8) {
            // Swing number
            Text("#\(index)")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.4))
                .frame(width: 20, alignment: .leading)

            // Mini arc
            SwingArcView(
                normalizedForce: metrics.normalizedForce,
                diameter: 30
            )

            // Speed
            VStack(alignment: .leading, spacing: 0) {
                Text("\(metrics.estimatedSpeedFormatted) km/h")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                HStack(spacing: 4) {
                    Text(metrics.peakGFormatted)
                        .foregroundStyle(.cyan.opacity(0.6))
                    Text("·")
                    Text(metrics.tempoFormatted)
                        .foregroundStyle(.green.opacity(0.6))
                }
                .font(.system(size: 9, weight: .medium, design: .rounded))
            }

            Spacer()
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.white.opacity(0.04))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Swing \(index), \(metrics.estimatedSpeedFormatted) kilometres per hour, "
            + "\(metrics.peakGFormatted), tempo \(metrics.tempoFormatted)"
        )
    }
}

// MARK: - Previews

#Preview("With Swings") {
    let hole = HoleScore(holeNumber: 3, par: 4)
    hole.shots = 4
    hole.swingData = [
        SwingMetrics(id: UUID(), timestamp: .now, peakG: 12.3, estimatedSpeedMPS: 8.5, tempoSeconds: 0.24, accelerationProfile: []),
        SwingMetrics(id: UUID(), timestamp: .now, peakG: 18.7, estimatedSpeedMPS: 12.0, tempoSeconds: 0.18, accelerationProfile: []),
        SwingMetrics(id: UUID(), timestamp: .now, peakG: 10.1, estimatedSpeedMPS: 7.2, tempoSeconds: 0.30, accelerationProfile: []),
    ]
    return SwingAnalysisPage(hole: hole)
        .background(.black)
}

#Preview("Empty") {
    SwingAnalysisPage(hole: HoleScore(holeNumber: 1, par: 4))
        .background(.black)
}
