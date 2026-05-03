import SwiftUI
import SwiftData

/// Module-level constant — not actor-isolated, accessible from any concurrency
/// context (including AppIntents) without Swift 6 actor errors.
/// Swift guarantees thread-safe lazy initialization for module-level lets.
let appModelContainer: ModelContainer = {
    // Ensure Application Support directory exists before SwiftData/CoreData
    // tries to create the store file. On first launch this directory may not
    // exist, causing noisy "Failed to stat path" / "errno 2" errors.
    let fileManager = FileManager.default
    if let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
        try? fileManager.createDirectory(at: appSupport, withIntermediateDirectories: true)
    }

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
                .preferredColorScheme(.light)
                .tint(.white)
        }
        .modelContainer(appModelContainer)
    }
}
