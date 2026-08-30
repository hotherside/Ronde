import Foundation

/// A small, local-first archive for review metadata and tracer geometry.
///
/// Source videos remain in `LocalMediaStore`. The archive stores their app-owned URL plus the
/// reviewed geometry so relaunching Ronde does not discard a manual edit or evidence result.
struct ReviewSessionArchive {
    enum ArchiveError: Error {
        case storageUnavailable
    }

    private let fileURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(accountID: UUID? = nil, rootURL: URL? = nil, fileManager: FileManager = .default) throws {
        self.fileManager = fileManager
        let root: URL
        if let rootURL {
            root = rootURL
        } else if let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            root = support.appendingPathComponent("RondeShotReview", isDirectory: true)
        } else {
            throw ArchiveError.storageUnavailable
        }

        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        let filename = accountID.map { "review-sessions-\($0.uuidString.lowercased())-v1.json" }
            ?? "review-sessions-v1.json"
        fileURL = root.appendingPathComponent(filename)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func load() -> [ReviewSession] {
        guard let data = try? Data(contentsOf: fileURL),
              let sessions = try? decoder.decode([ReviewSession].self, from: data) else {
            return []
        }

        return sessions.sorted { $0.createdAt > $1.createdAt }
    }

    func save(_ sessions: [ReviewSession]) throws {
        let data = try encoder.encode(sessions)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }
}
