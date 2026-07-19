import SwiftUI

struct HoleTransitionView: View {
    let hole: HoleScore
    let isLastHole: Bool
    let onContinue: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    private var hasScore: Bool { hole.shots > 0 }
    private var scoreColor: Color {
        Theme.scoreColor(forDelta: hole.scoreToPar, hasShots: hasScore)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("HOLE \(hole.holeNumber)", systemImage: Theme.Symbol.pin)
                Spacer()
                Text("PAR \(hole.par)")
            }
            .font(.micro)
            .tracking(1.1)
            .foregroundStyle(Theme.textTertiary)

            Spacer(minLength: 4)

            VStack(spacing: 7) {
                Text(scoreName.uppercased())
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .tracking(1.1)
                    .foregroundStyle(scoreColor)
                    .multilineTextAlignment(.center)

                HStack(spacing: 0) {
                    stat(value: "\(hole.shots)", label: "STROKES", color: Theme.textPrimary)
                    Rectangle()
                        .fill(Theme.separator)
                        .frame(width: 1, height: 38)
                    stat(value: "\(hole.par)", label: "PAR", color: Theme.textSecondary)
                }

                if hasScore {
                    Text(scoreToParText)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .tracking(0.8)
                        .foregroundStyle(scoreColor)
                } else {
                    Text("NOT COUNTED IN ROUND SCORE")
                        .font(.system(size: 8, weight: .semibold, design: .rounded))
                        .tracking(0.6)
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .opacity(appeared ? 1 : 0)
            .scaleEffect(appeared || reduceMotion ? 1 : 0.94)

            Spacer(minLength: 6)

            Button(action: onContinue) {
                HStack(spacing: 6) {
                    Text(isLastHole ? "Finish Round" : "Next Hole")
                        .font(.system(size: 14, weight: .bold))
                    Image(systemName: isLastHole ? Theme.Symbol.flag : "arrow.right")
                        .font(.system(size: 12, weight: .bold))
                }
                .foregroundStyle(Color.black.opacity(0.86))
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(Theme.fairway, in: RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(RondePressStyle())
            .accessibilityLabel(isLastHole ? "Finish round" : "Advance to next hole")
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 7)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            Theme.scoreBackdrop(forDelta: hole.scoreToPar, hasShots: hasScore)
                .ignoresSafeArea()
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.34, dampingFraction: 0.88)) {
                appeared = true
            }
        }
    }

    private func stat(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 0) {
            Text(value)
                .font(.scoreNumeral(size: 36))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 8, weight: .semibold, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    private var scoreToParText: String {
        let delta = hole.scoreToPar
        if delta == 0 { return "EVEN" }
        return delta > 0 ? "+\(delta) OVER" : "\(abs(delta)) UNDER"
    }

    private var scoreName: String {
        guard hasScore else { return "Skipped" }
        return Theme.scoreName(forDelta: hole.scoreToPar)
    }
}
