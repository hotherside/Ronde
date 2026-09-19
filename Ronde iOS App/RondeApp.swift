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
            "ios-recording-studio",
            "ios-concept-home",
            "ios-concept-library",
            "ios-concept-media",
            "ios-concept-recording"
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
        isMediaDetailPreview = previewScreen == "ios-redesign-media" || previewScreen == "ios-concept-media"
        isTracerEditorPreview = previewScreen == "ios-redesign-tracer"
        isSignInPreview = previewScreen == "ios-redesign-signin"
        isRecordingPreview = previewScreen == "ios-recording-studio" || previewScreen == "ios-concept-recording"
        switch previewScreen {
        case "ios-redesign-library", "ios-concept-library": initialTab = .library
        case "ios-redesign-profile": initialTab = .profile
        default: initialTab = .home
        }
        let reviewStore = ReviewerStore(
            includeFixtures: includeFixture,
            previewSourceURL: previewSourceURL,
            persistenceEnabled: !includeFixture
        )
        #if DEBUG
        if previewScreen?.hasPrefix("ios-concept-") == true {
            let secondaryURL = ProcessInfo.processInfo.environment["RONDE_PREVIEW_SECONDARY_VIDEO_PATH"]
                .flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
            reviewStore.sessions = Self.conceptSessions(sourceURL: previewSourceURL, secondaryURL: secondaryURL)
            if let shot = reviewStore.sessions.first(where: { !$0.isRecording }) { reviewStore.select(shot) }
        } else if isRecordingPreview {
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

    #if DEBUG
    /// Populated visual-review data uses fictional concept stills encoded as local movies.
    /// It never opens an archive, starts tracking, or enters a release build.
    private static func conceptSessions(sourceURL: URL?, secondaryURL: URL?) -> [ReviewSession] {
        let groupID = UUID(uuidString: "090F916A-C8E4-449C-B159-990051228290")!
        let previousID = UUID(uuidString: "090F916A-C8E4-449C-B159-990051228291")!
        let recordingID = UUID(uuidString: "090F916A-C8E4-449C-B159-990051228292")!
        let bookmark = RecordingBookmark(sourceTime: 6)
        let date = Date(timeIntervalSince1970: 1_789_727_400)
        let recording = ReviewSession(
            id: recordingID, mode: .range, importKind: .recording,
            title: "The Friday bucket", sourceName: "Range camera 01.mov", sourceURL: sourceURL,
            createdAt: date, duration: 16, sourceAspectRatio: 1.5, status: .reviewing,
            progress: 1, candidates: [], placeName: "Moore Park, Sydney", errorMessage: nil,
            groupID: groupID, groupTitle: "The Friday bucket",
            storedBookmarks: [bookmark, RecordingBookmark(sourceTime: 10)]
        )
        let second = ReviewSession(
            id: UUID(uuidString: "090F916A-C8E4-449C-B159-990051228293")!,
            mode: .range, importKind: .recording, title: recording.title,
            sourceName: "Range camera 02.mov", sourceURL: sourceURL, createdAt: date.addingTimeInterval(-1),
            duration: 16, sourceAspectRatio: 1.5, status: .reviewing, progress: 1,
            candidates: [], errorMessage: nil, groupID: groupID, groupTitle: recording.title
        )
        let older = ReviewSession(
            id: previousID, mode: .range, importKind: .recording, title: "Sunday, by the sea",
            sourceName: "Coastal nine.mov", sourceURL: secondaryURL ?? sourceURL,
            createdAt: date.addingTimeInterval(-432_000), duration: 16, sourceAspectRatio: 1.5,
            status: .reviewing, progress: 1, candidates: [], placeName: "The coast, NSW",
            errorMessage: nil, groupID: previousID, groupTitle: "Sunday, by the sea"
        )
        let shots = ["That finish.", "Right on line.", "One for the reel.", "Last ball, best ball."].enumerated().map { index, title in
            let coastal = index == 1
            let candidate = ReviewCandidate(ordinal: index + 1, impactTime: 6, sourceDuration: 16,
                                            classification: .uncertain, confidence: .low,
                                            evidence: ["Fictional visual-review fixture"], decision: .kept)
            return ReviewSession(
                id: UUID(uuidString: String(format: "090F916A-C8E4-449C-B159-9900512283%02d", index))!,
                mode: .range, importKind: .oneShot, title: title, sourceName: coastal ? older.sourceName : recording.sourceName,
                sourceURL: coastal ? older.sourceURL : sourceURL, createdAt: date.addingTimeInterval(-Double(index)),
                duration: 16, sourceAspectRatio: 1.5, status: .complete, progress: 1, candidates: [candidate],
                placeName: coastal ? "The coast" : "Moore Park", clubName: index == 2 ? "Driver" : "7 iron",
                isFavourite: index < 2, errorMessage: nil, groupID: coastal ? previousID : groupID,
                groupTitle: coastal ? older.title : recording.title,
                sourceRecordingID: coastal ? previousID : recordingID,
                sourceBookmarkID: index == 0 ? bookmark.id : nil,
                sourceClipRange: ReviewTimeRange(start: 1, duration: 10)
            )
        }
        return [recording, second, older] + shots
    }
    #endif

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
