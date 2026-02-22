import SwiftUI

struct HoleTransitionView: View {
    let hole: HoleScore
    let isLastHole: Bool
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Text("Hole \(hole.holeNumber)")
                .font(.headline)

            HStack(spacing: 16) {
                VStack {
                    Text("\(hole.shots)")
                        .font(.title.bold())
                    Text("Shots")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                VStack {
                    Text("\(hole.par)")
                        .font(.title.bold())
                        .foregroundStyle(.secondary)
                    Text("Par")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                VStack {
                    Text(hole.scoreLabel)
                        .font(.title.bold())
                        .foregroundStyle(scoreColor)
                    Text("Score")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Button(isLastHole ? "Finish Round" : "Next Hole", action: onContinue)
                .buttonStyle(.borderedProminent)
                .tint(isLastHole ? .green : .blue)
                .padding(.top, 4)
        }
        .padding()
        .navigationBarBackButtonHidden(true)
        .task {
            try? await Task.sleep(for: .seconds(3))
            if !Task.isCancelled {
                onContinue()
            }
        }
    }

    private var scoreColor: Color {
        let diff = hole.scoreToPar
        if diff <= 0 { return .green }
        if diff <= 2 { return .yellow }
        return .red
    }
}
