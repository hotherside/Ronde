import AppIntents
import SwiftData
import WatchKit
import os

private let intentLog = Logger(subsystem: "com.ronde.Ronde", category: "ActionButton")

extension Notification.Name {
    static let rondeShotDidChange = Notification.Name("com.ronde.Ronde.shotDidChange")
}

/// The quick-start choice Ronde exposes in Settings > Action Button > Workout.
/// The first press starts the preferred round length; later presses log shots.
enum GolfRoundStyle: String, AppEnum {
    case golf

    static let allCases: [GolfRoundStyle] = [.golf]
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Golf Round"
    static let caseDisplayRepresentations: [GolfRoundStyle: DisplayRepresentation] = [
        .golf: DisplayRepresentation(
            title: "Golf Round",
            subtitle: "Start your preferred round length"
        ),
    ]

    var holeCount: Int {
        let preferred = UserDefaults.standard.integer(forKey: "preferredHoleCount")
        return preferred == 9 ? 9 : 18
    }
}

struct StartGolfRoundIntent: StartWorkoutIntent {
    static let title: LocalizedStringResource = "Start Golf Round"
    static let suggestedWorkouts: [StartGolfRoundIntent] = [
        StartGolfRoundIntent(style: .golf),
    ]

    @Parameter(title: "Round Length")
    var workoutStyle: GolfRoundStyle

    init() {
        workoutStyle = .golf
    }

    var displayRepresentation: DisplayRepresentation {
        GolfRoundStyle.caseDisplayRepresentations[workoutStyle]
            ?? DisplayRepresentation(title: "Golf Round")
    }

    func perform() async throws -> some IntentResult {
        guard let appModelContainer else {
            intentLog.fault("Cannot start round because the model container is unavailable")
            return .result()
        }

        let context = ModelContext(appModelContainer)
        var descriptor = FetchDescriptor<Round>(
            predicate: #Predicate { $0.isComplete == false },
            sortBy: [SortDescriptor(\Round.date, order: .reverse)]
        )
        descriptor.fetchLimit = 1

        do {
            if try context.fetch(descriptor).isEmpty {
                let round = Round(
                    date: .now,
                    courseName: nil,
                    numberOfHoles: workoutStyle.holeCount,
                    pars: Array(repeating: 4, count: workoutStyle.holeCount)
                )
                context.insert(round)
                try context.save()
                intentLog.info("Created a \(workoutStyle.holeCount)-hole quick round")
            }
        } catch {
            intentLog.error("Unable to create or fetch active round: \(error.localizedDescription)")
            return .result()
        }

        await WorkoutManager.shared.startWorkout()
        // WorkoutManager donates the shot intent after the HealthKit session is
        // running, covering both Action Button and in-app starts.
        return .result()
    }
}

/// Silent, one-press shot logging for the active hole. Haptics and the live
/// counter provide feedback without a dialog covering the score.
struct ShotCountIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Golf Shot"
    static let description = IntentDescription("Increment the shot count for the current hole.")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult {
        guard let appModelContainer else {
            intentLog.fault("Cannot log shot because the model container is unavailable")
            return .result()
        }

        let context = ModelContext(appModelContainer)
        var descriptor = FetchDescriptor<Round>(
            predicate: #Predicate { $0.isComplete == false },
            sortBy: [SortDescriptor(\Round.date, order: .reverse)]
        )
        descriptor.fetchLimit = 1

        do {
            guard let round = try context.fetch(descriptor).first,
                  let hole = round.currentHole else {
                intentLog.info("Shot ignored because there is no active round")
                return .result()
            }

            hole.incrementShot()
            try context.save()

            let holeID = hole.id
            let shots = hole.shots
            let holeNumber = hole.holeNumber
            await MainActor.run {
                WKInterfaceDevice.current().play(.click)
                NotificationCenter.default.post(
                    name: .rondeShotDidChange,
                    object: nil,
                    userInfo: ["holeID": holeID, "shots": shots]
                )
            }
            intentLog.debug("Shot \(shots) logged on hole \(holeNumber)")
        } catch {
            intentLog.error("Shot logging failed: \(error.localizedDescription)")
        }

        return .result()
    }
}

struct RondeShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ShotCountIntent(),
            phrases: [
                "Log a shot in \(.applicationName)",
                "Count a shot in \(.applicationName)",
            ],
            shortTitle: "Log Shot",
            systemImageName: "figure.golf"
        )
    }
}
