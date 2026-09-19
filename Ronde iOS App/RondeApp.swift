import Foundation
import SwiftUI

/// Ronde's universal iPhone and iPad shot media library and tracer.
@main
struct RondeApp: App {
    @StateObject private var store: ReviewerStore
    @StateObject private var accountStore: RondeAccountStore
    private let isQuickReviewPreview: Bool
    private let isMediaDetailPreview: Bool
    private let isTracerEditorPreview: Bool
    private let isSignInPreview: Bool
    private let isRecordingPreview: Bool
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
            "ios-redesign-tracer",
            "ios-recording-studio"
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
        isRecordingPreview = previewScreen == "ios-recording-studio"
        switch previewScreen {
        case "ios-redesign-library": initialTab = .library
        case "ios-redesign-profile": initialTab = .profile
        default: initialTab = .home
        }
        let reviewStore = ReviewerStore(
            includeFixtures: includeFixture,
            previewSourceURL: previewSourceURL,
            persistenceEnabled: !includeFixture
        )
        #if DEBUG
        if isRecordingPreview {
            let recording = ReviewSession(
                id: UUID(uuidString: "B5522071-A1C8-49D1-9D0B-1F37A852C427")!,
                mode: .range, importKind: .recording,
                title: "Saturday at the range", sourceName: "Studio test recording.mp4",
                sourceURL: previewSourceURL, createdAt: .now, duration: 6.634,
                sourceAspectRatio: 9.0 / 16, status: .reviewing, progress: 1, candidates: [],
                errorMessage: nil, groupTitle: "Saturday at the range"
            )
            reviewStore.sessions = [recording]
            reviewStore.select(recording)
        }
        #endif
        _store = StateObject(wrappedValue: reviewStore)
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
                } else if isRecordingPreview, let recording = store.sessions.first(where: \.isRecording) {
                    RecordingStudioPreviewRoute(store: store, accountStore: accountStore, recordingID: recording.id)
                } else if isTracerEditorPreview,
                          let session = store.selectedSession,
                          let candidate = session.defaultCandidate {
                    FullScreenTracerEditor(store: store, session: session, candidate: candidate)
                } else if isQuickReviewPreview, let session = store.selectedSession {
                    NavigationStack {
                        RondeMediaDetailRoute(store: store, accountStore: accountStore, sessionID: session.id)
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

private struct RecordingStudioPreviewRoute: View {
    @ObservedObject var store: ReviewerStore
    @ObservedObject var accountStore: RondeAccountStore
    let recordingID: UUID
    @State private var path: [UUID] = []

    var body: some View {
        NavigationStack(path: $path) {
            RecordingStudioView(store: store, accountStore: accountStore, recordingID: recordingID) { path.append($0) }
                .navigationDestination(for: UUID.self) { shotID in
                    RondeMediaDetailRoute(store: store, accountStore: accountStore, sessionID: shotID)
                }
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
