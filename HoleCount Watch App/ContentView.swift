import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Round.date, order: .reverse) private var rounds: [Round]
    @State private var showingSetup = false
    @State private var activeRound: Round?

    var body: some View {
        NavigationStack {
            if let round = activeRound, !round.isComplete {
                ShotCounterView(round: round) {
                    activeRound = nil
                }
            } else {
                roundsList
            }
        }
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

            if !rounds.isEmpty {
                Section("Past Rounds") {
                    ForEach(rounds) { round in
                        NavigationLink {
                            RoundSummaryView(round: round, isPostRound: false)
                        } label: {
                            RoundRowView(round: round)
                        }
                    }
                    .onDelete(perform: deleteRounds)
                }
            }
        }
        .navigationTitle("HoleCount")
        .sheet(isPresented: $showingSetup) {
            StartView { round in
                activeRound = round
                showingSetup = false
            }
        }
    }

    private func deleteRounds(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(rounds[index])
        }
    }
}

private struct RoundRowView: View {
    let round: Round

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(round.courseName ?? "Custom Round")
                .font(.headline)
            HStack {
                Text(round.date, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(round.totalShots) shots")
                    .font(.caption)
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
