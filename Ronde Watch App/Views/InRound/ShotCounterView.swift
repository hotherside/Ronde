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

    @StateObject private var pedometer = PedometerService.shared
    @StateObject private var workoutManager = WorkoutManager.shared

    @State private var showHealthKitBanner = false
    @State private var shotPulse = false
    /// Pedometer cumulative distance at the start of the current hole.
    /// Subtracting from the live reading on hole-finish gives per-hole walking.
    @State private var holeStartDistance: Double = 0

    private var currentHole: HoleScore? {
        round.currentHole
    }

    var body: some View {
        Group {
            if showingHoleTransition, let hole = currentHole {
                HoleTransitionView(
                    hole: hole,
                    isLastHole: round.currentHoleIndex >= round.numberOfHoles - 1
                ) {
                    showingHoleTransition = false
                    captureHoleDistance(for: hole)
                    round.advanceToNextHole()
                    if round.isComplete {
                        finishRound()
                    }
                }
            } else if let hole = currentHole {
                shotCounterContent(hole: hole)
                    .overlay(alignment: .top) {
                        if showHealthKitBanner {
                            Text("Enable Health access in Settings to save your round")
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Theme.bunker.opacity(0.85), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .padding(.top, 4)
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }
                    }
                    .animation(.easeInOut(duration: 0.3), value: showHealthKitBanner)
            }
        }
        .task {
            await WorkoutManager.shared.startWorkout()
            PedometerService.shared.startTracking()
            if !WorkoutManager.shared.isActive && workoutManager.authorizationDenied {
                showHealthKitBanner = true
                try? await Task.sleep(for: .seconds(5))
                withAnimation { showHealthKitBanner = false }
            }
        }
    }

    // MARK: - Actions

    private func addShot(_ hole: HoleScore) {
        hole.incrementShot()
        WKInterfaceDevice.current().play(.click)
        triggerShotPulse()
    }

    private func undoShot(_ hole: HoleScore) {
        hole.decrementShot()
        WKInterfaceDevice.current().play(.retry)
    }

    private func triggerShotPulse() {
        shotPulse = true
        Task {
            try? await Task.sleep(for: .milliseconds(200))
            shotPulse = false
        }
    }

    private func finishRound() {
        let result = PedometerService.shared.stopTracking()
        round.totalSteps = result.steps
        round.totalDistanceMeters = result.distanceMeters
        Task { await WorkoutManager.shared.endWorkout() }
        onEndRound()
    }

    /// Snapshot pedometer delta into the just-completed hole and re-anchor for
    /// the next one. Called from the hole-transition continue closure, before
    /// `round.advanceToNextHole()` flips `currentHole`.
    private func captureHoleDistance(for hole: HoleScore) {
        let now = pedometer.totalDistanceMeters
        hole.distanceMeters = max(0, now - holeStartDistance)
        holeStartDistance = now
    }

    private func discardRound() {
        _ = PedometerService.shared.stopTracking()
        Task { await WorkoutManager.shared.endWorkout() }
        modelContext.delete(round)
        onDiscard()
    }

    // MARK: - Main Content

    private func shotCounterContent(hole: HoleScore) -> some View {
        VStack(spacing: 0) {
            // ── Top bar: hole + par ──
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 3) {
                        Image(systemName: Theme.Symbol.pin)
                            .font(.system(size: 7, weight: .bold))
                        Text("HOLE")
                            .font(.system(size: 8, weight: .bold, design: .rounded))
                            .tracking(1)
                    }
                    .foregroundStyle(Theme.fairwayBright.opacity(0.7))

                    Text("\(hole.holeNumber)")
                        .font(.scoreNumeral(size: 26))
                        .foregroundStyle(Theme.textPrimary)
                }

                Spacer()

                // Hole progress dots — at-a-glance position in the round
                HoleProgressDots(
                    total: round.numberOfHoles,
                    current: round.currentHoleIndex
                )

                Spacer()

                VStack(alignment: .trailing, spacing: 0) {
                    Text("PAR")
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.mutedText)
                        .tracking(1)
                    Text("\(hole.par)")
                        .font(.scoreNumeral(size: 26))
                        .foregroundStyle(Theme.mutedText)
                }
            }
            .padding(.horizontal, 10)

            Spacer(minLength: 0)

            // ── Hero: shot count, tap-to-add ──
            VStack(spacing: 4) {
                Text(hole.shots > 0 ? "\(hole.shots)" : "0")
                    .font(.scoreNumeral(size: 84))
                    .foregroundStyle(Theme.textPrimary)
                    .contentTransition(.numericText())
                    .scaleEffect(shotPulse ? 1.08 : 1.0)
                    .animation(.spring(response: 0.2, dampingFraction: 0.45), value: shotPulse)
                    .animation(.snappy(duration: 0.15), value: hole.shots)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)

                if hole.shots > 0 {
                    scoreToParBadge(for: hole)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    Text("TAP TO LOG SHOT")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.faintText)
                        .tracking(1.5)
                }
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .onTapGesture { addShot(hole) }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(hole.shots > 0 ? "\(hole.shots) shots" : "No shots yet")
            .accessibilityHint("Tap to add a shot")
            .animation(.easeOut(duration: 0.2), value: hole.shots)

            Spacer(minLength: 0)

            // ── Bottom toolbar ──
            HStack(spacing: 0) {
                Button { undoShot(hole) } label: {
                    Image(systemName: Theme.Symbol.undo)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(hole.shots > 0 ? Theme.textSecondary : Theme.faintText)
                        .frame(width: 34, height: 34)
                        .background(
                            Circle().fill(Theme.textPrimary.opacity(hole.shots > 0 ? 0.06 : 0.02))
                        )
                }
                .buttonStyle(.plain)
                .disabled(hole.shots == 0)
                .accessibilityLabel("Undo shot")

                Spacer()

                HStack(spacing: 3) {
                    Image(systemName: Theme.Symbol.walking)
                        .font(.system(size: 8))
                    Text("\(pedometer.totalSteps.formatted())")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("·")
                        .font(.system(size: 8))
                    Text("\(String(format: "%.1f", pedometer.totalDistanceMeters / 1000.0)) km")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                }
                .foregroundStyle(Theme.dimText)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(
                    "\(pedometer.totalSteps) steps, \(String(format: "%.1f", pedometer.totalDistanceMeters / 1000.0)) kilometers"
                )

                Spacer()

                Button {
                    showingHoleTransition = true
                    WKInterfaceDevice.current().play(.success)
                } label: {
                    Image(systemName: Theme.Symbol.flag)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(
                            Circle()
                                .fill(Theme.fairway)
                                .shadow(color: Theme.fairway.opacity(0.35), radius: 4, y: 2)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    round.currentHoleIndex >= round.numberOfHoles - 1
                        ? "Finish round" : "Finish hole"
                )
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 2)
        }
        .padding(.top, 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            Theme.scoreBackdrop(forDelta: hole.scoreToPar, hasShots: hole.shots > 0)
                .ignoresSafeArea()
        }
        .containerBackground(Theme.fairway.gradient, for: .navigation)
        .animation(.easeInOut(duration: 0.5), value: hole.shots)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    showingEndConfirmation = true
                } label: {
                    Image(systemName: "xmark")
                        .foregroundStyle(.white)
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
        let color = Theme.scoreColor(forDelta: diff)
        let text: String = {
            if diff <= -2 { return hole.scoreLabel }
            if diff == 0  { return "PAR" }
            return diff > 0 ? "+\(diff)" : "\(diff)"
        }()

        Text(text)
            .font(.system(size: 14, weight: .heavy, design: .rounded))
            .monospacedDigit()
            .tracking(1)
            .foregroundStyle(color)
            .padding(.horizontal, 12)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.18)))
            .accessibilityLabel(accessibilityScoreLabel(diff: diff))
    }

    private func accessibilityScoreLabel(diff: Int) -> String {
        switch diff {
        case ...(-2): return "\(abs(diff)) under par, \(Theme.scoreName(forDelta: diff))"
        case -1:      return "1 under par, birdie"
        case 0:       return "Even par"
        case 1:       return "1 over par, bogey"
        default:      return "\(diff) over par"
        }
    }
}

// MARK: - Hole progress dots

private struct HoleProgressDots: View {
    let total: Int
    let current: Int

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<min(total, 18), id: \.self) { index in
                Circle()
                    .fill(color(for: index))
                    .frame(width: 4, height: 4)
            }
        }
        .accessibilityHidden(true)
    }

    private func color(for index: Int) -> Color {
        if index == current { return Theme.fairwayBright }
        if index < current { return Theme.fairway.opacity(0.6) }
        return Theme.faintText
    }
}
