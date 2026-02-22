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
        if showingHoleTransition, let hole = currentHole {
            HoleTransitionView(
                hole: hole,
                isLastHole: round.currentHoleIndex >= round.numberOfHoles - 1
            ) {
                showingHoleTransition = false
                round.advanceToNextHole()
                if round.isComplete {
                    onEndRound()
                }
            }
        } else if let hole = currentHole {
            shotCounterContent(hole: hole)
        }
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

            // Shot count - the main element
            Text("\(hole.shots)")
                .font(.system(size: 64, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.snappy(duration: 0.2), value: hole.shots)

            // Score to par (only when shots > 0)
            if hole.shots > 0 {
                Text(hole.scoreLabel)
                    .font(.caption.bold())
                    .foregroundStyle(scoreColor(for: hole))
            }

            Spacer()

            // Controls
            HStack(spacing: 20) {
                // Undo button
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

                // Add shot button (screen alternative to Action Button)
                Button {
                    hole.incrementShot()
                    WKInterfaceDevice.current().play(.start)
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.green)

                // Done with hole
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
                onEndRound()
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
