import SwiftUI

/// Minimal iOS companion app.
/// Ronde runs independently on Apple Watch (WKRunsIndependentlyOfCompanionApp = YES),
/// but this target is required so Xcode validates the watch app bundle ID correctly:
///   iOS companion: com.ronde
///   Watch app:     com.ronde.Ronde  (prefixed by "com.ronde.")
@main
struct RondeCompanionApp: App {
    var body: some Scene {
        WindowGroup {
            Text("Ronde")
        }
    }
}
