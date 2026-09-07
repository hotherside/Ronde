import Foundation

/// A small, local-first archive for review metadata and tracer geometry.
///
/// Source videos remain in `LocalMediaStore`. Portable media paths are resolved at load time.
/// A failed read locks writes until an explicit, successful read makes the archive safe again.
final class ReviewSessionArchive {
    enum ArchiveError: LocalizedError, Equatable {
        case storageUnavailable
        case unreadable
        case corrupted
        case writeBlocked

        var errorDescription: String? {
            switch self {
            case .storageUnavailable: "Ronde could not open local review storage."
            case .unreadable: "Your library could not be read. Its files have been kept. Try opening it again."
            case .corrupted: "Your library needs recovery. Its files have been kept and will not be overwritten."
            case .writeBlocked: "Open your existing library successfully before saving changes."
            }
        }
    }

    enum ReadResult {
        case missing
        case loaded([ReviewSession])
        case failed(ArchiveError)
    }

    private let fileURL: URL
    private let rootURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var hasRead = false
    private var permitsWrites = false

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
        self.rootURL = root

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func read() -> ReadResult {
        hasRead = true
        permitsWrites = false
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            let failure = error as NSError
            if failure.domain == NSCocoaErrorDomain,
               [NSFileReadNoSuchFileError, NSFileNoSuchFileError].contains(failure.code) {
                permitsWrites = true
                return .missing
            }
            return .failed(.unreadable)
        }
        do {
            let sessions = try decoder.decode([ReviewSession].self, from: data)
            permitsWrites = true
            return .loaded(sessions.map(resolveMedia).sorted { $0.createdAt > $1.createdAt })
        } catch {
            return .failed(.corrupted)
        }
    }

    /// Compatibility for callers that only need loaded records. Runtime UI uses `read()` so
    /// it can distinguish unavailable storage from a new library; the write gate applies here too.
    func load() -> [ReviewSession] {
        if case .loaded(let sessions) = read() { return sessions }
        return []
    }

    func save(_ sessions: [ReviewSession]) throws {
        // Even a caller that saves before loading cannot overwrite an existing corrupt archive.
        if !hasRead { _ = read() }
        guard permitsWrites else { throw ArchiveError.writeBlocked }
        let data = try encoder.encode(sessions.map(portableMedia))
        try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }

    private func portableMedia(_ session: ReviewSession) -> ReviewSession {
        var value = session
        let path: String?
        if let storedPath = value.sourceRelativePath {
            path = validatedMediaPath(storedPath)
        } else {
            path = value.sourceURL.flatMap(relativeMediaPath)
        }
        if let path {
            value.sourceRelativePath = path
            value.sourceURL = nil
        }
        return value
    }

    private func resolveMedia(_ session: ReviewSession) -> ReviewSession {
        var value = session
        let path: String?
        if let storedPath = value.sourceRelativePath {
            path = validatedMediaPath(storedPath)
        } else {
            path = value.sourceURL.flatMap(relativeMediaPath)
        }
        if let path {
            value.sourceRelativePath = path
            value.sourceURL = rootURL.appendingPathComponent(path)
        } else if value.sourceRelativePath != nil {
            // Never fall back to an arbitrary URL when a stored relative path is invalid.
            value.sourceURL = nil
        }
        return value
    }

    private func relativeMediaPath(_ url: URL) -> String? {
        guard url.isFileURL else { return nil }
        let components = url.standardizedFileURL.pathComponents
        let root = rootURL.standardizedFileURL.pathComponents
        if components.starts(with: root) {
            return validatedMediaPath(components.dropFirst(root.count).joined(separator: "/"))
        }
        // Legacy archives stored the former iOS container URL. Only rebase the exact
        // app-owned media suffix, never external files or an arbitrary path traversal.
        guard let index = components.lastIndex(of: "RondeShotReview") else { return nil }
        return validatedMediaPath(components.dropFirst(index + 1).joined(separator: "/"))
    }

    private func validatedMediaPath(_ path: String) -> String? {
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard components.count == 2,
              ["sources", "clips", "segments"].contains(String(components[0])),
              !components[1].isEmpty,
              components[1] != ".", components[1] != "..",
              !components[1].contains("\\") else { return nil }
        return components.map(String.init).joined(separator: "/")
    }
}
