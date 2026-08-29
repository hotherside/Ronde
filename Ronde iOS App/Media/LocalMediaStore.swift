import Foundation
import UniformTypeIdentifiers

enum LocalMediaStoreError: LocalizedError, Sendable, Equatable {
    case invalidRelativePath
    case sourceDoesNotExist
    case storageUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidRelativePath: "The media path is invalid."
        case .sourceDoesNotExist: "The selected video is no longer available."
        case .storageUnavailable: "Ronde could not prepare its local media storage."
        }
    }
}

/// App-owned media storage. Imports are copied before analysis so original media remains untouched.
actor LocalMediaStore {
    enum Directory: String, Sendable {
        case sources
        case clips
        case segments
    }

    private let rootURL: URL
    private let fileManager: FileManager

    init(rootURL: URL? = nil, fileManager: FileManager = .default) throws {
        self.fileManager = fileManager
        if let rootURL {
            self.rootURL = rootURL
        } else if let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            self.rootURL = support.appendingPathComponent("RondeShotReview", isDirectory: true)
        } else {
            throw LocalMediaStoreError.storageUnavailable
        }
        try Self.prepareDirectories(rootURL: self.rootURL, fileManager: fileManager)
    }

    func importVideo(at sourceURL: URL) throws -> LocalMediaReference {
        let accessed = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessed { sourceURL.stopAccessingSecurityScopedResource() }
        }

        guard fileManager.fileExists(atPath: sourceURL.path) else {
            throw LocalMediaStoreError.sourceDoesNotExist
        }

        let extensionName = sourceURL.pathExtension.isEmpty ? "mov" : sourceURL.pathExtension
        let filename = "\(UUID().uuidString).\(extensionName)"
        let destination = directoryURL(for: .sources).appendingPathComponent(filename)
        try fileManager.copyItem(at: sourceURL, to: destination)
        return LocalMediaReference(
            relativePath: relativePath(for: destination),
            originalFilename: sourceURL.lastPathComponent
        )
    }

    func url(for reference: LocalMediaReference) throws -> URL {
        try validatedURL(relativePath: reference.relativePath)
    }

    func makeClipURL(fileExtension: String = "mov") throws -> URL {
        let url = directoryURL(for: .clips).appendingPathComponent("\(UUID().uuidString).\(fileExtension)")
        return url
    }

    func makeClipDestination(fileExtension: String = "mov") throws -> LocalMediaDestination {
        let url = try makeClipURL(fileExtension: fileExtension)
        return LocalMediaDestination(
            reference: LocalMediaReference(
                relativePath: relativePath(for: url),
                originalFilename: "Ronde Review.\(fileExtension)"
            ),
            url: url
        )
    }

    func makeSegmentURL(fileExtension: String = "mov") throws -> URL {
        directoryURL(for: .segments).appendingPathComponent("\(UUID().uuidString).\(fileExtension)")
    }

    func delete(_ url: URL) throws {
        guard url.path.hasPrefix(rootURL.path) else { throw LocalMediaStoreError.invalidRelativePath }
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }

    func removeUnreferencedSegments(keeping protectedURLs: Set<URL>) throws {
        let directory = directoryURL(for: .segments)
        for url in try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) where !protectedURLs.contains(url) {
            try fileManager.removeItem(at: url)
        }
    }

    private static func prepareDirectories(rootURL: URL, fileManager: FileManager) throws {
        do {
            try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
            for directory in [Directory.sources, .clips, .segments] {
                try fileManager.createDirectory(
                    at: rootURL.appendingPathComponent(directory.rawValue, isDirectory: true),
                    withIntermediateDirectories: true
                )
            }
        } catch {
            throw LocalMediaStoreError.storageUnavailable
        }
    }

    private func directoryURL(for directory: Directory) -> URL {
        rootURL.appendingPathComponent(directory.rawValue, isDirectory: true)
    }

    private func relativePath(for url: URL) -> String {
        String(url.path.dropFirst(rootURL.path.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private func validatedURL(relativePath: String) throws -> URL {
        guard !relativePath.isEmpty, !relativePath.contains("..") else { throw LocalMediaStoreError.invalidRelativePath }
        let url = rootURL.appendingPathComponent(relativePath)
        guard url.path.hasPrefix(rootURL.path) else { throw LocalMediaStoreError.invalidRelativePath }
        return url
    }
}

struct LocalMediaDestination: Sendable, Equatable {
    let reference: LocalMediaReference
    let url: URL
}
