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
                ShotCounterView(round: round) {
                    // Round ended (last hole completed or early save).
                    // Show the post-round summary before returning to history.
                    showingSummaryForRound = activeRound
                }
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
                    Label("New Round", systemImage: "plus.circle.fill")
                }
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
        VStack(alignment: .leading, spacing: 2) {
            Text(round.courseName ?? "Custom Round")
                .font(.headline)
                .lineLimit(1)
            HStack(spacing: 4) {
                Text(round.date, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("·")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(round.numberOfHoles)H")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(round.totalShots)")
                    .font(.caption.monospacedDigit())
                scoreLabel
            }
        }
    }

    private var scoreLabel: some View {
        let score = round.scoreToPar
        let text = score == 0 ? "E" : (score > 0 ? "+\(score)" : "\(score)")
        let color: Color = score <= 0 ? .green : (score <= 5 ? .yellow : .red)
        return Text(text)
            .font(.caption.bold())
            .foregroundStyle(color)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Round.self, HoleScore.self], inMemory: true)
}
