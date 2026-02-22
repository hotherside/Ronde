import SwiftUI
import WatchKit

struct ShotCounterView: View {
    @Bindable var round: Round
    let onEndRound: () -> Void

    @State private var showingHoleTransition = false
    @State private var showingEndConfirmation = false

    private var currentHole: HoleScore? {
        round.currentHole
    }

    private var backgroundColor: Color {
        guard let hole = currentHole else { return .clear }
        let diff = hole.shots - hole.par
        if hole.shots == 0 { return .clear }
        if diff <= 0 { return .green.opacity(0.15) }
        if diff <= 2 { return .yellow.opacity(0.15) }
        return .red.opacity(0.15)
    }

    var body: some View {
        Group {
            if showingHoleTransition, let hole = currentHole {
                HoleTransitionView(
                    hole: hole,
                    isLastHole: round.currentHoleIndex >= round.numberOfHoles - 1
                ) {
                    showingHoleTransition = false
                    round.advanceToNextHole()
                    if round.isComplete {
                        finishRound()
                    }
                }
            } else if let hole = currentHole {
                shotCounterContent(hole: hole)
            }
        }
        .task {
            // Start a HealthKit golf workout session to keep the app alive
            // and the display on for the duration of the round.
            await WorkoutManager.shared.startWorkout()
        }
    }

    /// Ends the HealthKit workout session then hands off to the parent
    /// to show the summary screen.
    private func finishRound() {
        Task { await WorkoutManager.shared.endWorkout() }
        onEndRound()
    }

    private func shotCounterContent(hole: HoleScore) -> some View {
        VStack(spacing: 4) {
            // Hole info
            Text("Hole \(hole.holeNumber) of \(round.numberOfHoles)")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text("Par \(hole.par)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            // Shot count — the primary element
            Text("\(hole.shots)")
                .font(.system(size: 64, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.snappy(duration: 0.2), value: hole.shots)

            // Score to par (only once shots have been logged)
            if hole.shots > 0 {
                Text(hole.scoreLabel)
                    .font(.caption.bold())
                    .foregroundStyle(scoreColor(for: hole))
            }

            Spacer()

            // Controls
            HStack(spacing: 20) {
                // Undo
                Button {
                    hole.decrementShot()
                    WKInterfaceDevice.current().play(.retry)
                } label: {
                    Image(systemName: "minus.circle")
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .foregroundStyle(hole.shots > 0 ? .red : .gray)
                .disabled(hole.shots == 0)

                // Add shot (screen alternative to Action Button)
                Button {
                    hole.incrementShot()
                    WKInterfaceDevice.current().play(.start)
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.green)

                // Finish hole
                Button {
                    showingHoleTransition = true
                    WKInterfaceDevice.current().play(.success)
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.blue)
            }
        }
        .padding()
        .background(backgroundColor)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    showingEndConfirmation = true
                } label: {
                    Image(systemName: "xmark")
                }
            }
        }
        .confirmationDialog(
            "End Round?",
            isPresented: $showingEndConfirmation,
            titleVisibility: .visible
        ) {
            Button("End & Save", role: .destructive) {
                round.isComplete = true
                finishRound()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func scoreColor(for hole: HoleScore) -> Color {
        let diff = hole.scoreToPar
        if diff <= 0 { return .green }
        if diff <= 2 { return .yellow }
        return .red
    }
}
