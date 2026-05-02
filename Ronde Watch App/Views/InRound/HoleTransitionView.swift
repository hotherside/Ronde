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

    private var scoreColor: Color {
        Theme.scoreColor(forDelta: hole.scoreToPar, hasShots: hole.shots > 0)
    }

    var body: some View {
        ZStack {
            // ── Top bar ──
            HStack {
                Label("HOLE \(hole.holeNumber)", systemImage: Theme.Symbol.pin)
                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.mutedText)
                    .tracking(1.5)

                Spacer()

                Text("PAR \(hole.par)")
                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.mutedText)
                    .tracking(1.5)
            }
            .padding(.horizontal, 14)
            .padding(.top, 4)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .opacity(contentAppear ? 1 : 0)

            // ── Centre: scorecard ──
            VStack(spacing: 8) {
                // Score name — hero
                Text(scoreName.uppercased())
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundStyle(scoreColor)
                    .tracking(1.5)
                    .multilineTextAlignment(.center)

                // Shots vs par split
                HStack(spacing: 0) {
                    VStack(spacing: 1) {
                        Text("\(hole.shots)")
                            .font(.scoreNumeral(size: 38))
                            .foregroundStyle(Theme.textPrimary)
                        Text("SHOTS")
                            .font(.system(size: 8, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.dimText)
                            .tracking(1)
                    }
                    .frame(maxWidth: .infinity)

                    Rectangle()
                        .fill(Theme.textPrimary.opacity(0.12))
                        .frame(width: 1, height: 42)

                    VStack(spacing: 1) {
                        Text("\(hole.par)")
                            .font(.scoreNumeral(size: 38))
                            .foregroundStyle(Theme.mutedText)
                        Text("PAR")
                            .font(.system(size: 8, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.dimText)
                            .tracking(1)
                    }
                    .frame(maxWidth: .infinity)
                }
                .scaleEffect(statsAppear ? 1.0 : 0.85)
                .opacity(statsAppear ? 1.0 : 0.0)

                if hole.shots > 0 {
                    Text(scoreToParText)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .tracking(1)
                        .foregroundStyle(scoreColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(scoreColor.opacity(0.15)))
                        .opacity(statsAppear ? 1.0 : 0.0)
                }
            }
            .scaleEffect(celebrationScale)

            // ── Bottom action ──
            Button(action: onContinue) {
                HStack(spacing: 6) {
                    Image(systemName: isLastHole ? Theme.Symbol.flag : Theme.Symbol.pin)
                        .font(.system(size: 12, weight: .bold))
                    Text(isLastHole ? "Finish Round" : "Next Hole")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Capsule().fill(Theme.fairway))
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
            Theme.scoreBackdrop(forDelta: hole.scoreToPar, hasShots: hole.shots > 0)
                .ignoresSafeArea()
        }
        .containerBackground(Theme.fairway.gradient, for: .navigation)
        .navigationBarBackButtonHidden(true)
        .task {
            withAnimation(.easeOut(duration: 0.35)) {
                contentAppear = true
            }
            withAnimation(.easeOut(duration: 0.4).delay(0.15)) {
                statsAppear = true
            }
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

            // Auto-advance after 4s
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

    private var scoreName: String {
        guard hole.shots > 0 else { return "—" }
        return Theme.scoreName(forDelta: hole.scoreToPar)
    }
}
