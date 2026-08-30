import Foundation
import SwiftUI

/// Ronde's universal iPhone and iPad Shot Reviewer.
///
/// The watch app remains independently functional. This target now owns the
/// light reviewer workspace while Terra's capture and analysis services are
/// connected through the narrow adapters in Features.
@main
struct RondeCompanionApp: App {
    @StateObject private var store: ReviewerStore
    @StateObject private var accountStore: RondeAccountStore
    private let isQuickReviewPreview: Bool
    private let isMediaDetailPreview: Bool
    private let isTracerEditorPreview: Bool
    private let isSignInPreview: Bool
    private let initialTab: RondeAppTab

    init() {
        #if DEBUG
        let previewScreen = ProcessInfo.processInfo.environment["RONDE_PREVIEW_SCREEN"]
        let fixtureScreens = [
            "ios-quick-review",
            "ios-redesign-home",
            "ios-redesign-library",
            "ios-redesign-profile",
            "ios-redesign-media",
            "ios-redesign-tracer"
        ]
        let includeFixture = previewScreen.map(fixtureScreens.contains) ?? false
        let previewSourceURL = ProcessInfo.processInfo.environment["RONDE_PREVIEW_VIDEO_PATH"]
            .flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
        #else
        let previewScreen: String? = nil
        let includeFixture = false
        let previewSourceURL: URL? = nil
        #endif
        isQuickReviewPreview = previewScreen == "ios-quick-review"
        isMediaDetailPreview = previewScreen == "ios-redesign-media"
        isTracerEditorPreview = previewScreen == "ios-redesign-tracer"
        isSignInPreview = previewScreen == "ios-redesign-signin"
        switch previewScreen {
        case "ios-redesign-library": initialTab = .library
        case "ios-redesign-profile": initialTab = .profile
        default: initialTab = .home
        }
        _store = StateObject(wrappedValue: ReviewerStore(
            includeFixtures: includeFixture,
            previewSourceURL: previewSourceURL,
            persistenceEnabled: !includeFixture
        ))
        _accountStore = StateObject(wrappedValue: RondeAccountStore(
            previewAccount: includeFixture
                ? RondeAccount(
                    id: UUID(uuidString: "8A8299A4-E7B4-4A5D-B2B1-E5121F3A1AF2")!,
                    displayName: "Ronde Golfer",
                    email: "golfer@example.com"
                )
                : nil
        ))
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if isSignInPreview {
                    RondeSignInView(accountStore: accountStore)
                } else if isTracerEditorPreview,
                          let session = store.selectedSession,
                          let candidate = session.defaultCandidate {
                    FullScreenTracerEditor(store: store, session: session, candidate: candidate)
                } else if isQuickReviewPreview, let session = store.selectedSession {
                    NavigationStack {
                        SessionWorkspaceView(store: store, session: session)
                    }
                } else if isMediaDetailPreview, let session = store.selectedSession {
                    NavigationStack {
                        RondeMediaDetailRoute(store: store, accountStore: accountStore, sessionID: session.id)
                    }
                } else {
                    RondeRootView(store: store, accountStore: accountStore, initialTab: initialTab)
                }
            }
                .tint(RondeReviewDesign.fairway)
                .preferredColorScheme(.light)
        }
    }
}

#Preview("Review library") {
    RondeRootView(
        store: ReviewerStore(includeFixtures: true),
        accountStore: RondeAccountStore(previewAccount: RondeAccount(
            id: UUID(),
            displayName: "Ronde Golfer",
            email: "golfer@example.com"
        ))
    )
}

#Preview("Empty library") {
    RondeRootView(
        store: ReviewerStore(includeFixtures: false),
        accountStore: RondeAccountStore(previewAccount: RondeAccount(
            id: UUID(),
            displayName: "Ronde Golfer",
            email: nil
        ))
    )
}
