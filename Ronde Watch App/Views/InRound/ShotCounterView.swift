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

    @State private var showSwingToast = false
    @State private var lastManualIncrementTime: Date = .distantPast

    // MARK: - Animation State

    @State private var shotPulse = false
    @State private var ringPulse = false

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
            SwingDetector.shared.startDetecting()
        }
        .onChange(of: swingDetector.swingCount) { oldValue, newValue in
            guard newValue > oldValue else { return }
            guard let hole = currentHole else { return }

            if Date().timeIntervalSince(lastManualIncrementTime) < 2.0 {
                return
            }

            hole.incrementShot()
            WKInterfaceDevice.current().play(.start)
            triggerShotAnimation()

            showSwingToast = true
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                showSwingToast = false
            }
        }
    }

    // MARK: - Actions

    private func addShot(_ hole: HoleScore) {
        if swingDetector.wasSwingDetectedWithin(seconds: 2.0) { return }
        hole.incrementShot()
        lastManualIncrementTime = .now
        WKInterfaceDevice.current().play(.click)
        triggerShotAnimation()
    }

    private func undoShot(_ hole: HoleScore) {
        hole.decrementShot()
        WKInterfaceDevice.current().play(.retry)
    }

    private func triggerShotAnimation() {
        shotPulse = true
        ringPulse = true
        Task {
            try? await Task.sleep(for: .milliseconds(180))
            shotPulse = false
            try? await Task.sleep(for: .milliseconds(120))
            ringPulse = false
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

    // MARK: - Arc Helpers

    private func arcProgress(for hole: HoleScore) -> CGFloat {
        guard hole.par > 0, hole.shots > 0 else { return 0 }
        return min(CGFloat(hole.shots) / CGFloat(hole.par), 1.0)
    }

    private func arcColor(for hole: HoleScore) -> Color {
        guard hole.shots > 0 else { return .clear }
        let diff = hole.shots - hole.par
        if diff < 0  { return .green }
        if diff == 0 { return .green }
        if diff <= 2 { return .orange }
        return .red
    }

    private func backgroundGradient(for hole: HoleScore) -> some ShapeStyle {
        let tint = arcColor(for: hole)
        return RadialGradient(
            colors: hole.shots > 0
                ? [tint.opacity(0.18), tint.opacity(0.06), .clear]
                : [.clear, .clear, .clear],
            center: .center,
            startRadius: 10,
            endRadius: 160
        )
    }

    // MARK: - Main Content

    private func shotCounterContent(hole: HoleScore) -> some View {
        VStack(spacing: 0) {
            // ── Top bar ──
            HStack {
                Text("\(hole.holeNumber)/\(round.numberOfHoles)")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)

                Spacer()

                Text("PAR \(hole.par)")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .tracking(0.5)
            }
            .padding(.horizontal, 4)

            Spacer(minLength: 0)

            // ── Center: ring + number — TAP TO ADD ──
            shotRing(hole: hole)
                .contentShape(Circle())
                .onTapGesture { addShot(hole) }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(hole.shots > 0 ? "\(hole.shots) shots" : "No shots yet")
                .accessibilityHint("Tap to add a shot")

            Spacer(minLength: 0)

            // ── Bottom bar: undo · steps · done ──
            HStack(spacing: 0) {
                // Undo
                Button { undoShot(hole) } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(hole.shots > 0 ? .white.opacity(0.7) : .white.opacity(0.12))
                }
                .buttonStyle(.plain)
                .disabled(hole.shots == 0)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel("Undo shot")

                // Steps + distance
                HStack(spacing: 3) {
                    Image(systemName: "figure.walk")
                    Text("\(pedometer.totalSteps.formatted())")
                    Text("·")
                    Text("\(String(format: "%.1f", pedometer.totalDistanceMeters / 1000.0))km")
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.3))
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(
                    "\(pedometer.totalSteps) steps, \(String(format: "%.1f", pedometer.totalDistanceMeters / 1000.0)) kilometers"
                )

                // Finish hole
                Button {
                    showingHoleTransition = true
                    WKInterfaceDevice.current().play(.success)
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .accessibilityLabel(
                    round.currentHoleIndex >= round.numberOfHoles - 1
                        ? "Finish round" : "Finish hole"
                )
            }
            .padding(.horizontal, 2)
        }
        .padding(.horizontal, 6)
        .padding(.top, 2)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { Rectangle().fill(backgroundGradient(for: hole)).ignoresSafeArea() }
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

    // MARK: - Shot Ring

    @ViewBuilder
    private func shotRing(hole: HoleScore) -> some View {
        let ringSize: CGFloat = 130
        let strokeWidth: CGFloat = 5
        let progress = arcProgress(for: hole)
        let color = arcColor(for: hole)

        ZStack {
            // Track ring
            Circle()
                .stroke(Color.white.opacity(0.07), lineWidth: strokeWidth)
                .frame(width: ringSize, height: ringSize)

            // Progress arc
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    color,
                    style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .frame(width: ringSize, height: ringSize)
                .animation(.easeInOut(duration: 0.4), value: hole.shots)
                .opacity(ringPulse ? 1.0 : 0.85)
                .scaleEffect(ringPulse ? 1.04 : 1.0)
                .animation(.spring(response: 0.25, dampingFraction: 0.5), value: ringPulse)

            // Center content
            VStack(spacing: 2) {
                // Swing toast
                if showSwingToast {
                    Text("SWING")
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .foregroundStyle(.green)
                        .tracking(1.5)
                        .transition(.opacity.combined(with: .scale(scale: 0.7)))
                }

                // Shot count — HERO
                Text(hole.shots > 0 ? "\(hole.shots)" : "–")
                    .font(.system(size: 72, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                    .scaleEffect(shotPulse ? 1.12 : 1.0)
                    .animation(.spring(response: 0.2, dampingFraction: 0.45), value: shotPulse)
                    .animation(.snappy(duration: 0.15), value: hole.shots)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)

                // Score badge or tap hint
                if hole.shots > 0 {
                    scoreToParBadge(for: hole)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    Text("TAP")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.25))
                        .tracking(2)
                }
            }
            .animation(.easeOut(duration: 0.25), value: showSwingToast)
            .animation(.easeOut(duration: 0.2), value: hole.shots)
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
