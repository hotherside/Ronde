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

    @State private var displayedMetrics: SwingMetrics?
    @State private var metricsDisplayTask: Task<Void, Never>?
    @State private var lastManualIncrementTime: Date = .distantPast

    // MARK: - Animation State

    @State private var shotPulse = false

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
            // CMBatchedSensorManager requires an active HKWorkoutSession.
            // Only start swing detection if the workout session is running.
            if WorkoutManager.shared.isActive {
                SwingDetector.shared.startDetecting()
            }
        }
        .onChange(of: swingDetector.swingCount) { oldValue, newValue in
            guard newValue > oldValue else { return }
            guard let hole = currentHole else { return }

            if Date().timeIntervalSince(lastManualIncrementTime) < 2.0 {
                return
            }

            hole.incrementShot()
            WKInterfaceDevice.current().play(.start)
            triggerShotPulse()

            // Show metrics card instead of plain "SWING" toast
            showSwingMetrics()
        }
    }

    // MARK: - Actions

    private func addShot(_ hole: HoleScore) {
        if swingDetector.wasSwingDetectedWithin(seconds: 2.0) { return }
        hole.incrementShot()
        lastManualIncrementTime = .now
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

    private func showSwingMetrics() {
        // Cancel any previous display timer
        metricsDisplayTask?.cancel()

        metricsDisplayTask = Task {
            // Wait for SwingDetector to finish capturing follow-through data
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }

            if let metrics = swingDetector.lastSwingMetrics {
                // Persist for later review
                currentHole?.swingData.append(metrics)

                withAnimation(.spring(response: 0.35, dampingFraction: 0.65)) {
                    displayedMetrics = metrics
                }
            }

            // Auto-dismiss after 3.5 seconds
            try? await Task.sleep(for: .seconds(3.5))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.3)) {
                displayedMetrics = nil
            }
        }
    }

    private func finishRound() {
        let result = PedometerService.shared.stopTracking()
        round.totalSteps = result.steps
        round.totalDistanceMeters = result.distanceMeters
        SwingDetector.shared.stopDetecting()
        Task { await WorkoutManager.shared.endWorkout() }
        onEndRound()
    }

    private func discardRound() {
        _ = PedometerService.shared.stopTracking()
        SwingDetector.shared.stopDetecting()
        Task { await WorkoutManager.shared.endWorkout() }
        modelContext.delete(round)
        onDiscard()
    }

    // MARK: - Color Helpers

    private func scoreColor(for hole: HoleScore) -> Color {
        guard hole.shots > 0 else { return .clear }
        let diff = hole.shots - hole.par
        if diff < 0  { return .green }
        if diff == 0 { return .green }
        if diff <= 2 { return .orange }
        return .red
    }

    private func backgroundGradient(for hole: HoleScore) -> some ShapeStyle {
        let tint = scoreColor(for: hole)
        return RadialGradient(
            colors: hole.shots > 0
                ? [tint.opacity(0.18), tint.opacity(0.05), .clear]
                : [.clear, .clear, .clear],
            center: .center,
            startRadius: 5,
            endRadius: 180
        )
    }

    // MARK: - Main Content — Spatial Dashboard

    private func shotCounterContent(hole: HoleScore) -> some View {
        VStack(spacing: 0) {
            // ── Top corners: hole info + par ──
            HStack(alignment: .top) {
                // Left: hole number
                VStack(alignment: .leading, spacing: 0) {
                    Text("HOLE")
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.35))
                        .tracking(1)
                    Text("\(hole.holeNumber)")
                        .font(.system(size: 24, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                }

                Spacer()

                // Right: par
                VStack(alignment: .trailing, spacing: 0) {
                    Text("PAR")
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.35))
                        .tracking(1)
                    Text("\(hole.par)")
                        .font(.system(size: 24, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
            .padding(.horizontal, 10)

            Spacer(minLength: 0)

            // ── Center: hero shot count — tap to add ──
            VStack(spacing: 2) {
                // Shot count — massive
                Text(hole.shots > 0 ? "\(hole.shots)" : "0")
                    .font(.system(size: 80, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                    .scaleEffect(shotPulse ? 1.08 : 1.0)
                    .animation(.spring(response: 0.2, dampingFraction: 0.45), value: shotPulse)
                    .animation(.snappy(duration: 0.15), value: hole.shots)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)

                // Score badge or tap hint
                if hole.shots > 0 {
                    scoreToParBadge(for: hole)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    Text("TAP TO START")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.2))
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

            // ── Bottom: icon toolbar ──
            HStack(spacing: 0) {
                // Undo
                Button { undoShot(hole) } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(hole.shots > 0 ? .white.opacity(0.6) : .white.opacity(0.12))
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(.white.opacity(hole.shots > 0 ? 0.08 : 0.03)))
                }
                .buttonStyle(.plain)
                .disabled(hole.shots == 0)
                .accessibilityLabel("Undo shot")

                Spacer()

                // Steps + distance — compact center
                HStack(spacing: 3) {
                    Image(systemName: "figure.walk")
                        .font(.system(size: 8))
                    Text("\(pedometer.totalSteps.formatted())")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("·")
                        .font(.system(size: 8))
                    Text("\(String(format: "%.1f", pedometer.totalDistanceMeters / 1000.0))km")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                }
                .foregroundStyle(.white.opacity(0.3))
                .accessibilityElement(children: .combine)
                .accessibilityLabel(
                    "\(pedometer.totalSteps) steps, \(String(format: "%.1f", pedometer.totalDistanceMeters / 1000.0)) kilometers"
                )

                Spacer()

                // Finish hole
                Button {
                    showingHoleTransition = true
                    WKInterfaceDevice.current().play(.success)
                } label: {
                    Image(systemName: "flag.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.green)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(.green.opacity(0.15)))
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
        .background { Rectangle().fill(backgroundGradient(for: hole)).ignoresSafeArea() }
        .overlay {
            if let metrics = displayedMetrics {
                SwingMetricsCard(metrics: metrics)
                    .transition(
                        .asymmetric(
                            insertion: .scale(scale: 0.7).combined(with: .opacity),
                            removal: .opacity
                        )
                    )
                    .zIndex(10)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.65), value: displayedMetrics?.id)
        .animation(.easeInOut(duration: 0.5), value: hole.shots)
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
            case 0:       return ("E", Color(white: 0.5))
            case 1:       return ("+1", .orange)
            default:      return (hole.scoreLabel, .red)
            }
        }()

        Text(text)
            .font(.system(size: 16, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(color)
            .padding(.horizontal, 12)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.15)))
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
