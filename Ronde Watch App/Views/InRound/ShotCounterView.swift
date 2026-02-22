import SwiftUI
import SwiftData
import WatchKit

struct ShotCounterView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var round: Round
    let onEndRound: () -> Void
    let onDiscard: () -> Void

    @State private var showingHoleTransition = false
    @State private var showingEndConfirmation = false

    private var currentHole: HoleScore? {
        round.currentHole
    }

    private var backgroundTint: Color {
        guard let hole = currentHole, hole.shots > 0 else { return .clear }
        let diff = hole.shots - hole.par
        if diff <= 0 { return .green.opacity(0.12) }
        if diff <= 2 { return .yellow.opacity(0.12) }
        return .red.opacity(0.12)
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
            await WorkoutManager.shared.startWorkout()
        }
    }

    private func finishRound() {
        Task { await WorkoutManager.shared.endWorkout() }
        onEndRound()
    }

    private func discardRound() {
        Task { await WorkoutManager.shared.endWorkout() }
        modelContext.delete(round)
        onDiscard()
    }

    private func shotCounterContent(hole: HoleScore) -> some View {
        VStack(spacing: 4) {
            // Hole info
            Text("Hole \(hole.holeNumber) / \(round.numberOfHoles)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Hole \(hole.holeNumber) of \(round.numberOfHoles)")

            Text("Par \(hole.par)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            // Shot count — primary element
            Text(hole.shots > 0 ? "\(hole.shots)" : "–")
                .font(.system(size: 64, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.snappy(duration: 0.15), value: hole.shots)
                .accessibilityLabel(hole.shots > 0 ? "\(hole.shots) shots" : "No shots yet")

            // Score-to-par badge (only after first shot)
            if hole.shots > 0 {
                scoreToParBadge(for: hole)
            }

            Spacer()

            // Controls
            HStack(spacing: 20) {
                // Undo
                Button {
                    hole.decrementShot()
                    WKInterfaceDevice.current().play(.retry)
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(hole.shots > 0 ? .red : Color.secondary.opacity(0.3))
                }
                .buttonStyle(.plain)
                .disabled(hole.shots == 0)
                .accessibilityLabel("Undo shot")

                // Finish hole
                Button {
                    showingHoleTransition = true
                    WKInterfaceDevice.current().play(.success)
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title)
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    round.currentHoleIndex >= round.numberOfHoles - 1
                        ? "Finish round"
                        : "Finish hole"
                )

                // Add shot (on-screen fallback for Action Button)
                Button {
                    hole.incrementShot()
                    WKInterfaceDevice.current().play(.click)
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.green)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add shot")
            }
        }
        .padding()
        .background(backgroundTint)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    showingEndConfirmation = true
                } label: {
                    Image(systemName: "xmark")
                }
                .accessibilityLabel("End or discard round")
            }
        }
        .confirmationDialog(
            "End Round?",
            isPresented: $showingEndConfirmation,
            titleVisibility: .visible
        ) {
            Button("Save & Exit") {
                round.isComplete = true
                finishRound()
            }
            Button("Discard Round", role: .destructive) {
                discardRound()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    @ViewBuilder
    private func scoreToParBadge(for hole: HoleScore) -> some View {
        let diff = hole.scoreToPar
        let (text, color): (String, Color) = {
            switch diff {
            case ...(-2): return (hole.scoreLabel, .yellow)
            case -1:      return ("-1", .green)
            case 0:       return ("E", Color(white: 0.55))
            case 1:       return ("+1", .orange)
            default:      return (hole.scoreLabel, .red)
            }
        }()
        Text(text)
            .font(.caption.bold())
            .foregroundStyle(color)
            .accessibilityLabel(accessibilityScoreLabel(diff: diff, shots: hole.shots))
    }

    private func accessibilityScoreLabel(diff: Int, shots: Int) -> String {
        switch diff {
        case ...(-2): return "\(abs(diff)) under par"
        case -1:      return "1 under par, birdie"
        case 0:       return "Even par"
        case 1:       return "1 over par, bogey"
        default:      return "\(diff) over par"
        }
    }
}
