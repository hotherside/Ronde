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
        // Reuse the app's shared ModelContainer so the intent context and the
        // app's main context share the same NSPersistentStoreCoordinator.
        // Saves from here trigger NSManagedObjectContextDidSave on the main
        // context, keeping @Bindable / @Query up-to-date without extra glue.
        let context = ModelContext(RondeApp.sharedModelContainer)

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

        // Dedup: skip if swing was auto-detected within the last 2 seconds
        let swingRecent = await MainActor.run {
            SwingDetector.shared.wasSwingDetectedWithin(seconds: 2.0)
        }
        if swingRecent {
            let shots = hole.shots
            let holeNumber = hole.holeNumber
            log.debug("Action Button skipped — swing already detected for hole \(holeNumber)")
            await MainActor.run {
                WKInterfaceDevice.current().play(.click)
            }
            return .result(dialog: "Shot \(shots) on hole \(holeNumber)")
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
