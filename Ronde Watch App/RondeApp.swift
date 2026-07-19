import SwiftUI
import SwiftData
import WatchKit
import os

private let persistenceLog = Logger(subsystem: "com.ronde.Ronde", category: "Persistence")

enum PersistenceMode: Sendable {
    case primary
    case recovered
    case temporary
    case unavailable

    var notice: String? {
        switch self {
        case .primary:
            return nil
        case .recovered:
            return "Round history was recovered into a new local store."
        case .temporary:
            return "Rounds cannot be saved permanently right now."
        case .unavailable:
            return "Ronde could not open its local round data."
        }
    }
}

/// Builds the shared SwiftData container without turning a recoverable store
/// problem into a launch crash. A damaged primary store is left untouched and
/// a deterministic recovery store is used, so later launches keep the new data.
struct PersistenceRuntime: @unchecked Sendable {
    let container: ModelContainer?
    let mode: PersistenceMode

    init() {
        let fileManager = FileManager.default
        let supportDirectory = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first
        if let supportDirectory {
            do {
                try fileManager.createDirectory(
                    at: supportDirectory,
                    withIntermediateDirectories: true
                )
            } catch {
                persistenceLog.error("Application Support could not be prepared: \(error.localizedDescription)")
            }
        }

        let schema = Schema([Round.self, HoleScore.self])
        let primary = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            container = try ModelContainer(for: schema, configurations: [primary])
            mode = .primary
            return
        } catch {
            persistenceLog.fault("Primary store failed to open: \(error.localizedDescription)")
        }

        if let support = supportDirectory {
            do {
                try fileManager.createDirectory(at: support, withIntermediateDirectories: true)
                let recoveryURL = support.appendingPathComponent("Ronde-Recovery.store")
                let recovery = ModelConfiguration(
                    "RondeRecovery",
                    schema: schema,
                    url: recoveryURL,
                    cloudKitDatabase: .none
                )
                container = try ModelContainer(for: schema, configurations: [recovery])
                mode = .recovered
                persistenceLog.warning("Using recovery store at \(recoveryURL.path, privacy: .private)")
                return
            } catch {
                persistenceLog.fault("Recovery store failed to open: \(error.localizedDescription)")
            }
        }

        do {
            let temporary = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            container = try ModelContainer(for: schema, configurations: [temporary])
            mode = .temporary
        } catch {
            persistenceLog.fault("In-memory store failed to initialise: \(error.localizedDescription)")
            container = nil
            mode = .unavailable
        }
    }
}

let persistenceRuntime = PersistenceRuntime()
let appModelContainer = persistenceRuntime.container

@MainActor
final class RondeApplicationDelegate: NSObject, WKApplicationDelegate {
    func handleActiveWorkoutRecovery() {
        Task { await WorkoutManager.shared.recoverActiveWorkout() }
    }
}

@main
struct RondeApp: App {
    @WKApplicationDelegateAdaptor(RondeApplicationDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            if let container = appModelContainer {
                appRoot
                    .modelContainer(container)
                    .preferredColorScheme(.dark)
                    .tint(Theme.fairway)
            } else {
                StorageUnavailableView()
                    .preferredColorScheme(.dark)
            }
        }
    }

    @ViewBuilder
    private var appRoot: some View {
#if DEBUG
        if let previewScreen = ProcessInfo.processInfo.environment["RONDE_PREVIEW_SCREEN"] {
            RondePreviewRouter(screen: previewScreen)
        } else {
            ContentView()
        }
#else
        ContentView()
#endif
    }
}

private struct StorageUnavailableView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "externaldrive.badge.exclamationmark")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(Theme.rough)
            Text("Round data unavailable")
                .font(.titleSmall)
                .multilineTextAlignment(.center)
            Text("Restart your watch, then open Ronde again.")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .fairwayBackground()
    }
}
