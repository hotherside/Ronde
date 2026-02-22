import SwiftUI

struct RoundSummaryView: View {
    let round: Round
    let isPostRound: Bool

    var body: some View {
        List {
            // Header
            Section {
                VStack(spacing: 4) {
                    Text(round.courseName ?? "Custom Round")
                        .font(.headline)
                    Text(round.date, style: .date)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 16) {
                        VStack {
                            Text("\(round.totalShots)")
                                .font(.title2.bold())
                            Text("Shots")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        VStack {
                            Text("\(round.totalPar)")
                                .font(.title2.bold())
                                .foregroundStyle(.secondary)
                            Text("Par")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        VStack {
                            Text(scoreText)
                                .font(.title2.bold())
                                .foregroundStyle(scoreColor)
                            Text("Score")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity)
            }

            // Per-hole breakdown
            Section("Holes") {
                ForEach(round.sortedHoleScores) { hole in
                    HStack {
                        Text("\(hole.holeNumber)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 20, alignment: .leading)

                        Text("Par \(hole.par)")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Spacer()

                        Text("\(hole.shots)")
                            .font(.body.monospacedDigit().bold())

                        Text(hole.scoreLabel)
                            .font(.caption.bold())
                            .foregroundStyle(holeScoreColor(for: hole))
                            .frame(width: 30, alignment: .trailing)
                    }
                }
            }
        }
        .navigationTitle(isPostRound ? "Round Complete" : "Round Details")
    }

    private var scoreText: String {
        let score = round.scoreToPar
        if score == 0 { return "E" }
        return score > 0 ? "+\(score)" : "\(score)"
    }

    private var scoreColor: Color {
        let score = round.scoreToPar
        if score <= 0 { return .green }
        if score <= 5 { return .yellow }
        return .red
    }

    private func holeScoreColor(for hole: HoleScore) -> Color {
        let diff = hole.scoreToPar
        if diff < 0 { return .green }
        if diff == 0 { return .green.opacity(0.7) }
        if diff <= 2 { return .yellow }
        return .red
    }
}
