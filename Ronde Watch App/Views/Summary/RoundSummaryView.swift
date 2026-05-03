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
                    HStack(spacing: 4) {
                        Image(systemName: Theme.Symbol.course)
                            .font(.system(size: 9))
                            .foregroundStyle(Theme.fairwayBright)
                        Text(round.courseName ?? "Custom Round")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.textPrimary)
                            .multilineTextAlignment(.center)
                            .lineLimit(1)
                    }
                    .accessibilityAddTraits(.isHeader)

                    Text(round.date, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.dimText)

                    HStack(spacing: 0) {
                        statColumn(
                            value: "\(round.totalShots)",
                            label: "SHOTS",
                            valueColor: Theme.textPrimary,
                            valueSize: 28
                        )

                        Rectangle()
                            .fill(Theme.textPrimary.opacity(0.12))
                            .frame(width: 1, height: 38)

                        statColumn(
                            value: "\(round.totalPar)",
                            label: "PAR",
                            valueColor: Theme.mutedText,
                            valueSize: 28
                        )

                        Rectangle()
                            .fill(Theme.textPrimary.opacity(0.12))
                            .frame(width: 1, height: 38)

                        statColumn(
                            value: scoreText,
                            label: "VS PAR",
                            valueColor: scoreColor,
                            valueSize: 28
                        )
                    }
                    .padding(.top, 2)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(
                        "\(round.totalShots) shots, par \(round.totalPar), \(accessibilityScoreText)"
                    )

                    // Steps + distance
                    if round.totalSteps > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: Theme.Symbol.walking)
                                .font(.system(size: 9))
                            Text("\(round.totalSteps.formatted())")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .monospacedDigit()
                            Text("·")
                            Text("\(String(format: "%.1f", round.totalDistanceKm)) km")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                        }
                        .foregroundStyle(Theme.dimText)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(
                            "\(round.totalSteps) steps walked, \(String(format: "%.1f", round.totalDistanceKm)) kilometers"
                        )
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .listRowBackground(cardBackground)
            }

            // ── Per-hole scorecard ──
            Section {
                ForEach(round.sortedHoleScores) { hole in
                    HoleScoreRow(hole: hole)
                        .listRowBackground(cardBackground)
                }
            } header: {
                Text("Scorecard").sectionHeaderStyle()
            }

            // ── Score legend ──
            Section {
                ScoreLegend()
                    .padding(.vertical, 2)
                    .listRowBackground(cardBackground)
            }

            // ── Post-round actions ──
            if isPostRound {
                Section {
                    Button {
                        round.isComplete = true
                        onDone?()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 13))
                            Text("Save Round")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(Theme.fairway))
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
        .scrollContentBackground(.hidden)
        .background(Theme.surface)
        .containerBackground(Theme.fairway.gradient, for: .navigation)
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

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Theme.cardSurface)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Theme.textPrimary.opacity(0.05), lineWidth: 1)
            )
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
                .font(.scoreNumeral(size: valueSize))
                .foregroundStyle(valueColor)
            Text(label)
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.dimText)
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
        guard round.totalShots > 0 else { return Theme.mutedText }
        let score = round.scoreToPar
        if score <= -1 { return Theme.fairwayBright }
        if score == 0  { return Theme.fairway }
        if score <= 5  { return Theme.bunker }
        return Theme.rough
    }
}

// MARK: - Per-hole row

private struct HoleScoreRow: View {
    let hole: HoleScore

    var body: some View {
        HStack(spacing: 6) {
            // Coloured dot + hole number
            HStack(spacing: 5) {
                Circle()
                    .fill(badgeColor)
                    .frame(width: 6, height: 6)
                Text("\(hole.holeNumber)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textSecondary)
            }
            .frame(width: 30, alignment: .leading)

            Spacer(minLength: 4)

            // Par
            Text("P\(hole.par)")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.dimText)

            Spacer(minLength: 4)

            // Shot count
            Text(hole.shots > 0 ? "\(hole.shots)" : "–")
                .font(.scoreNumeral(size: 16))
                .foregroundStyle(Theme.textPrimary)

            Spacer(minLength: 4)

            // Score badge
            if hole.shots > 0 {
                Text(hole.scoreLabel)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(badgeColor)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(badgeColor.opacity(0.18)))
                    .accessibilityLabel(hole.scoreLabel == "E" ? "Par" : hole.scoreLabel)
            } else {
                Text("–")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.faintText)
                    .frame(width: 28, alignment: .center)
            }

            // Walking distance (only for completed holes with non-trivial walk)
            Text(distanceText)
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Theme.faintText)
                .frame(width: 36, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(holeAccessibilityLabel)
    }

    private var distanceText: String {
        let metres = hole.distanceMeters
        guard metres >= 1 else { return "" }
        if metres >= 1000 {
            return String(format: "%.1fkm", metres / 1000)
        }
        return "\(Int(metres.rounded()))m"
    }

    private var holeAccessibilityLabel: String {
        let walkSuffix = distanceText.isEmpty ? "" : ", walked \(distanceText)"
        guard hole.shots > 0 else {
            return "Hole \(hole.holeNumber), par \(hole.par), no shots\(walkSuffix)"
        }
        return "Hole \(hole.holeNumber), \(Theme.scoreName(forDelta: hole.scoreToPar)), \(hole.shots) shots\(walkSuffix)"
    }

    private var badgeColor: Color {
        Theme.scoreColor(forDelta: hole.scoreToPar)
    }
}

// MARK: - Score legend

private struct ScoreLegend: View {
    private let items: [(label: String, color: Color)] = [
        ("Egl", Theme.eagleGold),
        ("Bird", Theme.fairwayBright),
        ("Par", Theme.fairway),
        ("Bog", Theme.bunker),
        ("Dbl+", Theme.rough),
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
                        .foregroundStyle(Theme.dimText)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Score legend: Eagle gold, Birdie bright green, Par green, Bogey amber, Double bogey or worse red")
    }
}
