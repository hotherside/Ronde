import SwiftUI
import SwiftData

struct RoundSummaryView: View {
    @Environment(\.modelContext) private var modelContext
    let round: Round
    /// Non-nil when shown post-round; nil when viewed from history (read-only).
    let onDone: (() -> Void)?

    @State private var showingDiscardConfirmation = false

    private var isPostRound: Bool { onDone != nil }

    var body: some View {
        List {
            // Header: course, date, totals
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
                    HoleScoreRow(hole: hole)
                }
            }

            // Score legend
            Section {
                ScoreLegend()
                    .padding(.vertical, 2)
            }

            // Post-round actions
            if isPostRound {
                Section {
                    Button {
                        round.isComplete = true
                        onDone?()
                    } label: {
                        Text("Save & Done")
                            .frame(maxWidth: .infinity)
                            .fontWeight(.semibold)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)

                    Button(role: .destructive) {
                        showingDiscardConfirmation = true
                    } label: {
                        Text("Discard")
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .navigationTitle(isPostRound ? "Round Complete" : "Round Details")
        .confirmationDialog(
            "Discard this round?",
            isPresented: $showingDiscardConfirmation,
            titleVisibility: .visible
        ) {
            Button("Discard", role: .destructive) {
                modelContext.delete(round)
                onDone?()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Header helpers

    private var scoreText: String {
        guard round.totalShots > 0 else { return "—" }
        let score = round.scoreToPar
        if score == 0 { return "E" }
        return score > 0 ? "+\(score)" : "\(score)"
    }

    private var scoreColor: Color {
        guard round.totalShots > 0 else { return .gray }
        let score = round.scoreToPar
        if score <= 0 { return .green }
        if score <= 5 { return .yellow }
        return .red
    }
}

// MARK: - Per-hole row

private struct HoleScoreRow: View {
    let hole: HoleScore

    var body: some View {
        HStack {
            Text("\(hole.holeNumber)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 20, alignment: .leading)

            Text("P\(hole.par)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Text(hole.shots > 0 ? "\(hole.shots)" : "—")
                .font(.body.monospacedDigit().bold())

            Text(hole.scoreLabel)
                .font(.caption.bold())
                .foregroundStyle(scoreColor)
                .frame(width: 32, alignment: .trailing)
        }
    }

    private var scoreColor: Color {
        guard hole.shots > 0 else { return .gray }
        switch hole.scoreToPar {
        case ...(-2): return .yellow   // Eagle or better
        case -1:      return .green    // Birdie
        case 0:       return .gray     // Par
        case 1:       return .orange   // Bogey
        default:      return .red      // Double bogey or worse
        }
    }
}

// MARK: - Score legend

private struct ScoreLegend: View {
    private let items: [(label: String, color: Color)] = [
        ("Egl", .yellow),
        ("Bird", .green),
        ("Par", .gray),
        ("Bog", .orange),
        ("Dbl+", .red),
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items, id: \.label) { item in
                VStack(spacing: 2) {
                    Circle()
                        .fill(item.color)
                        .frame(width: 6, height: 6)
                    Text(item.label)
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}
