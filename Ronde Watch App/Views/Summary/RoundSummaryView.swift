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
                VStack(spacing: 6) {
                    Text(round.courseName ?? "Custom Round")
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)

                    Text(round.date, style: .date)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    // Totals row
                    HStack(spacing: 0) {
                        statCell(value: "\(round.totalShots)", label: "Shots")
                        Divider().frame(height: 32)
                        statCell(value: "\(round.totalPar)", label: "Par",
                                 valueColor: .secondary)
                        Divider().frame(height: 32)
                        statCell(value: scoreText, label: "Score",
                                 valueColor: scoreColor)
                    }
                    .padding(.top, 2)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(
                        "\(round.totalShots) shots, par \(round.totalPar), \(accessibilityScoreText)"
                    )
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
                    .accessibilityLabel("Save round and return to history")

                    Button(role: .destructive) {
                        showingDiscardConfirmation = true
                    } label: {
                        Text("Discard")
                            .frame(maxWidth: .infinity)
                    }
                    .accessibilityLabel("Discard this round")
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

    private func statCell(
        value: String,
        label: String,
        valueColor: Color = .primary
    ) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.title3.bold().monospacedDigit())
                .foregroundStyle(valueColor)
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var scoreText: String {
        guard round.totalShots > 0 else { return "–" }
        let score = round.scoreToPar
        if score == 0 { return "E" }
        return score > 0 ? "+\(score)" : "\(score)"
    }

    private var accessibilityScoreText: String {
        guard round.totalShots > 0 else { return "no shots recorded" }
        let score = round.scoreToPar
        if score == 0 { return "even par" }
        return score > 0 ? "\(score) over par" : "\(abs(score)) under par"
    }

    private var scoreColor: Color {
        guard round.totalShots > 0 else { return .secondary }
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
        HStack(spacing: 6) {
            // Hole number
            Text("\(hole.holeNumber)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 18, alignment: .leading)

            // Par
            Text("P\(hole.par)")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Spacer()

            // Shot count
            Text(hole.shots > 0 ? "\(hole.shots)" : "–")
                .font(.body.monospacedDigit().bold())

            // Score badge (pill)
            if hole.shots > 0 {
                Text(hole.scoreLabel)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(badgeTextColor)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(badgeColor.opacity(0.25))
                    )
                    .overlay(
                        Capsule().stroke(badgeColor.opacity(0.5), lineWidth: 0.5)
                    )
                    .accessibilityLabel(hole.scoreLabel == "E" ? "Par" : hole.scoreLabel)
            } else {
                Text("–")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .frame(width: 28, alignment: .center)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(holeAccessibilityLabel)
    }

    private var holeAccessibilityLabel: String {
        guard hole.shots > 0 else {
            return "Hole \(hole.holeNumber), par \(hole.par), no shots"
        }
        let scoreDesc: String
        switch hole.scoreToPar {
        case ...(-2): return "Hole \(hole.holeNumber), eagle or better, \(hole.shots) shots"
        case -1:      scoreDesc = "birdie"
        case 0:       scoreDesc = "par"
        case 1:       scoreDesc = "bogey"
        default:      scoreDesc = "\(hole.scoreToPar) over par"
        }
        return "Hole \(hole.holeNumber), \(scoreDesc), \(hole.shots) shots"
    }

    private var badgeColor: Color {
        switch hole.scoreToPar {
        case ...(-2): return .yellow
        case -1:      return .green
        case 0:       return Color(white: 0.5)
        case 1:       return .orange
        default:      return .red
        }
    }

    private var badgeTextColor: Color {
        // Slightly brighter than the badge fill for legibility
        badgeColor
    }
}

// MARK: - Score legend

private struct ScoreLegend: View {
    private let items: [(label: String, color: Color)] = [
        ("Egl", .yellow),
        ("Bird", .green),
        ("Par", Color(white: 0.5)),
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Score legend: Eagle yellow, Birdie green, Par gray, Bogey orange, Double bogey or worse red")
    }
}
