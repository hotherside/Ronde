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
            // ── Hero header: course + score grid ──
            Section {
                VStack(spacing: 8) {
                    Text(round.courseName ?? "Custom Round")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.center)
                        .lineLimit(1)
                        .accessibilityAddTraits(.isHeader)

                    Text(round.date, format: .dateTime.month(.abbreviated).day())
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)

                    // ── 3-column stat grid ──
                    HStack(spacing: 0) {
                        statColumn(
                            value: "\(round.totalShots)",
                            label: "SHOTS",
                            valueColor: .white,
                            valueSize: 28
                        )

                        // Divider
                        Rectangle()
                            .fill(.white.opacity(0.12))
                            .frame(width: 1, height: 38)

                        statColumn(
                            value: "\(round.totalPar)",
                            label: "PAR",
                            valueColor: .white.opacity(0.45),
                            valueSize: 28
                        )

                        // Divider
                        Rectangle()
                            .fill(.white.opacity(0.12))
                            .frame(width: 1, height: 38)

                        statColumn(
                            value: scoreText,
                            label: "SCORE",
                            valueColor: scoreColor,
                            valueSize: 28
                        )
                    }
                    .padding(.top, 2)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(
                        "\(round.totalShots) shots, par \(round.totalPar), \(accessibilityScoreText)"
                    )

                    // ── Steps + distance row ──
                    if round.totalSteps > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "figure.walk")
                                .font(.system(size: 9))
                            Text("\(round.totalSteps.formatted())")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .monospacedDigit()
                            Text("·")
                            Text("\(String(format: "%.1f", round.totalDistanceKm)) km")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                        }
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.35))
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(
                            "\(round.totalSteps) steps walked, \(String(format: "%.1f", round.totalDistanceKm)) kilometers"
                        )
                    }
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
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Capsule().fill(.green))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Save round and return to history")
                    .listRowBackground(Color.clear)

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

    // MARK: - Stat Column

    private func statColumn(
        value: String,
        label: String,
        valueColor: Color,
        valueSize: CGFloat
    ) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.system(size: valueSize, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(valueColor)
            Text(label)
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.35))
                .tracking(0.8)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Helpers

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
        HStack(spacing: 0) {
            // Hole number — left aligned with color dot
            HStack(spacing: 4) {
                Circle()
                    .fill(badgeColor)
                    .frame(width: 6, height: 6)
                Text("\(hole.holeNumber)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.6))
            }
            .frame(width: 30, alignment: .leading)

            Spacer()

            // Par
            Text("P\(hole.par)")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.3))

            Spacer()

            // Shot count
            Text(hole.shots > 0 ? "\(hole.shots)" : "–")
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)

            Spacer()

            // Score badge
            if hole.shots > 0 {
                Text(hole.scoreLabel)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(badgeColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(badgeColor.opacity(0.15)))
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
