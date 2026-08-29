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
    private let isQuickReviewPreview: Bool

    init() {
        #if DEBUG
        let includeFixture = ProcessInfo.processInfo.environment["RONDE_PREVIEW_SCREEN"] == "ios-quick-review"
        let previewSourceURL = ProcessInfo.processInfo.environment["RONDE_PREVIEW_VIDEO_PATH"]
            .flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
        #else
        let includeFixture = false
        let previewSourceURL: URL? = nil
        #endif
        isQuickReviewPreview = includeFixture
        _store = StateObject(wrappedValue: ReviewerStore(
            includeFixtures: includeFixture,
            previewSourceURL: previewSourceURL
        ))
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if isQuickReviewPreview, let session = store.selectedSession {
                    NavigationStack {
                        SessionWorkspaceView(store: store, session: session)
                    }
                } else {
                    RondeLibraryView(store: store)
                }
            }
                .tint(RondeReviewDesign.fairway)
                .preferredColorScheme(.light)
        }
    }
}

#Preview("Review library") {
    RondeLibraryView(store: ReviewerStore(includeFixtures: true))
}

#Preview("Empty library") {
    RondeLibraryView(store: ReviewerStore(includeFixtures: false))
}
