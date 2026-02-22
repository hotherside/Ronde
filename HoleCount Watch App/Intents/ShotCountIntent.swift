import AppIntents

/// App Intent for logging a golf shot via Action Button or Shortcuts.
///
/// Users can assign this to:
/// - Apple Watch Ultra Action Button (via Shortcuts in watchOS 11+)
/// - Siri: "Log a shot in HoleCount"
///
/// TODO: Session 3 - Connect to active round's current hole
/// and increment the shot count. For now this is a scaffold.
struct ShotCountIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Golf Shot"
    static var description = IntentDescription("Increment the shot count for the current hole.")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult & ProvidesDialog {
        // TODO: Session 3 - Access shared model container,
        // find active round, increment current hole shots,
        // trigger haptic feedback
        return .result(dialog: "Shot logged!")
    }
}

/// Registers the app's shortcuts so they appear in the Shortcuts app
/// and can be assigned to the Action Button.
struct HoleCountShortcuts: AppShortcutsProvider {
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
