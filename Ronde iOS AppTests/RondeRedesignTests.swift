import Foundation
import XCTest
@testable import Ronde

final class RondeRedesignTests: XCTestCase {
    func testReviewArchiveRestoresLocalMetadataAndEvidenceGeometry() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ronde-redesign-tests-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }

        var session = ReviewFixtures.quickReviewSession
        session.placeName = "Moore Park Golf"
        session.clubName = "7-iron"
        session.note = "Low wind."
        session.isFavourite = true

        let archive = try ReviewSessionArchive(rootURL: root)
        try archive.save([session])

        let restored = try XCTUnwrap(archive.load().first)
        XCTAssertEqual(restored.id, session.id)
        XCTAssertEqual(restored.placeName, "Moore Park Golf")
        XCTAssertEqual(restored.clubName, "7-iron")
        XCTAssertEqual(restored.note, "Low wind.")
        XCTAssertTrue(restored.isFavourite)
        XCTAssertEqual(
            restored.defaultCandidate?.evidenceAnchoredPath,
            session.defaultCandidate?.evidenceAnchoredPath
        )
    }

    func testReviewArchivesAreScopedToSignedInAccount() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ronde-account-archive-tests-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }

        let firstAccount = UUID()
        let secondAccount = UUID()
        let firstArchive = try ReviewSessionArchive(accountID: firstAccount, rootURL: root)
        let secondArchive = try ReviewSessionArchive(accountID: secondAccount, rootURL: root)

        try firstArchive.save([ReviewFixtures.quickReviewSession])

        XCTAssertEqual(firstArchive.load().count, 1)
        XCTAssertTrue(secondArchive.load().isEmpty)
    }

    func testLibraryMetricsStayEmptyWithoutReviews() {
        let metrics = RondeLibraryMetrics(sessions: [])

        XCTAssertEqual(metrics.reviewCount, 0)
        XCTAssertEqual(metrics.tracedCount, 0)
        XCTAssertEqual(metrics.availability, 0)
        XCTAssertEqual(metrics.weeklyActivity.count, 8)
        XCTAssertTrue(metrics.weeklyActivity.allSatisfy { $0.count == 0 })
    }

    func testLibraryMetricsUseOnlyStoredReviewEvidence() {
        var traced = ReviewFixtures.quickReviewSession
        traced.createdAt = .now
        traced.isFavourite = true

        var untracked = ReviewFixtures.liveSession
        untracked.createdAt = .now
        untracked.isFavourite = false

        let metrics = RondeLibraryMetrics(sessions: [traced, untracked])

        XCTAssertEqual(metrics.reviewCount, 2)
        XCTAssertEqual(metrics.tracedCount, 1)
        XCTAssertEqual(metrics.favouriteCount, 1)
        XCTAssertEqual(metrics.availability, 0.5, accuracy: 0.001)
    }
}
