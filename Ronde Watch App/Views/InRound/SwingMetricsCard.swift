import SwiftUI

/// Compact overlay showing swing metrics with an animated arc ring.
///
/// Displayed for ~3.5 seconds after each detected swing, then auto-dismissed.
/// Layout: arc ring (90pt) with peak-g in the centre, speed + tempo below.
struct SwingMetricsCard: View {
    let metrics: SwingMetrics

    @State private var appeared = false
    @State private var statsAppeared = false

    var body: some View {
        VStack(spacing: 4) {
            // ── Arc ring with peak-g hero number ──
            ZStack {
                SwingArcView(
                    normalizedForce: metrics.normalizedForce,
                    diameter: 90
                )

                // Centre: peak g-force
                VStack(spacing: 0) {
                    Text(String(format: "%.1f", metrics.peakG))
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                    Text("G-FORCE")
                        .font(.system(size: 7, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.4))
                        .tracking(1)
                }
                .opacity(statsAppeared ? 1 : 0)
                .scaleEffect(statsAppeared ? 1 : 0.8)
            }

            // ── Bottom stats: speed + tempo ──
            HStack(spacing: 12) {
                // Estimated speed (km/h)
                VStack(spacing: 0) {
                    Text(metrics.estimatedSpeedFormatted)
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.cyan)
                    Text("EST. KM/H")
                        .font(.system(size: 7, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.3))
                        .tracking(0.8)
                }

                // Divider
                Rectangle()
                    .fill(.white.opacity(0.12))
                    .frame(width: 1, height: 20)

                // Tempo
                VStack(spacing: 0) {
                    Text(metrics.tempoFormatted)
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.green)
                    Text("TEMPO")
                        .font(.system(size: 7, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.3))
                        .tracking(0.8)
                }
            }
            .opacity(statsAppeared ? 1 : 0)
            .offset(y: statsAppeared ? 0 : 6)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .opacity(0.85)
        )
        .scaleEffect(appeared ? 1 : 0.7)
        .opacity(appeared ? 1 : 0)
        .task {
            // Staggered entrance: card springs in, then stats fade in
            withAnimation(.spring(response: 0.35, dampingFraction: 0.65)) {
                appeared = true
            }
            withAnimation(.easeOut(duration: 0.3).delay(0.2)) {
                statsAppeared = true
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Swing detected. Peak force \(metrics.peakGFormatted), "
            + "estimated speed \(metrics.estimatedSpeedFormatted) kilometres per hour, "
            + "tempo \(metrics.tempoFormatted)"
        )
    }
}

// MARK: - Previews

#Preview("Metrics Card — Light Swing") {
    SwingMetricsCard(metrics: SwingMetrics(
        id: UUID(),
        timestamp: .now,
        peakG: 10.2,
        estimatedSpeedMPS: 8.0,
        tempoSeconds: 0.32,
        accelerationProfile: (0..<60).map { Double($0) / 60.0 * 10.2 }
    ))
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(.black)
}

#Preview("Metrics Card — Power Swing") {
    SwingMetricsCard(metrics: SwingMetrics(
        id: UUID(),
        timestamp: .now,
        peakG: 22.5,
        estimatedSpeedMPS: 28.0,
        tempoSeconds: 0.18,
        accelerationProfile: (0..<60).map { Double($0) / 60.0 * 22.5 }
    ))
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(.black)
}
