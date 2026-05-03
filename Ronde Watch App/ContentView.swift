import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Round.date, order: .reverse) private var rounds: [Round]
    @State private var showingSetup = false
    @State private var activeRound: Round?
    /// Set after a round ends so we can show the post-round summary before
    /// returning to the history list. Cleared when the user saves or discards.
    @State private var showingSummaryForRound: Round?

    var body: some View {
        NavigationStack {
            if let round = showingSummaryForRound {
                RoundSummaryView(round: round) {
                    showingSummaryForRound = nil
                    activeRound = nil
                }
            } else if let round = activeRound, !round.isComplete {
                ShotCounterView(
                    round: round,
                    onEndRound: {
                        showingSummaryForRound = activeRound
                    },
                    onDiscard: {
                        activeRound = nil
                    }
                )
            } else {
                roundsList
            }
        }
        .onAppear {
            if activeRound == nil, showingSummaryForRound == nil {
                activeRound = rounds.first { !$0.isComplete }
            }
        }
    }

    private var completedRounds: [Round] {
        rounds.filter(\.isComplete)
    }

    @ViewBuilder
    private var roundsList: some View {
        if completedRounds.isEmpty {
            emptyState
        } else {
            populatedList
        }
    }

    private var emptyState: some View {
        VStack(spacing: 0) {
            NavHeader(title: "Ronde", leading: .none)

            VStack(spacing: 14) {
                Spacer()

                ZStack {
                    Circle()
                        .fill(Theme.fairway.opacity(0.18))
                        .frame(width: 64, height: 64)
                    Image(systemName: Theme.Symbol.golfer)
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(Theme.fairwayBright)
                }

                VStack(spacing: 4) {
                    Text("Tee it up")
                        .font(.titleLarge)
                        .foregroundStyle(Theme.textPrimary)
                    Text("Tap below to start your first round.")
                        .font(.caption)
                        .foregroundStyle(Theme.dimText)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal)

                Spacer()

                PrimaryButton(title: "New Round", icon: Theme.Symbol.pin) {
                    showingSetup = true
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 4)
                .accessibilityLabel("Start a new round")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .fairwayBackground()
        .fairwayContainerBackground()
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showingSetup) {
            StartView { round in
                activeRound = round
                showingSetup = false
            }
        }
    }

    private var populatedList: some View {
        VStack(spacing: 0) {
            NavHeader(title: "Ronde", leading: .none)

            List {
                Section {
                    Button {
                        showingSetup = true
                    } label: {
                        HStack(spacing: 8) {
                            ZStack {
                                Circle()
                                    .fill(Theme.fairway)
                                    .frame(width: 26, height: 26)
                                Image(systemName: Theme.Symbol.pin)
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                            Text("New Round")
                                .font(.bodyEmphasized)
                                .foregroundStyle(Theme.textPrimary)
                            Spacer()
                        }
                    }
                    .buttonStyle(CardRowButtonStyle())
                    .listRowBackground(Theme.cardSurfaceShape)
                    .accessibilityLabel("Start a new round")
                }

                Section {
                    ForEach(completedRounds) { round in
                        NavigationLink {
                            RoundSummaryView(round: round, onDone: nil)
                        } label: {
                            RoundRowView(round: round)
                        }
                        .listRowBackground(Theme.cardSurfaceShape)
                    }
                    .onDelete(perform: deleteRounds)
                } header: {
                    Text("Past Rounds").sectionHeaderStyle()
                }
            }
            .scrollContentBackground(.hidden)
        }
        .background(Theme.surface)
        .fairwayContainerBackground()
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showingSetup) {
            StartView { round in
                activeRound = round
                showingSetup = false
            }
        }
    }

    private func deleteRounds(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(completedRounds[index])
        }
    }
}

private struct RoundRowView: View {
    let round: Round

    var body: some View {
        HStack(spacing: 8) {
            // Score chip
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(scoreColor.opacity(0.18))
                    .frame(width: 36, height: 32)
                Text(scoreShortText)
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(scoreColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(round.courseName ?? "Custom Round")
                    .font(.bodyEmphasized)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.9)
                    .allowsTightening(true)
                HStack(spacing: 4) {
                    Text(round.date, format: .dateTime.month(.abbreviated).day())
                    Text("·")
                    Text("\(round.numberOfHoles)H")
                    Text("·")
                    Text("\(round.totalShots) shots")
                        .monospacedDigit()
                }
                .font(.caption)
                .foregroundStyle(Theme.dimText)
            }

            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(rowAccessibilityLabel)
    }

    private var rowAccessibilityLabel: String {
        let course = round.courseName ?? "Custom Round"
        let score = round.scoreToPar
        let scoreDesc = score == 0 ? "even par"
            : score > 0 ? "\(score) over par"
            : "\(abs(score)) under par"
        return "\(course), \(round.numberOfHoles) holes, \(round.totalShots) shots, \(scoreDesc)"
    }

    private var scoreShortText: String {
        let score = round.scoreToPar
        if score == 0 { return "E" }
        return score > 0 ? "+\(score)" : "\(score)"
    }

    private var scoreColor: Color {
        let score = round.scoreToPar
        if score <= -1 { return Theme.fairwayBright }
        if score == 0  { return Theme.fairway }
        if score <= 5  { return Theme.bunker }
        return Theme.rough
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Round.self, HoleScore.self], inMemory: true)
}
