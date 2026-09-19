import AVFoundation
import Foundation
import XCTest
@testable import Ronde

final class ReviewLibrarySafetyTests: XCTestCase {
    func testCorruptArchiveCannotBeOverwrittenAfterFailedLoad() throws {
        let root = try makeRoot()
        let url = archiveURL(root: root)
        let bytes = Data("[{\"createdAt\":{\"invalid\":true}}]".utf8)
        try bytes.write(to: url)
        let archive = try ReviewSessionArchive(rootURL: root)

        guard case .failed(.corrupted) = archive.read() else {
            return XCTFail("A decode failure must be distinct from an empty library")
        }
        XCTAssertThrowsError(try archive.save([ReviewFixtures.quickReviewSession])) { error in
            XCTAssertEqual(error as? ReviewSessionArchive.ArchiveError, .writeBlocked)
        }
        XCTAssertEqual(try Data(contentsOf: url), bytes)
    }

    func testSavingBeforeReadingCannotBypassCorruptionGate() throws {
        let root = try makeRoot()
        let url = archiveURL(root: root)
        let bytes = Data("not-json".utf8)
        try bytes.write(to: url)

        let archive = try ReviewSessionArchive(rootURL: root)
        XCTAssertThrowsError(try archive.save([]))
        XCTAssertEqual(try Data(contentsOf: url), bytes)
    }

    func testUnreadableArchiveRequiresSuccessfulReadBeforeSaving() throws {
        let root = try makeRoot()
        let url = archiveURL(root: root)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        let archive = try ReviewSessionArchive(rootURL: root)

        guard case .failed(.unreadable) = archive.read() else {
            return XCTFail("An unreadable file must not be reported as missing")
        }
        XCTAssertThrowsError(try archive.save([]))
        try FileManager.default.removeItem(at: url)
        guard case .missing = archive.read() else { return XCTFail("Storage is now available") }
        try archive.save([ReviewFixtures.quickReviewSession])
        XCTAssertEqual(archive.load().count, 1)
    }

    func testSavedMediaRebasesAfterTheWholeLibraryMoves() throws {
        let parent = try makeRoot()
        let firstRoot = parent.appendingPathComponent("first/RondeShotReview", isDirectory: true)
        let secondRoot = parent.appendingPathComponent("second/RondeShotReview", isDirectory: true)
        let archive = try ReviewSessionArchive(rootURL: firstRoot)
        let source = firstRoot.appendingPathComponent("sources/synthetic.mov")
        try FileManager.default.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("synthetic media".utf8).write(to: source)
        var session = ReviewFixtures.quickReviewSession
        session.sourceURL = source
        try archive.save([session])
        let encoded = try Data(contentsOf: archiveURL(root: firstRoot))
        let rows = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [[String: Any]])
        XCTAssertNil(rows.first?["sourceURL"])
        XCTAssertEqual(rows.first?["sourceRelativePath"] as? String, "sources/synthetic.mov")

        try FileManager.default.createDirectory(at: secondRoot.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: firstRoot, to: secondRoot)
        let restored = try XCTUnwrap(ReviewSessionArchive(rootURL: secondRoot).load().first)
        XCTAssertEqual(restored.sourceURL, secondRoot.appendingPathComponent("sources/synthetic.mov"))
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(restored.sourceURL)), Data("synthetic media".utf8))
    }

    func testLegacyAbsoluteURLMigratesAndMissingEditFieldRemainsCompatible() throws {
        let root = try makeRoot()
        var session = ReviewFixtures.quickReviewSession
        session.sourceURL = URL(fileURLWithPath: "/SYNTHETIC/old-container/RondeShotReview/sources/legacy.mov")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var rows = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode([session])) as? [[String: Any]])
        rows[0].removeValue(forKey: "sourceRelativePath")
        rows[0].removeValue(forKey: "videoEdit")
        try JSONSerialization.data(withJSONObject: rows).write(to: archiveURL(root: root))

        let archive = try ReviewSessionArchive(rootURL: root)
        let restored = try XCTUnwrap(archive.load().first)
        XCTAssertNil(restored.videoEdit)
        XCTAssertEqual(restored.sourceURL, root.appendingPathComponent("sources/legacy.mov"))
        XCTAssertEqual(restored.sourceRelativePath, "sources/legacy.mov")
        try archive.save([restored])
        let encoded = try String(contentsOf: archiveURL(root: root), encoding: .utf8)
        XCTAssertFalse(encoded.contains("old-container"))
    }

    func testLegacyArchiveWithoutRecordingFieldsStillDecodesAndNewBookmarksRoundTrip() throws {
        let root = try makeRoot()
        var legacy = ReviewFixtures.quickReviewSession
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var rows = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode([legacy])) as? [[String: Any]])
        for key in ["groupID", "groupTitle", "sourceRecordingID", "sourceBookmarkID", "sourceClipRange", "storedBookmarks", "storedBookmarkWindow"] {
            rows[0].removeValue(forKey: key)
        }
        try JSONSerialization.data(withJSONObject: rows).write(to: archiveURL(root: root))

        let archive = try ReviewSessionArchive(rootURL: root)
        let restoredLegacy = try XCTUnwrap(archive.load().first)
        XCTAssertTrue(restoredLegacy.bookmarks.isEmpty)
        XCTAssertNil(restoredLegacy.sourceClipRange)
        XCTAssertEqual(restoredLegacy.bookmarkWindow, .standard)

        legacy.importKind = .recording
        legacy.groupID = legacy.id
        legacy.groupTitle = "Saturday practice"
        legacy.bookmarks = [RecordingBookmark(sourceTime: 20)]
        try archive.save([legacy])
        let restoredRecording = try XCTUnwrap(archive.load().first)
        XCTAssertEqual(restoredRecording.groupID, legacy.id)
        XCTAssertEqual(restoredRecording.groupTitle, "Saturday practice")
        XCTAssertEqual(restoredRecording.bookmarks.map(\.sourceTime), [20])
    }

    func testInvalidRelativeMediaPathCannotEscapeItsLibrary() throws {
        let root = try makeRoot()
        var session = ReviewFixtures.quickReviewSession
        session.sourceRelativePath = "sources/../../another-account.mov"
        session.sourceURL = URL(fileURLWithPath: "/SYNTHETIC/external.mov")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode([session]).write(to: archiveURL(root: root))

        let restored = try XCTUnwrap(ReviewSessionArchive(rootURL: root).load().first)
        XCTAssertNil(restored.sourceURL)
    }

    @MainActor
    func testCorruptAccountLibraryExposesErrorAndRejectsNewImports() async throws {
        let root = try makeRoot()
        let account = UUID()
        let bytes = Data("broken account archive".utf8)
        try bytes.write(to: archiveURL(root: root, accountID: account))
        let store = ReviewerStore(persistenceEnabled: true, libraryRootURL: root)
        store.activateLibrary(for: account)

        XCTAssertFalse(store.canModifyLibrary)
        XCTAssertNotNil(store.libraryError)
        XCTAssertNil(store.captureImportOwnership())
        let result = await store.importVideo(at: root.appendingPathComponent("missing.mov"), sourceName: "Synthetic", importKind: .oneShot)
        guard case .failed = result else { return XCTFail("A locked library must reject import") }
        XCTAssertEqual(try Data(contentsOf: archiveURL(root: root, accountID: account)), bytes)
    }

    @MainActor
    func testFailedSaveRetainsUnsavedEditsAndRetryPersistsThem() throws {
        let root = try makeRoot()
        let account = UUID()
        let session = ReviewFixtures.quickReviewSession
        let archive = try ReviewSessionArchive(accountID: account, rootURL: root)
        try archive.save([session])
        let store = ReviewerStore(persistenceEnabled: true, libraryRootURL: root)
        store.activateLibrary(for: account)
        let url = archiveURL(root: root, accountID: account)
        try FileManager.default.removeItem(at: url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)

        store.toggleFavourite(session)
        XCTAssertTrue(store.hasUnsavedChanges)
        XCTAssertNotNil(store.libraryError)
        XCTAssertEqual(store.sessions.first?.isFavourite, !session.isFavourite)
        try FileManager.default.removeItem(at: url)
        store.retrySavingLibrary()
        XCTAssertFalse(store.hasUnsavedChanges)
        XCTAssertNil(store.libraryError)
        XCTAssertEqual(archive.load().first?.isFavourite, !session.isFavourite)
    }

    @MainActor
    func testFailedBookmarkExtractionRollsBackTheEntireBatch() throws {
        let root = try makeRoot()
        let account = UUID()
        var recording = ReviewFixtures.quickReviewSession
        recording.importKind = .recording
        recording.groupID = recording.id
        recording.groupTitle = recording.title
        try ReviewSessionArchive(accountID: account, rootURL: root).save([recording])
        let store = ReviewerStore(persistenceEnabled: true, libraryRootURL: root)
        store.activateLibrary(for: account)
        let openRecording = try XCTUnwrap(store.sessions.first)
        XCTAssertNotNil(store.addBookmark(at: 3, to: openRecording))

        let url = archiveURL(root: root, accountID: account)
        try FileManager.default.removeItem(at: url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)

        XCTAssertTrue(store.createShots(from: openRecording).isEmpty)
        XCTAssertEqual(store.sessions.map(\.id), [recording.id])
        XCTAssertNotNil(store.libraryError)
    }

    @MainActor
    func testRecordingImportPersistsTwentyMinuteSourceAndCreatesBoundedManualShot() async throws {
        let root = try makeRoot()
        let source = root.appendingPathComponent("twenty-minute-source.mov")
        try await writeSparseVideo(to: source, endSessionAt: 1_200)
        let originalBytes = try Data(contentsOf: source)
        let account = UUID()
        let store = ReviewerStore(persistenceEnabled: true, libraryRootURL: root)
        store.activateLibrary(for: account)

        let result = await store.importVideo(
            at: source,
            sourceName: "Twenty minute practice.mov",
            importKind: .recording
        )
        guard case .imported(let imported) = result else {
            return XCTFail("A valid recording should be copied and persisted without analysis: \(String(describing: result))")
        }
        let recording = try XCTUnwrap(store.sessions.first { $0.id == imported.id })
        XCTAssertTrue(recording.isRecording)
        XCTAssertGreaterThanOrEqual(recording.duration, 1_199)
        XCTAssertLessThanOrEqual(recording.duration, RecordingImportPolicy.maximumDuration)
        XCTAssertNil(recording.errorMessage)
        XCTAssertNotEqual(recording.sourceURL, source)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        XCTAssertEqual(try Data(contentsOf: source), originalBytes)

        let bookmark = try XCTUnwrap(store.addBookmark(at: 600, to: recording))
        let shotID = try XCTUnwrap(store.createShots(from: recording, bookmarkIDs: [bookmark.id]).first)
        let shot = try XCTUnwrap(store.sessions.first { $0.id == shotID })
        XCTAssertEqual(shot.sourceClipRange, ReviewTimeRange(start: 595, duration: 10))
        XCTAssertEqual(shot.videoEdit?.sourceRange, ReviewTimeRange(start: 595, duration: 10))
        XCTAssertEqual(try XCTUnwrap(ReviewSessionArchive(accountID: account, rootURL: root).load().first { $0.id == shotID }).sourceClipRange,
                       ReviewTimeRange(start: 595, duration: 10))
    }

    @MainActor
    func testRecordingImportUnderTwentySecondsBecomesDirectShotWithoutAnalysis() async throws {
        let root = try makeRoot()
        let source = root.appendingPathComponent("short-source.mov")
        try await writeSparseVideo(to: source, endSessionAt: 19)
        let store = ReviewerStore(persistenceEnabled: true, libraryRootURL: root)
        store.activateLibrary(for: UUID())

        let result = await store.importVideo(at: source, sourceName: "Short shot.mov", importKind: .recording)
        guard case .imported(let imported) = result else {
            return XCTFail("A short recording should be ready directly in Shot Studio: \(String(describing: result))")
        }
        XCTAssertTrue(imported.isSingleShotImport)
        XCTAssertTrue(imported.isDirectShotImport)
        XCTAssertFalse(imported.isRecording)
        XCTAssertEqual(imported.status, .reviewing)
        XCTAssertEqual(imported.progress, 1)
        XCTAssertTrue(imported.bookmarks.isEmpty)
        XCTAssertEqual(store.sessions.first?.id, imported.id)
    }

    @MainActor
    func testTwentySecondRecordingStaysInChooseShotsFlow() async throws {
        let root = try makeRoot()
        let source = root.appendingPathComponent("boundary-source.mov")
        try await writeSparseVideo(to: source, endSessionAt: 20)
        let store = ReviewerStore(persistenceEnabled: true, libraryRootURL: root)
        store.activateLibrary(for: UUID())

        let result = await store.importVideo(at: source, sourceName: "Boundary recording.mov", importKind: .recording)
        guard case .imported(let imported) = result else {
            return XCTFail("A twenty-second recording should import for manual shot selection")
        }
        XCTAssertTrue(imported.isRecording)
        XCTAssertFalse(imported.isDirectShotImport)
        XCTAssertFalse(imported.isSingleShotImport)
        XCTAssertEqual(imported.status, .reviewing)
    }

    @MainActor
    func testBookmarkWindowIsPersistedAndIndividualOverridesRemainIndependent() throws {
        let root = try makeRoot()
        let account = UUID()
        let groupID = UUID()
        var recording = ReviewFixtures.quickReviewSession
        recording.importKind = .recording
        recording.groupID = groupID
        recording.groupTitle = recording.title
        var sibling = ReviewFixtures.rangeSession
        sibling.importKind = .recording
        sibling.groupID = groupID
        sibling.groupTitle = recording.title
        try ReviewSessionArchive(accountID: account, rootURL: root).save([recording, sibling])
        let store = ReviewerStore(persistenceEnabled: true, libraryRootURL: root)
        store.activateLibrary(for: account)
        let openRecording = try XCTUnwrap(store.sessions.first { $0.id == recording.id })

        XCTAssertTrue(store.updateBookmarkWindow(before: 10, after: 10, in: openRecording))
        XCTAssertEqual(store.sessions.first { $0.id == sibling.id }?.bookmarkWindow,
                       RecordingBookmarkWindow(beforeDuration: 10, afterDuration: 10))
        let defaultBookmark = try XCTUnwrap(store.addBookmark(at: 3, to: openRecording))
        let overriddenBookmark = try XCTUnwrap(store.addBookmark(at: 5, before: 2, after: 3, to: openRecording))
        XCTAssertEqual(defaultBookmark.beforeDuration, 10)
        XCTAssertEqual(defaultBookmark.afterDuration, 10)
        XCTAssertEqual(overriddenBookmark.beforeDuration, 2)
        XCTAssertEqual(overriddenBookmark.afterDuration, 3)

        let restored = try XCTUnwrap(ReviewSessionArchive(accountID: account, rootURL: root).load().first)
        XCTAssertEqual(restored.bookmarkWindow, RecordingBookmarkWindow(beforeDuration: 10, afterDuration: 10))
        XCTAssertEqual(restored.bookmark(id: defaultBookmark.id)?.beforeDuration, 10)
        XCTAssertEqual(restored.bookmark(id: overriddenBookmark.id)?.afterDuration, 3)
    }

    @MainActor
    func testNewRecordingInheritsItsGroupsBookmarkWindow() async throws {
        let root = try makeRoot()
        let account = UUID()
        let groupID = UUID()
        var existing = ReviewFixtures.rangeSession
        existing.importKind = .recording
        existing.groupID = groupID
        existing.groupTitle = "Saturday practice"
        existing.bookmarkWindow = RecordingBookmarkWindow(beforeDuration: 10, afterDuration: 10)
        try ReviewSessionArchive(accountID: account, rootURL: root).save([existing])
        let source = root.appendingPathComponent("inherited-window.mov")
        try await writeSparseVideo(to: source, endSessionAt: 20)
        let store = ReviewerStore(persistenceEnabled: true, libraryRootURL: root)
        store.activateLibrary(for: account)

        let result = await store.importVideo(
            at: source,
            sourceName: "Second recording.mov",
            importKind: .recording,
            groupID: groupID,
            groupTitle: "Saturday practice"
        )
        guard case .imported(let imported) = result else {
            return XCTFail("A new recording in the group should import successfully")
        }
        XCTAssertTrue(imported.isRecording)
        XCTAssertEqual(imported.bookmarkWindow, RecordingBookmarkWindow(beforeDuration: 10, afterDuration: 10))
    }

    @MainActor
    func testRecordingImportRejectsSourceLongerThanTwentyMinutes() async throws {
        let root = try makeRoot()
        let source = root.appendingPathComponent("too-long-source.mov")
        try await writeSparseVideo(to: source, endSessionAt: 1_201)
        let store = ReviewerStore(persistenceEnabled: true, libraryRootURL: root)
        store.activateLibrary(for: UUID())

        let result = await store.importVideo(at: source, sourceName: "Too long.mov", importKind: .recording)
        guard case .failed(let message) = result else { return XCTFail("A source longer than twenty minutes must be rejected") }
        XCTAssertTrue(message.contains("20 minutes"))
        XCTAssertTrue(store.sessions.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    @MainActor
    func testRelaunchOffersRecoveryForInterruptedAnalysis() throws {
        let root = try makeRoot()
        let account = UUID()
        var session = ReviewFixtures.quickReviewSession
        session.status = .analysing
        session.progress = 0.6
        try ReviewSessionArchive(accountID: account, rootURL: root).save([session])
        let store = ReviewerStore(persistenceEnabled: true, libraryRootURL: root)

        store.activateLibrary(for: account)
        XCTAssertEqual(store.sessions.first?.status, .needsAttention)
        XCTAssertEqual(store.sessions.first?.progress, 0)
        XCTAssertTrue(store.sessions.first?.errorMessage?.contains("interrupted") == true)
        XCTAssertEqual(store.sessions.first?.defaultCandidate?.evidenceAnchoredPath, session.defaultCandidate?.evidenceAnchoredPath)
    }

    @MainActor
    func testFailedDeletionKeepsTheSourceAndReview() async throws {
        let root = try makeRoot()
        let account = UUID()
        var session = ReviewFixtures.quickReviewSession
        let source = root.appendingPathComponent("sources/keep.mov")
        try FileManager.default.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("synthetic source".utf8).write(to: source)
        session.sourceURL = source
        try ReviewSessionArchive(accountID: account, rootURL: root).save([session])
        let store = ReviewerStore(persistenceEnabled: true, libraryRootURL: root)
        store.activateLibrary(for: account)
        let url = archiveURL(root: root, accountID: account)
        try FileManager.default.removeItem(at: url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)

        let deleted = await store.delete(session)
        XCTAssertFalse(deleted)
        XCTAssertEqual(store.sessions.first?.id, session.id)
        XCTAssertEqual(try Data(contentsOf: source), Data("synthetic source".utf8))
        XCTAssertNotNil(store.libraryError)
    }

    @MainActor
    func testDeletingASourceLinkedShotKeepsSharedRecordingMediaAndRootDeletionIsBlocked() async throws {
        let root = try makeRoot()
        let account = UUID()
        let source = root.appendingPathComponent("sources/recording.mov")
        try FileManager.default.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("shared source".utf8).write(to: source)
        var recording = ReviewFixtures.quickReviewSession
        recording.importKind = .recording
        recording.sourceURL = source
        recording.sourceRelativePath = "sources/recording.mov"
        recording.groupID = recording.id
        let shot = ReviewSession(
            id: UUID(), mode: .range, importKind: .oneShot, title: "Bookmark shot",
            sourceName: recording.sourceName, sourceURL: source, sourceRelativePath: "sources/recording.mov",
            videoEdit: ShotVideoEdit(trimStart: 10, trimEnd: 20, overlay: .original),
            createdAt: .now, duration: recording.duration, sourceAspectRatio: recording.sourceAspectRatio,
            status: .reviewing, progress: 1, candidates: [], groupID: recording.groupID,
            groupTitle: recording.title, sourceRecordingID: recording.id, sourceBookmarkID: UUID(),
            sourceClipRange: .init(start: 10, duration: 10), storedBookmarks: nil
        )
        try ReviewSessionArchive(accountID: account, rootURL: root).save([recording, shot])
        let store = ReviewerStore(persistenceEnabled: true, libraryRootURL: root)
        store.activateLibrary(for: account)

        let deletedRecording = await store.delete(recording)
        XCTAssertFalse(deletedRecording)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        let deletedShot = await store.delete(shot)
        XCTAssertTrue(deletedShot)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    @MainActor
    func testCopyFailureDoesNotMarkAnExistingSameNamedReviewAsFailed() async throws {
        let root = try makeRoot()
        let account = UUID()
        var session = ReviewFixtures.quickReviewSession
        session.title = "Same name"
        try ReviewSessionArchive(accountID: account, rootURL: root).save([session])
        let store = ReviewerStore(persistenceEnabled: true, libraryRootURL: root)
        store.activateLibrary(for: account)

        let result = await store.importVideo(at: root.appendingPathComponent("missing.mov"), sourceName: "Same name", importKind: .oneShot)
        guard case .failed = result else { return XCTFail("Missing source must return an import failure") }
        XCTAssertEqual(store.sessions.count, 1)
        XCTAssertEqual(store.selectedSessionID, session.id)
        XCTAssertEqual(store.sessions.first?.status, session.status)
        XCTAssertEqual(store.sessions.first?.errorMessage, session.errorMessage)
    }

    @MainActor
    func testManualRescueWithoutTimingRetainsTheFullOneShotVideo() throws {
        let store = ReviewerStore(includeFixtures: true)
        var session = try XCTUnwrap(store.sessions.first)
        session.candidates = []
        store.sessions = [session]
        store.playheadTime = session.duration / 2

        store.addManualMarker(in: session)
        let marker = try XCTUnwrap(store.sessions.first?.defaultCandidate)
        XCTAssertTrue(marker.usesFullSourceRange)
        XCTAssertEqual(marker.startTime, 0)
        XCTAssertEqual(marker.endTime, session.duration)
        XCTAssertFalse(marker.hasAutomaticTracer)
    }

    @MainActor
    func testPickerOwnershipFromAnotherAccountIsRejectedBeforeCopying() async throws {
        let root = try makeRoot()
        let media = SuspendedReviewMedia(root: root)
        let store = ReviewerStore(persistenceEnabled: true, libraryRootURL: root, mediaStore: media)
        store.activateLibrary(for: UUID())
        let owner = try XCTUnwrap(store.captureImportOwnership())
        store.deactivateLibrary()
        store.activateLibrary(for: UUID())

        let result = await store.importVideo(at: root.appendingPathComponent("synthetic.mov"), sourceName: "Synthetic", importKind: .oneShot, ownership: owner)
        guard case .cancelled = result else { return XCTFail("A stale picker must not import into the new account") }
        let count = await media.importCount
        XCTAssertEqual(count, 0)
        XCTAssertTrue(store.sessions.isEmpty)
    }

    @MainActor
    func testAccountSwitchDuringCopyDiscardsStagedMediaAndNeverAttachesToNewAccount() async throws {
        let root = try makeRoot()
        let media = SuspendedReviewMedia(root: root)
        let store = ReviewerStore(persistenceEnabled: true, libraryRootURL: root, mediaStore: media)
        store.activateLibrary(for: UUID())
        let owner = try XCTUnwrap(store.captureImportOwnership())
        let task = Task { await store.importVideo(at: root.appendingPathComponent("synthetic.mov"), sourceName: "Synthetic", importKind: .oneShot, ownership: owner) }
        await media.waitUntilStarted()
        store.deactivateLibrary()
        let nextAccount = UUID()
        store.activateLibrary(for: nextAccount)
        await media.completeCopy()
        let result = await task.value

        guard case .cancelled = result else { return XCTFail("Copy completion must retain its original account ownership") }
        XCTAssertTrue(store.sessions.isEmpty)
        XCTAssertFalse(store.isBusy)
        XCTAssertTrue(try ReviewSessionArchive(accountID: nextAccount, rootURL: root).load().isEmpty)
        let deleteCount = await media.deleteCount
        XCTAssertEqual(deleteCount, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("sources/staged.mov").path))
    }

    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ronde-library-safety-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }

    private func archiveURL(root: URL, accountID: UUID? = nil) -> URL {
        let name = accountID.map { "review-sessions-\($0.uuidString.lowercased())-v1.json" } ?? "review-sessions-v1.json"
        return root.appendingPathComponent(name)
    }

    /// Encodes only two small frames at distant source presentation times. `endSession` supplies
    /// the exact asset duration, so this is a real 20-minute metadata/import path without a large
    /// fixture or a 20-minute test run.
    @MainActor
    private func writeSparseVideo(to url: URL, endSessionAt endTime: TimeInterval) async throws {
        let width = 16
        let height = 16
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ])
        guard writer.canAdd(input) else { throw SparseVideoFixtureError.cannotAddInput }
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? SparseVideoFixtureError.cannotStart }
        writer.startSession(atSourceTime: .zero)

        for seconds in [0, endTime - 1] {
            var attempts = 0
            while !input.isReadyForMoreMediaData && attempts < 500 {
                try await Task.sleep(nanoseconds: 10_000_000)
                attempts += 1
            }
            guard input.isReadyForMoreMediaData, let pool = adaptor.pixelBufferPool else {
                throw SparseVideoFixtureError.cannotAppend
            }
            var pixelBuffer: CVPixelBuffer?
            guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer) == kCVReturnSuccess,
                  let pixelBuffer else { throw SparseVideoFixtureError.cannotAppend }
            CVPixelBufferLockBaseAddress(pixelBuffer, [])
            if let bytes = CVPixelBufferGetBaseAddress(pixelBuffer) {
                memset(bytes, seconds == 0 ? 0x30 : 0xA0, CVPixelBufferGetDataSize(pixelBuffer))
            }
            CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
            guard adaptor.append(pixelBuffer, withPresentationTime: CMTime(seconds: seconds, preferredTimescale: 600)) else {
                throw writer.error ?? SparseVideoFixtureError.cannotAppend
            }
        }
        writer.endSession(atSourceTime: CMTime(seconds: endTime, preferredTimescale: 600))
        input.markAsFinished()
        await withCheckedContinuation { continuation in
            writer.finishWriting { continuation.resume() }
        }
        guard writer.status == .completed else { throw writer.error ?? SparseVideoFixtureError.cannotFinish }
    }
}

private enum SparseVideoFixtureError: Error {
    case cannotAddInput
    case cannotStart
    case cannotAppend
    case cannotFinish
}

private actor SuspendedReviewMedia: ReviewMediaImporting {
    let root: URL
    private(set) var importCount = 0
    private(set) var deleteCount = 0
    private var startedWaiter: CheckedContinuation<Void, Never>?
    private var copyWaiter: CheckedContinuation<Void, Never>?

    init(root: URL) { self.root = root }

    func importVideo(at sourceURL: URL) async throws -> LocalMediaReference {
        importCount += 1
        startedWaiter?.resume()
        startedWaiter = nil
        await withCheckedContinuation { copyWaiter = $0 }
        let destination = root.appendingPathComponent("sources/staged.mov")
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("synthetic staged file".utf8).write(to: destination)
        return LocalMediaReference(relativePath: "sources/staged.mov", originalFilename: "synthetic.mov")
    }

    func url(for reference: LocalMediaReference) -> URL { root.appendingPathComponent(reference.relativePath) }

    func delete(_ url: URL) throws {
        deleteCount += 1
        try FileManager.default.removeItem(at: url)
    }

    func waitUntilStarted() async {
        if importCount > 0 { return }
        await withCheckedContinuation { startedWaiter = $0 }
    }

    func completeCopy() {
        copyWaiter?.resume()
        copyWaiter = nil
    }
}
