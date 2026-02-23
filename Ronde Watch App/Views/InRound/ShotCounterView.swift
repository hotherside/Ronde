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

    // MARK: - Motion Services

    @StateObject private var pedometer = PedometerService.shared
    @StateObject private var swingDetector = SwingDetector.shared

    /// Brief toast when a swing is auto-detected.
    @State private var showSwingToast = false

    /// Timestamp of last manual increment (+ button), for dedup with swing detection.
    @State private var lastManualIncrementTime: Date = .distantPast

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
            PedometerService.shared.startTracking()
            SwingDetector.shared.startDetecting()
        }
        .onChange(of: swingDetector.swingCount) { oldValue, newValue in
            guard newValue > oldValue else { return }
            guard let hole = currentHole else { return }

            // Dedup: skip if user manually tapped within last 2 seconds
            if Date().timeIntervalSince(lastManualIncrementTime) < 2.0 {
                return
            }

            hole.incrementShot()

            // Distinct haptic for auto-detected swing
            WKInterfaceDevice.current().play(.start)

            // Brief toast
            showSwingToast = true
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                showSwingToast = false
            }
        }
    }

    // MARK: - Actions

    private func finishRound() {
        // Save pedometer totals
        let result = PedometerService.shared.stopTracking()
        round.totalSteps = result.steps
        round.totalDistanceMeters = result.distanceMeters

        SwingDetector.shared.stopDetecting()

        Task { await WorkoutManager.shared.endWorkout() }
        onEndRound()
    }

    private func discardRound() {
        // Stop services without saving
        _ = PedometerService.shared.stopTracking()
        SwingDetector.shared.stopDetecting()

        Task { await WorkoutManager.shared.endWorkout() }
        modelContext.delete(round)
        onDiscard()
    }

    // MARK: - Main Content

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

            // Steps + distance — always visible
            HStack(spacing: 4) {
                Image(systemName: "figure.walk")
                    .font(.system(size: 9))
                Text("\(pedometer.totalSteps.formatted())")
                Text("·")
                Text("\(String(format: "%.1f", pedometer.totalDistanceMeters / 1000.0)) km")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                "\(pedometer.totalSteps) steps, \(String(format: "%.1f", pedometer.totalDistanceMeters / 1000.0)) kilometers"
            )

            Spacer()

            // Shot count — primary element
            ZStack {
                Text(hole.shots > 0 ? "\(hole.shots)" : "–")
                    .font(.system(size: 64, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.15), value: hole.shots)
                    .accessibilityLabel(hole.shots > 0 ? "\(hole.shots) shots" : "No shots yet")

                // Swing auto-detect toast
                if showSwingToast {
                    Text("Swing!")
                        .font(.caption.bold())
                        .foregroundStyle(.green)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(.green.opacity(0.2)))
                        .transition(.opacity.combined(with: .scale))
                        .offset(y: -44)
                }
            }
            .animation(.easeOut(duration: 0.3), value: showSwingToast)

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
                    // Dedup: skip if swing was auto-detected within last 2 seconds
                    if swingDetector.wasSwingDetectedWithin(seconds: 2.0) {
                        return
                    }
                    hole.incrementShot()
                    lastManualIncrementTime = .now
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(backgroundTint.ignoresSafeArea())
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

    // MARK: - Score Badge

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
