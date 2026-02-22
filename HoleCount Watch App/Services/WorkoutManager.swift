import Foundation
import HealthKit
import os.log

private let log = Logger(subsystem: "com.ronde.HoleCount", category: "WorkoutManager")

/// Manages an HKWorkoutSession (golf) that keeps the app alive
/// and the display on during a 4-5 hour round.
///
/// Usage:
///   - Call `startWorkout()` when a round begins (ShotCounterView.onAppear)
///   - Call `endWorkout()` before navigating to the summary screen
@MainActor
final class WorkoutManager: NSObject {

    // MARK: - Shared instance

    static let shared = WorkoutManager()

    // MARK: - State

    private(set) var isActive = false

    // MARK: - Private

    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    private override init() {
        super.init()
    }

    // MARK: - Public API

    func startWorkout() async {
        guard !isActive else { return }

        guard HKHealthStore.isHealthDataAvailable() else {
            log.info("HealthKit not available on this device — skipping workout session")
            return
        }

        let typesToShare: Set<HKSampleType> = [HKQuantityType.workoutType()]
        let typesToRead: Set<HKObjectType> = [HKQuantityType.workoutType()]

        do {
            try await healthStore.requestAuthorization(toShare: typesToShare, read: typesToRead)
        } catch {
            log.error("HealthKit authorization failed: \(error.localizedDescription)")
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
            log.info("Golf workout session started")
        } catch {
            log.error("Failed to create/start workout session: \(error.localizedDescription)")
        }
    }

    func endWorkout() async {
        guard isActive, let session, let builder else { return }

        session.end()

        do {
            try await builder.endCollection(at: .now)
            _ = try await builder.finishWorkout()
            log.info("Golf workout session ended and saved to Health")
        } catch {
            log.error("Failed to end workout: \(error.localizedDescription)")
        }

        self.session = nil
        self.builder = nil
        isActive = false
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
