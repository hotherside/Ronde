import Foundation
import HealthKit
import AppIntents
import os.log

private let log = Logger(subsystem: "com.ronde.Ronde", category: "WorkoutManager")

/// Manages an HKWorkoutSession (golf) that keeps the app alive
/// and the display on during a 4-5 hour round.
///
/// Usage:
///   - Call `startWorkout()` when a round begins (ShotCounterView.onAppear)
///   - Call `endWorkout()` before navigating to the summary screen
@MainActor
final class WorkoutManager: NSObject, ObservableObject {

    // MARK: - Shared instance

    static let shared = WorkoutManager()

    // MARK: - State

    @Published private(set) var isActive = false

    /// True when HealthKit is unavailable or the user denied authorization.
    /// The app still works — shot counting and pedometer function without a
    /// workout session — but the round won't be saved to Apple Health and the
    /// app may get suspended during long rounds.
    @Published private(set) var authorizationDenied = false

    // MARK: - Private

    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var isEnding = false

    private override init() {
        super.init()
    }

    // MARK: - Public API

    func startWorkout() async {
        guard !isEnding else { return }
        if isActive {
            await donateShotAction()
            return
        }

        guard HKHealthStore.isHealthDataAvailable() else {
            log.info("HealthKit not available on this device — skipping workout session")
            authorizationDenied = true
            return
        }

        // Request authorization. This shows the system prompt on first launch;
        // on subsequent launches it returns immediately without throwing,
        // even if the user previously denied access.
        let typesToShare: Set<HKSampleType> = [HKQuantityType.workoutType()]
        let typesToRead: Set<HKObjectType> = [HKQuantityType.workoutType()]

        do {
            try await healthStore.requestAuthorization(toShare: typesToShare, read: typesToRead)
        } catch {
            log.error("HealthKit authorization request failed: \(error.localizedDescription)")
            authorizationDenied = true
            return
        }

        // Check the actual authorization status — requestAuthorization
        // succeeds even when the user denies permission.
        let workoutStatus = healthStore.authorizationStatus(for: HKQuantityType.workoutType())
        if workoutStatus != .sharingAuthorized {
            log.warning("HealthKit workout sharing not authorized (status: \(workoutStatus.rawValue)) — workout session will not start")
            authorizationDenied = true
            return
        }

        let config = HKWorkoutConfiguration()
        config.activityType = .golf
        config.locationType = .outdoor

        do {
            let workoutSession = try HKWorkoutSession(
                healthStore: healthStore,
                configuration: config
            )
            let workoutBuilder = workoutSession.associatedWorkoutBuilder()
            workoutBuilder.dataSource = HKLiveWorkoutDataSource(
                healthStore: healthStore,
                workoutConfiguration: config
            )
            workoutSession.delegate = self
            workoutBuilder.delegate = self

            self.session = workoutSession
            self.builder = workoutBuilder

            workoutSession.startActivity(with: .now)
            try await workoutBuilder.beginCollection(at: .now)

            isActive = true
            authorizationDenied = false
            log.info("Golf workout session started")
            await donateShotAction()
        } catch {
            log.error("Failed to create/start workout session: \(error.localizedDescription)")
            // Clean up without calling session.end() on a session that
            // never fully started — avoids HKLiveWorkoutBuilder state
            // machine transition errors.
            self.session = nil
            self.builder = nil
        }
    }

    func endWorkout() async {
        guard isActive, !isEnding, let session, let builder else { return }

        // Claim the end operation synchronously before awaiting HealthKit. This
        // prevents a double-tap or duplicated transition callback from ending
        // the same builder twice and tripping its state machine.
        isEnding = true
        isActive = false
        self.session = nil
        self.builder = nil

        session.end()

        do {
            try await builder.endCollection(at: .now)
            _ = try await builder.finishWorkout()
            log.info("Golf workout session ended and saved to Health")
        } catch {
            log.error("Failed to end workout: \(error.localizedDescription)")
        }

        isEnding = false
    }

    /// Reattaches delegates and the live builder after watchOS relaunches Ronde
    /// following a crash during an active workout.
    func recoverActiveWorkout() async {
        guard !isActive, !isEnding else { return }

        do {
            guard let recoveredSession = try await healthStore.recoverActiveWorkoutSession() else {
                log.info("No active golf workout was available to recover")
                return
            }

            let recoveredBuilder = recoveredSession.associatedWorkoutBuilder()
            recoveredBuilder.dataSource = HKLiveWorkoutDataSource(
                healthStore: healthStore,
                workoutConfiguration: recoveredSession.workoutConfiguration
            )
            recoveredSession.delegate = self
            recoveredBuilder.delegate = self

            session = recoveredSession
            builder = recoveredBuilder
            isActive = true
            authorizationDenied = false
            log.info("Recovered active golf workout after relaunch")
            await donateShotAction()
        } catch {
            log.error("Workout recovery failed: \(error.localizedDescription)")
        }
    }

    private func donateShotAction() async {
        do {
            _ = try await StartGolfRoundIntent().donate(
                result: .result(actionButtonIntent: ShotCountIntent())
            )
            log.debug("Donated Log Shot as the Ultra Action Button's next action")
        } catch {
            log.error("Unable to donate Action Button shot intent: \(error.localizedDescription)")
        }
    }

    private func handleSessionFailure() {
        session = nil
        builder = nil
        isActive = false
        isEnding = false
    }
}

// MARK: - HKWorkoutSessionDelegate

extension WorkoutManager: HKWorkoutSessionDelegate {

    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        log.debug("Workout state changed: \(fromState.rawValue) → \(toState.rawValue)")
    }

    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didFailWithError error: any Error
    ) {
        log.error("Workout session failed: \(error.localizedDescription)")
        Task { @MainActor [weak self] in
            self?.handleSessionFailure()
        }
    }
}

// MARK: - HKLiveWorkoutBuilderDelegate

extension WorkoutManager: HKLiveWorkoutBuilderDelegate {

    nonisolated func workoutBuilder(
        _ workoutBuilder: HKLiveWorkoutBuilder,
        didCollectDataOf collectedTypes: Set<HKSampleType>
    ) {}

    nonisolated func workoutBuilderDidCollectEvent(
        _ workoutBuilder: HKLiveWorkoutBuilder
    ) {}
}
