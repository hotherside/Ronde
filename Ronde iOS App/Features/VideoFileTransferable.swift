import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// File-backed PhotosPicker representation. This avoids loading a 30–50 minute
/// recording into memory before LocalMediaStore copies it into app storage.
struct VideoFileTransferable: Transferable, Sendable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { received in
            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent("ronde-import-\(UUID().uuidString).\(received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension)")
            try FileManager.default.copyItem(at: received.file, to: destination)
            return VideoFileTransferable(url: destination)
        }
    }
}
