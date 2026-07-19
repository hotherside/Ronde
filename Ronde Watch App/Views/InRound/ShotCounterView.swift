import SwiftUI
import SwiftData
import WatchKit
import os

private let counterLog = Logger(subsystem: "com.ronde.Ronde", category: "ShotCounter")

struct ShotCounterView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Bindable var round: Round
    let onEndRound: () -> Void
    let onDiscard: () -> Void
    var startsTracking = true

    @State private var showingHoleTransition = false
    @State private var showingEndConfirmation = false
    @State private var showingSkipConfirmation = false
    @State private var showingParEditor = false
    @State private var showHealthKitBanner = false
    @State private var shotPulse = false
    @State private var isFinishingRound = false
    @State private var isCommittingHole = false
    @State private var holeStartDistance: Double = 0

    @StateObject private var pedometer = PedometerService.shared
    @StateObject private var workoutManager = WorkoutManager.shared

    private var currentHole: HoleScore? { round.currentHole }

    var body: some View {
        Group {
            if showingHoleTransition, let hole = currentHole {
                HoleTransitionView(
                    hole: hole,
                    isLastHole: round.currentHoleIndex >= round.sortedHoleScores.count - 1,
                    onContinue: { commitHoleAndContinue(hole) }
                )
            } else if let hole = currentHole {
                dashboard(hole)
            } else {
                invalidRoundView
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .task(id: round.id) {
            guard startsTracking else { return }
            await WorkoutManager.shared.startWorkout()
            let earliestReasonableStart = Date.now.addingTimeInterval(-12 * 60 * 60)
            PedometerService.shared.startTracking(from: max(round.date, earliestReasonableStart))
            holeStartDistance = completedHoleDistance

            if !WorkoutManager.shared.isActive && workoutManager.authorizationDenied {
                showHealthKitBanner = true
                try? await Task.sleep(for: .seconds(5))
                withAnimation { showHealthKitBanner = false }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { persistRound() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .rondeShotDidChange)) { notification in
            handleExternalShot(notification)
        }
        .sheet(isPresented: $showingParEditor) {
            if let hole = currentHole {
                ParPickerView(hole: hole) { persistRound() }
            }
        }
    }

    // MARK: - Dashboard

    private func dashboard(_ hole: HoleScore) -> some View {
        GeometryReader { proxy in
            // Width is the reliable discriminator here: the Ultra's curved
            // safe area can report a short height even with its larger canvas.
            let compact = proxy.size.width < 180

            VStack(spacing: 0) {
                topControls(hole)

                Spacer(minLength: 0)

                Button { addShot(hole) } label: {
                    VStack(spacing: 0) {
                        Text("\(hole.shots)")
                            .font(.scoreNumeral(size: compact ? 58 : 86))
                            .foregroundStyle(Theme.textPrimary)
                            .contentTransition(.numericText())
                            .scaleEffect(shotPulse && !reduceMotion ? 1.06 : 1)
                            .animation(
                                reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.22, dampingFraction: 0.72),
                                value: shotPulse
                            )
                            .minimumScaleFactor(0.55)
                            .lineLimit(1)

                        if !compact {
                            Text(hole.shots == 1 ? "STROKE" : "STROKES")
                                .font(.micro)
                                .tracking(1.8)
                                .foregroundStyle(Theme.textSecondary)
                        }

                        HStack(spacing: 4) {
                            Image(systemName: Theme.Symbol.actionButton)
                                .font(.system(size: 9, weight: .semibold))
                            Text("PRESS ACTION OR TAP")
                                .font(.system(size: compact ? 8 : 9, weight: .semibold, design: .rounded))
                                .tracking(compact ? 0.3 : 0.7)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                        }
                        .foregroundStyle(Theme.action)
                        .padding(.top, compact ? 2 : 6)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(hole.shots) strokes on hole \(hole.holeNumber)")
                .accessibilityHint("Tap to log another shot")

                Spacer(minLength: 0)

                bottomControls(hole, compact: compact)
                    .offset(y: compact ? -8 : 0)
            }
            .padding(.horizontal, compact ? 8 : 10)
            .padding(.top, compact ? 34 : 26)
            .padding(.bottom, compact ? 0 : 6)
        }
        .ignoresSafeArea(edges: .top)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { Theme.fairwayBackdrop.ignoresSafeArea() }
        .overlay(alignment: .top) {
            if showHealthKitBanner {
                Text("Enable Health access to keep Ronde active for the full round")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Theme.bunker.opacity(0.94), in: RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal, 12)
                    .transition(.opacity)
            }
        }
        .confirmationDialog(
            "End this round?",
            isPresented: $showingEndConfirmation,
            titleVisibility: .visible
        ) {
            Button("End & Save") {
                hole.isComplete = hole.shots > 0
                round.isComplete = true
                finishRound()
            }
            Button("Discard Round", role: .destructive) { discardRound() }
            Button("Keep Playing", role: .cancel) {}
        }
        .confirmationDialog(
            "Skip hole \(hole.holeNumber)?",
            isPresented: $showingSkipConfirmation,
            titleVisibility: .visible
        ) {
            Button("Skip Hole") { beginHoleTransition() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("A skipped hole will not count towards your score.")
        }
    }

    private func topControls(_ hole: HoleScore) -> some View {
        VStack(spacing: 7) {
            HStack(spacing: 7) {
                Button { showingEndConfirmation = true } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 30, height: 30)
                        .background(Theme.cardSurface, in: Circle())
                }
                .buttonStyle(RondePressStyle())
                .accessibilityLabel("End or discard round")

                ProgressView(
                    value: Double(round.currentHoleIndex + 1),
                    total: Double(max(round.sortedHoleScores.count, 1))
                )
                .tint(Theme.fairway)

                Text("\(round.currentHoleIndex + 1)/\(round.sortedHoleScores.count)")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textTertiary)
            }

            HStack(alignment: .firstTextBaseline) {
                metric(value: "\(hole.holeNumber)", label: "HOLE", alignment: .leading)
                Spacer()

                if pedometer.totalDistanceMeters >= 100 {
                    Label(
                        String(format: "%.1f km", pedometer.totalDistanceMeters / 1000),
                        systemImage: Theme.Symbol.walking
                    )
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
                }

                Spacer()
                metric(
                    value: Theme.compactScore(round.completedScoreToPar, hasShots: round.hasCompletedScore),
                    label: "ROUND",
                    color: Theme.scoreColor(
                        forDelta: round.completedScoreToPar,
                        hasShots: round.hasCompletedScore
                    ),
                    alignment: .center
                )
                Spacer()

                Button { showingParEditor = true } label: {
                    metric(value: "\(hole.par)", label: "PAR", alignment: .trailing)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Theme.cardSurface, in: RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(RondePressStyle())
                .accessibilityLabel("Par \(hole.par). Tap to adjust")
            }
        }
    }

    private func metric(
        value: String,
        label: String,
        color: Color = Theme.textPrimary,
        alignment: HorizontalAlignment
    ) -> some View {
        VStack(alignment: alignment, spacing: 0) {
            Text(label)
                .font(.system(size: 8, weight: .semibold, design: .rounded))
                .tracking(0.9)
                .foregroundStyle(Theme.textTertiary)
            Text(value)
                .font(.scoreNumeral(size: 21))
                .foregroundStyle(color)
        }
    }

    private func bottomControls(_ hole: HoleScore, compact: Bool) -> some View {
        HStack(spacing: 8) {
            Button { undoShot(hole) } label: {
                Image(systemName: Theme.Symbol.undo)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(hole.shots > 0 ? Theme.textPrimary : Theme.textFaint)
                    .frame(width: compact ? 36 : 46, height: compact ? 36 : 46)
                    .background(Theme.cardSurface, in: RoundedRectangle(cornerRadius: compact ? 13 : 15))
            }
            .buttonStyle(RondePressStyle())
            .disabled(hole.shots == 0)
            .accessibilityLabel("Undo last shot")

            Button {
                if hole.shots == 0 {
                    showingSkipConfirmation = true
                } else {
                    beginHoleTransition()
                }
            } label: {
                HStack(spacing: 6) {
                    Text(hole.shots == 0 ? "Skip Hole" : "Hole Done")
                        .font(.system(size: 14, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.74)
                    Image(systemName: Theme.Symbol.flag)
                        .font(.system(size: 12, weight: .bold))
                }
                .foregroundStyle(Color.black.opacity(0.86))
                .frame(maxWidth: .infinity)
                .frame(height: compact ? 36 : 46)
                .background(Theme.fairway, in: RoundedRectangle(cornerRadius: compact ? 13 : 15))
            }
            .buttonStyle(RondePressStyle())
            .accessibilityLabel(
                hole.shots == 0
                    ? "Skip hole \(hole.holeNumber)"
                    : round.currentHoleIndex >= round.sortedHoleScores.count - 1
                        ? "Finish round" : "Finish hole \(hole.holeNumber)"
            )
        }
    }

    private var invalidRoundView: some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.bunker)
            Text("This round has no playable hole.")
                .font(.bodyEmphasized)
                .multilineTextAlignment(.center)
            OutlineButton(title: "Discard Round") { discardRound() }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .fairwayBackground()
    }

    // MARK: - Actions

    private func addShot(_ hole: HoleScore) {
        hole.incrementShot()
        WKInterfaceDevice.current().play(.click)
        persistRound()
        triggerShotPulse()
    }

    private func undoShot(_ hole: HoleScore) {
        hole.decrementShot()
        WKInterfaceDevice.current().play(.retry)
        persistRound()
    }

    private func beginHoleTransition() {
        guard !showingHoleTransition, !isCommittingHole else { return }
        WKInterfaceDevice.current().play(.success)
        showingHoleTransition = true
    }

    private func commitHoleAndContinue(_ hole: HoleScore) {
        guard !isCommittingHole, !isFinishingRound else { return }
        isCommittingHole = true

        captureHoleDistance(for: hole)
        round.advanceToNextHole()
        persistRound()

        if round.isComplete {
            finishRound()
        } else {
            showingHoleTransition = false
            isCommittingHole = false
        }
    }

    private func finishRound() {
        guard !isFinishingRound else { return }
        isFinishingRound = true
        let result = PedometerService.shared.stopTracking()
        round.totalSteps = result.steps
        round.totalDistanceMeters = result.distanceMeters
        persistRound()
        Task { await WorkoutManager.shared.endWorkout() }
        onEndRound()
    }

    private func discardRound() {
        guard !isFinishingRound else { return }
        isFinishingRound = true
        _ = PedometerService.shared.stopTracking()
        Task { await WorkoutManager.shared.endWorkout() }
        modelContext.delete(round)
        persistRound()
        onDiscard()
    }

    private func captureHoleDistance(for hole: HoleScore) {
        let now = pedometer.totalDistanceMeters
        hole.distanceMeters = max(0, now - holeStartDistance)
        holeStartDistance = now
    }

    private var completedHoleDistance: Double {
        round.sortedHoleScores
            .filter(\.isComplete)
            .reduce(0) { $0 + $1.distanceMeters }
    }

    private func triggerShotPulse() {
        shotPulse = true
        Task {
            try? await Task.sleep(for: .milliseconds(160))
            shotPulse = false
        }
    }

    private func handleExternalShot(_ notification: Notification) {
        guard let holeID = notification.userInfo?["holeID"] as? UUID,
              let shots = notification.userInfo?["shots"] as? Int,
              let hole = round.sortedHoleScores.first(where: { $0.id == holeID }) else { return }

        if hole.shots != shots {
            hole.shots = shots
        }
        triggerShotPulse()
    }

    private func persistRound() {
        do {
            try modelContext.save()
        } catch {
            counterLog.error("Round save failed: \(error.localizedDescription)")
        }
    }
}

private struct ParPickerView: View {
    @Bindable var hole: HoleScore
    let onDone: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 8) {
            Text("Hole \(hole.holeNumber) Par")
                .font(.titleSmall)

            Picker("Par", selection: $hole.par) {
                ForEach(3...5, id: \.self) { par in
                    Text("Par \(par)").tag(par)
                }
            }
            .labelsHidden()

            PrimaryButton(title: "Done", icon: "checkmark") {
                onDone()
                dismiss()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .fairwayBackground()
    }
}
