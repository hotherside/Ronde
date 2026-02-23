import SwiftUI

struct HoleTransitionView: View {
    let hole: HoleScore
    let isLastHole: Bool
    let onContinue: () -> Void

    @State private var appearAnimation = false

    private var progress: CGFloat {
        guard hole.par > 0, hole.shots > 0 else { return 0 }
        return min(CGFloat(hole.shots) / CGFloat(hole.par), 1.0)
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("HOLE \(hole.holeNumber)")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .tracking(1)

            Spacer(minLength: 0)

            // Ring + score
            ZStack {
                // Track
                Circle()
                    .stroke(Color.white.opacity(0.07), lineWidth: 5)
                    .frame(width: 110, height: 110)

                // Progress arc — animates in
                Circle()
                    .trim(from: 0, to: appearAnimation ? progress : 0)
                    .stroke(
                        scoreColor,
                        style: StrokeStyle(lineWidth: 5, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: 110, height: 110)

                VStack(spacing: 2) {
                    // Score name — hero
                    Text(scoreName)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(scoreColor)

                    // Shot count
                    Text(hole.shots > 0 ? "\(hole.shots)" : "–")
                        .font(.system(size: 40, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)

                    // Par reference
                    Text("Par \(hole.par)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.35))
                }
                .scaleEffect(appearAnimation ? 1.0 : 0.8)
                .opacity(appearAnimation ? 1.0 : 0.0)
            }

            Spacer(minLength: 0)

            Button(action: onContinue) {
                Text(isLastHole ? "Finish Round" : "Next Hole")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(isLastHole ? .green : .blue)
            .listRowBackground(Color.clear)
            .accessibilityLabel(isLastHole ? "Finish round" : "Advance to next hole")
        }
        .padding(.horizontal, 6)
        .padding(.top, 2)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RadialGradient(
                colors: [scoreColor.opacity(0.15), scoreColor.opacity(0.04), .clear],
                center: .center,
                startRadius: 10,
                endRadius: 140
            )
            .ignoresSafeArea()
        )
        .navigationBarBackButtonHidden(true)
        .task {
            // Animate in
            withAnimation(.easeOut(duration: 0.6)) {
                appearAnimation = true
            }
            // Auto-advance after 4 seconds
            try? await Task.sleep(for: .seconds(4))
            if !Task.isCancelled {
                onContinue()
            }
        }
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
        case ...(-3): return "Albatross"
        case -2:      return "Eagle"
        case -1:      return "Birdie"
        case 0:       return "Par"
        case 1:       return "Bogey"
        case 2:       return "Double"
        default:      return "+\(hole.scoreToPar)"
        }
    }
}
