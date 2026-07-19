import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Round.date, order: .reverse) private var rounds: [Round]

    @State private var showingSetup = false
    @State private var showingActionButtonGuide = false
    @State private var showingSummaryForRound: Round?

    private var activeRound: Round? {
        rounds.first { !$0.isComplete }
    }

    private var completedRounds: [Round] {
        rounds.filter(\.isComplete)
    }

    var body: some View {
        NavigationStack {
            if let round = showingSummaryForRound {
                RoundSummaryView(round: round) {
                    showingSummaryForRound = nil
                }
            } else if let round = activeRound {
                ShotCounterView(
                    round: round,
                    onEndRound: { showingSummaryForRound = round },
                    onDiscard: {}
                )
            } else {
                home
            }
        }
    }

    private var home: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                homeHeader

                if let notice = persistenceRuntime.mode.notice {
                    storageNotice(notice)
                }

                startPanel

                actionButtonSetup

                if !completedRounds.isEmpty {
                    recentRounds
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .fairwayBackground()
        .fairwayContainerBackground()
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showingSetup) {
            StartView { _ in showingSetup = false }
        }
        .sheet(isPresented: $showingActionButtonGuide) {
            ActionButtonGuideView()
        }
    }

    private var homeHeader: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("RONDE")
                .font(.micro)
                .tracking(2.2)
                .foregroundStyle(Theme.fairwayBright)
            Text("Golf, counted.")
                .font(.titleLarge)
                .foregroundStyle(Theme.textPrimary)
            Text("Track every shot without leaving the hole.")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var startPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Quick 9, Quick 18, or choose a Sydney course.")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)

            PrimaryButton(title: "Start Round", icon: Theme.Symbol.golfer) {
                showingSetup = true
            }
            .accessibilityLabel("Start a new golf round")
        }
        .padding(10)
        .cardSurface()
    }

    private var actionButtonSetup: some View {
        Button {
            showingActionButtonGuide = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: Theme.Symbol.actionButton)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.action)
                    .frame(width: 34, height: 34)
                    .background(Theme.action.opacity(0.13), in: RoundedRectangle(cornerRadius: 11))

                VStack(alignment: .leading, spacing: 1) {
                    Text("Use the Action Button")
                        .font(.bodyEmphasized)
                        .foregroundStyle(Theme.textPrimary)
                    Text("Start rounds and log every shot.")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }

                Spacer(minLength: 2)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(Theme.cardSurface)
                    .overlay {
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .stroke(Theme.action.opacity(0.24), lineWidth: 1)
                    }
            )
        }
        .buttonStyle(RondePressStyle())
        .accessibilityLabel("Set up Ronde for the Apple Watch Ultra Action Button")
    }

    private var recentRounds: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent rounds").sectionHeaderStyle()

            ForEach(completedRounds.prefix(5)) { round in
                NavigationLink {
                    RoundSummaryView(round: round, onDone: nil)
                } label: {
                    RoundRowView(round: round)
                        .padding(10)
                        .background(Theme.cardSurfaceShape)
                }
                .buttonStyle(RondePressStyle())
            }
        }
    }

    private func storageNotice(_ message: String) -> some View {
        Label(message, systemImage: "externaldrive.badge.exclamationmark")
            .font(.caption)
            .foregroundStyle(Theme.bunker)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.bunker.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct RoundRowView: View {
    let round: Round

    var body: some View {
        HStack(spacing: 9) {
            Text(Theme.compactScore(round.scoreToPar, hasShots: round.totalShots > 0))
                .font(.scoreNumeral(size: 17))
                .foregroundStyle(scoreColor)
                .frame(width: 38, height: 38)
                .background(scoreColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 11))

            VStack(alignment: .leading, spacing: 2) {
                Text(round.courseName ?? "Quick Round")
                    .font(.bodyEmphasized)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text(metadata)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 2)
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Theme.textTertiary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var metadata: String {
        let holes = round.scoredHoleCount == round.numberOfHoles
            ? "\(round.numberOfHoles) holes"
            : "\(round.scoredHoleCount)/\(round.numberOfHoles) scored"
        return "\(round.date.formatted(.dateTime.month(.abbreviated).day())) · \(holes) · \(round.totalShots) shots"
    }

    private var scoreColor: Color {
        Theme.scoreColor(forDelta: round.scoreToPar, hasShots: round.totalShots > 0)
    }

    private var accessibilitySummary: String {
        let score = round.scoreToPar
        let scoreText = score == 0 ? "even par" : score > 0 ? "\(score) over par" : "\(abs(score)) under par"
        return "\(round.courseName ?? "Quick Round"), \(round.scoredHoleCount) holes scored, \(round.totalShots) shots, \(scoreText)"
    }
}

private struct ActionButtonGuideView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 13) {
                Image(systemName: Theme.Symbol.actionButton)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(Theme.action)
                    .frame(width: 58, height: 58)
                    .background(Theme.action.opacity(0.13), in: RoundedRectangle(cornerRadius: 18))

                VStack(spacing: 4) {
                    Text("One press per shot")
                        .font(.titleSmall)
                    Text("Set Ronde as your workout app on Apple Watch Ultra.")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                }

                VStack(alignment: .leading, spacing: 8) {
                    guideStep("1", "Open Settings on your Watch")
                    guideStep("2", "Action Button → Workout")
                    guideStep("3", "Choose Ronde")
                }
                .padding(11)
                .cardSurface()

                Text("The first press starts your preferred round length. Every press after that logs a shot.")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)

                PrimaryButton(title: "Done", icon: "checkmark") { dismiss() }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .fairwayBackground()
        .fairwayContainerBackground()
    }

    private func guideStep(_ number: String, _ text: String) -> some View {
        HStack(spacing: 8) {
            Text(number)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(Color.black.opacity(0.85))
                .frame(width: 22, height: 22)
                .background(Theme.action, in: Circle())
            Text(text)
                .font(.caption)
                .foregroundStyle(Theme.textPrimary)
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Round.self, HoleScore.self], inMemory: true)
}
