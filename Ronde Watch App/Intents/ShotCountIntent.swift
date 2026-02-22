import AppIntents
import SwiftData
import WatchKit
import os.log

private let log = Logger(subsystem: "com.ronde.Ronde", category: "ShotCountIntent")

/// Logs a golf shot for the active round's current hole.
///
/// Triggered by:
/// - Apple Watch Ultra Action Button (via Shortcuts → assign this action)
/// - Siri: "Log a shot in Ronde"
/// - Shortcuts app
struct ShotCountIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Golf Shot"
    static let description = IntentDescription("Increment the shot count for the current hole.")
    static let openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult & ProvidesDialog {
        // Build a ModelContainer with the same schema and default store location
        // as the main app so we write to the same persistent store on disk.
        let schema = Schema([Round.self, HoleScore.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        let container: ModelContainer
        do {
            container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            log.error("ModelContainer init failed: \(error.localizedDescription)")
            return .result(dialog: "Unable to access round data")
        }

        let context = ModelContext(container)

        // Fetch the most recent incomplete round
        var descriptor = FetchDescriptor<Round>(
            predicate: #Predicate { $0.isComplete == false },
            sortBy: [SortDescriptor(\Round.date, order: .reverse)]
        )
        descriptor.fetchLimit = 1

        let activeRounds: [Round]
        do {
            activeRounds = try context.fetch(descriptor)
        } catch {
            log.error("Fetch failed: \(error.localizedDescription)")
            return .result(dialog: "Unable to find active round")
        }

        guard let round = activeRounds.first, let hole = round.currentHole else {
            log.info("No active round")
            return .result(dialog: "No active round")
        }

        hole.incrementShot()

        do {
            try context.save()
        } catch {
            log.error("Save failed: \(error.localizedDescription)")
        }

        let shots = hole.shots
        let holeNumber = hole.holeNumber

        // Trigger haptic on the main thread (crisp click matches the on-screen + button)
        await MainActor.run {
            WKInterfaceDevice.current().play(.click)
        }

        log.debug("Shot \(shots) logged on hole \(holeNumber)")
        return .result(dialog: "Shot \(shots) on hole \(holeNumber)")
    }
}

/// Registers shortcuts so this action appears in the Shortcuts app
/// and can be assigned to the Apple Watch Ultra Action Button.
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
