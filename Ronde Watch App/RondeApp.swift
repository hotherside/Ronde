import SwiftUI
import SwiftData

@main
struct RondeApp: App {
    nonisolated(unsafe) static let sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Round.self,
            HoleScore.self,
        ])
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
        )

        do {
            return try ModelContainer(
                for: schema,
                configurations: [modelConfiguration]
            )
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(RondeApp.sharedModelContainer)
    }
}
