import SwiftUI

struct HoleTransitionView: View {
    let hole: HoleScore
    let isLastHole: Bool
    let onContinue: () -> Void

    @State private var contentAppear = false
    @State private var ringFill = false
    @State private var celebrationBounce: CGFloat = 0.6

    private var isUnderPar: Bool {
        hole.shots > 0 && hole.scoreToPar < 0
    }

    /// Full ring for par or better; shrinks proportionally when over par.
    private var arcProgress: CGFloat {
        guard hole.par > 0, hole.shots > 0 else { return 0 }
        if hole.scoreToPar <= 0 { return 1.0 }
        return min(CGFloat(hole.par) / CGFloat(hole.shots), 0.95)
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── Hole label ──
            Text("HOLE \(hole.holeNumber)")
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundStyle(.white.opacity(0.45))
                .tracking(2)
                .padding(.top, 2)

            Spacer(minLength: 2)

            // ── Score ring ──
            ZStack {
                // Track
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: 6)
                    .frame(width: 100, height: 100)

                // Animated progress arc
                Circle()
                    .trim(from: 0, to: ringFill ? arcProgress : 0)
                    .stroke(
                        scoreColor,
                        style: StrokeStyle(lineWidth: 6, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: 100, height: 100)

                // Inner glow for birdie / eagle
                if isUnderPar {
                    Circle()
                        .fill(scoreColor.opacity(0.1))
                        .frame(width: 88, height: 88)
                        .blur(radius: 10)
                }

                // Center content
                VStack(spacing: 0) {
                    // Score name — BIRDIE, PAR, BOGEY …
                    Text(scoreName)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(scoreColor)
                        .tracking(1.2)

                    // Shot count — hero number
                    Text(hole.shots > 0 ? "\(hole.shots)" : "–")
                        .font(.system(size: 38, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.vertical, -4)

                    // Score-to-par badge
                    if hole.shots > 0 {
                        Text(scoreToParText)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(scoreColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(scoreColor.opacity(0.12)))
                    }
                }
                .scaleEffect(contentAppear ? 1.0 : 0.6)
                .opacity(contentAppear ? 1.0 : 0.0)
            }
            .scaleEffect(celebrationBounce)

            // Par reference — small, outside the ring
            Text("Par \(hole.par)")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.3))
                .padding(.top, 4)

            Spacer(minLength: 6)

            // ── Action button — custom capsule ──
            Button(action: onContinue) {
                Text(isLastHole ? "Finish Round" : "Next Hole")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        Capsule()
                            .fill(isLastHole ? Color.green : Color.blue)
                    )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.bottom, 4)
            .accessibilityLabel(isLastHole ? "Finish round" : "Advance to next hole")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            Rectangle()
                .fill(
                    RadialGradient(
                        colors: [
                            scoreColor.opacity(0.2),
                            scoreColor.opacity(0.06),
                            .clear,
                        ],
                        center: .center,
                        startRadius: 10,
                        endRadius: 140
                    )
                )
                .ignoresSafeArea()
        }
        .navigationBarBackButtonHidden(true)
        .task {
            // 1. Content fades / scales in
            withAnimation(.easeOut(duration: 0.35)) {
                contentAppear = true
            }

            // 2. Arc fills in (slightly delayed)
            withAnimation(.easeOut(duration: 0.6).delay(0.15)) {
                ringFill = true
            }

            // 3. Celebration bounce for under-par scores
            if isUnderPar {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.45).delay(0.25)) {
                    celebrationBounce = 1.06
                }
                try? await Task.sleep(for: .milliseconds(450))
                withAnimation(.spring(response: 0.3, dampingFraction: 0.65)) {
                    celebrationBounce = 1.0
                }
            } else {
                withAnimation(.easeOut(duration: 0.35)) {
                    celebrationBounce = 1.0
                }
            }

            // Auto-advance after 4 s
            try? await Task.sleep(for: .seconds(4))
            if !Task.isCancelled {
                onContinue()
            }
        }
    }

    // MARK: - Helpers

    private var scoreToParText: String {
        let diff = hole.scoreToPar
        if diff == 0 { return "E" }
        return diff > 0 ? "+\(diff)" : "\(diff)"
    }

    private var scoreColor: Color {
        guard hole.shots > 0 else { return .secondary }
        switch hole.scoreToPar {
        case ...(-2): return .yellow
        case -1:      return .green
        case 0:       return .green
        case 1:       return .orange
        default:      return .red
        }
    }

    private var scoreName: String {
        guard hole.shots > 0 else { return "–" }
        switch hole.scoreToPar {
        case ...(-3): return "ALBATROSS"
        case -2:      return "EAGLE"
        case -1:      return "BIRDIE"
        case 0:       return "PAR"
        case 1:       return "BOGEY"
        case 2:       return "DOUBLE"
        default:      return "+\(hole.scoreToPar)"
        }
    }
}
