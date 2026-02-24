import SwiftUI

/// Circular gauge arc that fills proportionally to swing force.
///
/// Draws a 270° arc (gap at the bottom) using `Circle().trim()`.
/// Background track shows the full range; foreground fills to `normalizedValue`.
/// Animated on appear with a spring for satisfying overshoot.
struct SwingArcView: View {
    /// 0.0 (minimum threshold) to 1.0 (maximum force). Controls arc fill.
    let normalizedValue: Double
    /// Outer diameter of the ring in points.
    let diameter: CGFloat

    @State private var animatedTrim: CGFloat = 0

    /// Arc fill: normalizedValue mapped to 75% of a full circle (270°).
    private var trimEnd: CGFloat {
        CGFloat(normalizedValue) * 0.75
    }

    private let lineWidth: CGFloat = 6

    /// Gradient from blue (low) → cyan (mid) → green (high force).
    private var arcGradient: AngularGradient {
        AngularGradient(
            gradient: Gradient(colors: [
                .blue,
                .cyan,
                .green,
            ]),
            center: .center,
            startAngle: .degrees(135),
            endAngle: .degrees(135 + 270 * normalizedValue)
        )
    }

    var body: some View {
        ZStack {
            // Background track — full 270° arc, subtle
            Circle()
                .trim(from: 0, to: 0.75)
                .stroke(
                    Color.white.opacity(0.08),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(135))

            // Foreground arc — fills to normalizedValue
            Circle()
                .trim(from: 0, to: animatedTrim)
                .stroke(
                    arcGradient,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(135))
        }
        .frame(width: diameter, height: diameter)
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.1)) {
                animatedTrim = trimEnd
            }
        }
    }
}

// MARK: - Previews

#Preview("Arc Forces") {
    VStack(spacing: 16) {
        HStack(spacing: 12) {
            SwingArcView(normalizedValue: 0.2, diameter: 70)
            SwingArcView(normalizedValue: 0.5, diameter: 70)
        }
        HStack(spacing: 12) {
            SwingArcView(normalizedValue: 0.8, diameter: 70)
            SwingArcView(normalizedValue: 1.0, diameter: 70)
        }
    }
    .padding()
    .background(.black)
}
