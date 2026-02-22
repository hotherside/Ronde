import SwiftUI

struct HoleTransitionView: View {
    let hole: HoleScore
    let isLastHole: Bool
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Text("Hole \(hole.holeNumber)")
                .font(.caption)
                .foregroundStyle(.secondary)

            // Large shot count
            Text(hole.shots > 0 ? "\(hole.shots)" : "–")
                .font(.system(size: 56, weight: .bold, design: .rounded))
                .monospacedDigit()

            // Score name + badge
            VStack(spacing: 2) {
                Text(scoreName)
                    .font(.caption.bold())
                    .foregroundStyle(scoreColor)
                // Par reference line
                Text("Par \(hole.par)")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                hole.shots > 0
                    ? "\(hole.shots) shots, \(scoreName) on par \(hole.par)"
                    : "No shots recorded"
            )

            Spacer(minLength: 4)

            Button(isLastHole ? "Finish Round" : "Next Hole", action: onContinue)
                .buttonStyle(.borderedProminent)
                .tint(isLastHole ? .green : .blue)
                .accessibilityLabel(isLastHole ? "Finish round" : "Advance to next hole")
        }
        .padding()
        .navigationBarBackButtonHidden(true)
        .task {
            // Auto-advance after 4 seconds so the user can glance and move on.
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
        case 0:       return Color(white: 0.55)
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
