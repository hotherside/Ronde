import SwiftUI

struct HoleTransitionView: View {
    let hole: HoleScore
    let isLastHole: Bool
    let onContinue: () -> Void

    @State private var contentAppear = false
    @State private var statsAppear = false
    @State private var celebrationScale: CGFloat = 0.7

    private var isUnderPar: Bool {
        hole.shots > 0 && hole.scoreToPar < 0
    }

    var body: some View {
        ZStack {
            // ── Top: hole + par in a compact bar ──
            HStack {
                Text("HOLE \(hole.holeNumber)")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white.opacity(0.4))
                    .tracking(1.5)

                Spacer()

                Text("PAR \(hole.par)")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white.opacity(0.4))
                    .tracking(1.5)
            }
            .padding(.horizontal, 14)
            .padding(.top, 4)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .opacity(contentAppear ? 1 : 0)

            // ── Center: score card ──
            VStack(spacing: 6) {
                // Score name — hero label
                Text(scoreName)
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                    .foregroundStyle(scoreColor)
                    .tracking(1)

                // Two-column stat grid: shots vs par
                HStack(spacing: 0) {
                    // Shots column
                    VStack(spacing: 1) {
                        Text("\(hole.shots)")
                            .font(.system(size: 36, weight: .heavy, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                        Text("SHOTS")
                            .font(.system(size: 8, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.35))
                            .tracking(1)
                    }
                    .frame(maxWidth: .infinity)

                    // Divider
                    Rectangle()
                        .fill(.white.opacity(0.12))
                        .frame(width: 1, height: 40)

                    // Par column
                    VStack(spacing: 1) {
                        Text("\(hole.par)")
                            .font(.system(size: 36, weight: .heavy, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white.opacity(0.4))
                        Text("PAR")
                            .font(.system(size: 8, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.35))
                            .tracking(1)
                    }
                    .frame(maxWidth: .infinity)
                }
                .scaleEffect(statsAppear ? 1.0 : 0.85)
                .opacity(statsAppear ? 1.0 : 0.0)

                // Score-to-par badge
                if hole.shots > 0 {
                    Text(scoreToParText)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(scoreColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(scoreColor.opacity(0.12)))
                        .opacity(statsAppear ? 1.0 : 0.0)
                }
            }
            .scaleEffect(celebrationScale)

            // ── Bottom: action button ──
            Button(action: onContinue) {
                Text(isLastHole ? "Finish Round" : "Next Hole")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(isLastHole ? Color.green : Color.blue))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 14)
            .padding(.bottom, 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .opacity(contentAppear ? 1 : 0)
            .accessibilityLabel(isLastHole ? "Finish round" : "Advance to next hole")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            Rectangle()
                .fill(
                    RadialGradient(
                        colors: [
                            scoreColor.opacity(0.22),
                            scoreColor.opacity(0.06),
                            .clear,
                        ],
                        center: .center,
                        startRadius: 5,
                        endRadius: 150
                    )
                )
                .ignoresSafeArea()
        }
        .navigationBarBackButtonHidden(true)
        .task {
            // Staggered entrance
            withAnimation(.easeOut(duration: 0.35)) {
                contentAppear = true
            }

            withAnimation(.easeOut(duration: 0.4).delay(0.15)) {
                statsAppear = true
            }

            // Celebration bounce for under-par
            if isUnderPar {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.4).delay(0.2)) {
                    celebrationScale = 1.05
                }
                try? await Task.sleep(for: .milliseconds(500))
                withAnimation(.spring(response: 0.3, dampingFraction: 0.65)) {
                    celebrationScale = 1.0
                }
            } else {
                withAnimation(.easeOut(duration: 0.35)) {
                    celebrationScale = 1.0
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
        if diff == 0 { return "EVEN" }
        return diff > 0 ? "+\(diff) OVER" : "\(diff) UNDER"
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
