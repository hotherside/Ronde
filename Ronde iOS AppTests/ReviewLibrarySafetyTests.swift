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
