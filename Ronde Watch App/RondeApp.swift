import SwiftUI
import SwiftData

/// Module-level constant — not actor-isolated, accessible from any concurrency
/// context (including AppIntents) without Swift 6 actor errors.
/// Swift guarantees thread-safe lazy initialization for module-level lets.
let appModelContainer: ModelContainer = {
    let schema = Schema([Round.self, HoleScore.self])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
    do {
        return try ModelContainer(for: schema, configurations: [config])
    } catch {
        fatalError("Could not create ModelContainer: \(error)")
    }
}()

@main
struct RondeApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(appModelContainer)
    }
}
