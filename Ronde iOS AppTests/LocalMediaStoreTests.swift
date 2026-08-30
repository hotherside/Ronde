import Foundation
import XCTest
@testable import Ronde

final class LocalMediaStoreTests: XCTestCase {
    func testImportCopiesSourceIntoAppOwnedStorage() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let source = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mov")
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: source)
        }
        try Data("source-video".utf8).write(to: source)
        let store = try LocalMediaStore(rootURL: root)

        let reference = try await store.importVideo(at: source)
        let copiedURL = try await store.url(for: reference)

        XCTAssertNotEqual(copiedURL, source)
        XCTAssertEqual(try Data(contentsOf: copiedURL), Data("source-video".utf8))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    func testRejectsPathTraversal() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try LocalMediaStore(rootURL: root)
        let unsafe = LocalMediaReference(relativePath: "../secret.mov", originalFilename: "secret.mov")

        do {
            _ = try await store.url(for: unsafe)
            XCTFail("Path traversal must be rejected")
        } catch let error as LocalMediaStoreError {
            XCTAssertEqual(error, .invalidRelativePath)
        }
    }
}
