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
                        // Round finished normally — show post-round summary.
                        showingSummaryForRound = activeRound
                    },
                    onDiscard: {
                        // Round was discarded — return straight to history list.
                        activeRound = nil
                    }
                )
            } else {
                roundsList
            }
        }
        .onAppear {
            // Resume any round that was active when the app was last closed.
            if activeRound == nil, showingSummaryForRound == nil {
                activeRound = rounds.first { !$0.isComplete }
            }
        }
    }

    private var completedRounds: [Round] {
        rounds.filter(\.isComplete)
    }

    private var roundsList: some View {
        List {
            Section {
                Button {
                    showingSetup = true
                } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(.green)
                        Text("New Round")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Start a new round")
            }

            if !completedRounds.isEmpty {
                Section("Past Rounds") {
                    ForEach(completedRounds) { round in
                        NavigationLink {
                            RoundSummaryView(round: round, onDone: nil)
                        } label: {
                            RoundRowView(round: round)
                        }
                    }
                    .onDelete(perform: deleteRounds)
                }
            }
        }
        .navigationTitle("Ronde")
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
            // Score indicator — colored circle on the left
            ZStack {
                Circle()
                    .fill(scoreCircleColor.opacity(0.15))
                    .frame(width: 32, height: 32)
                Text(scoreShortText)
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(scoreCircleColor)
            }

            // Course + details
            VStack(alignment: .leading, spacing: 2) {
                Text(round.courseName ?? "Custom Round")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(round.date, format: .dateTime.month(.abbreviated).day())
                    Text("·")
                    Text("\(round.numberOfHoles)H")
                    Text("·")
                    Text("\(round.totalShots)")
                        .monospacedDigit()
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.4))
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

    private var scoreCircleColor: Color {
        let score = round.scoreToPar
        if score <= 0 { return .green }
        if score <= 5 { return .orange }
        return .red
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Round.self, HoleScore.self], inMemory: true)
}
