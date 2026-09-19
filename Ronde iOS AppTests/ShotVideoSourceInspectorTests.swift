import XCTest
@testable import Ronde

final class ShotVideoSourceInspectorTests: XCTestCase {
    func testBoundedInspectionReturnsOnlyTheRequestedSourceWindow() async throws {
        let source = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "studio-fixture", withExtension: "mp4"))
        let range = ReviewTimeRange(start: 0.4, duration: 0.8)
        let inspector = ShotVideoSourceInspector()

        let times = try await inspector.presentationTimes(url: source, sourceRange: range)
        let thumbnails = await inspector.thumbnails(url: source, duration: 1.5, count: 4, sourceRange: range)

        XCTAssertFalse(times.isEmpty)
        XCTAssertTrue(times.allSatisfy { $0 >= range.start && $0 <= range.end })
        XCTAssertFalse(thumbnails.isEmpty)
        XCTAssertTrue(thumbnails.allSatisfy { $0.time >= range.start && $0.time <= range.end })
    }
}
