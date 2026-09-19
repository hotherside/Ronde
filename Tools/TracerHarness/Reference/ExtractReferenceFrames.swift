import AVFoundation
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Reviewer-supplied anchors place inspection crops only. They are never exported
// as ball observations. Keep the configuration, crops and manifest outside Git.
struct CropAnchor: Decodable {
    let timestamp: Double
    let x: Double
    let y: Double
}

struct InspectionConfiguration: Decodable {
    let start: Double
    let end: Double
    let cropSize: Int
    let anchors: [CropAnchor]
    let overviewTimes: [Double]
}

struct InspectionFrame: Encodable {
    let frameIndex: Int
    let timestamp: Double
    let cropX: Int
    let cropY: Int
    let cropWidth: Int
    let cropHeight: Int
    let file: String
}

struct InspectionManifest: Encodable {
    let width: Int
    let height: Int
    let coordinateOrigin = "top-left"
    let annotationStatus = "inspection-crops-only"
    let frames: [InspectionFrame]
}

@main
struct ExtractReferenceFrames {
    static func main() async throws {
        let args = CommandLine.arguments
        guard args.count == 4 else {
            throw failure("Usage: extract-reference VIDEO CONFIG_JSON OUTPUT_DIRECTORY")
        }
        let source = URL(fileURLWithPath: args[1])
        let config = try JSONDecoder().decode(InspectionConfiguration.self, from: Data(contentsOf: URL(fileURLWithPath: args[2])))
        guard config.cropSize > 0, config.start >= 0, config.end > config.start,
              !config.anchors.isEmpty,
              config.anchors.allSatisfy({ $0.timestamp.isFinite && $0.x.isFinite && $0.y.isFinite }),
              zip(config.anchors, config.anchors.dropFirst()).allSatisfy({ $0.timestamp < $1.timestamp }) else {
            throw failure("Invalid crop inspection configuration")
        }
        let destination = URL(fileURLWithPath: args[3], isDirectory: true)
        // Compile with an absolute source path so this guard is independent of
        // the caller's working directory. Fail closed if that source is absent.
        let sourceFile = URL(fileURLWithPath: #filePath).resolvingSymlinksInPath()
        guard FileManager.default.fileExists(atPath: sourceFile.path) else {
            throw failure("Compile this extractor with an absolute source-file path")
        }
        let repo = sourceFile.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().resolvingSymlinksInPath()
        guard FileManager.default.fileExists(atPath: repo.appendingPathComponent(".git").path) else {
            throw failure("Cannot establish the source working-tree boundary")
        }
        for privateURL in [source, URL(fileURLWithPath: args[2]), destination] {
            let path = privateURL.resolvingSymlinksInPath().standardizedFileURL.path
            guard path != repo.path, !path.hasPrefix(repo.path + "/") else {
                throw failure("Private source, crop configuration and inspection output must be outside the source working tree")
            }
        }
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let asset = AVURLAsset(url: source)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw failure("No video track") }
        let transform = try await track.load(.preferredTransform)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw failure("Cannot add video reader") }
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? failure("Cannot start video reader") }
        let context = CIContext(options: [.cacheIntermediates: false])
        var frames: [InspectionFrame] = []
        var frameIndex = 0
        var dimensions = (width: 0, height: 0)
        var overviewPending = Set(config.overviewTimes.indices)
        while let sample = output.copyNextSampleBuffer() {
            let index = frameIndex
            frameIndex += 1
            let timestamp = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sample))
            guard timestamp.isFinite, let buffer = CMSampleBufferGetImageBuffer(sample) else { continue }
            try autoreleasepool {
                let transformed = CIImage(cvPixelBuffer: buffer).transformed(by: transform)
                let image = transformed.transformed(by: CGAffineTransform(translationX: -transformed.extent.minX, y: -transformed.extent.minY))
                let width = Int(image.extent.width.rounded())
                let height = Int(image.extent.height.rounded())
                dimensions = (width, height)
                for overviewIndex in overviewPending.sorted() where timestamp >= config.overviewTimes[overviewIndex] {
                    let scale = min(1, 960.0 / Double(max(width, height)))
                    let overview = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                    try save(overview, context: context, to: destination.appendingPathComponent(String(format: "overview-%03d-%.6f.png", index, timestamp)))
                    overviewPending.remove(overviewIndex)
                }
                guard timestamp >= config.start, timestamp <= config.end else { return }
                let anchor = interpolatedCropCentre(at: timestamp, anchors: config.anchors)
                let cropWidth = min(width, config.cropSize)
                let cropHeight = min(height, config.cropSize)
                let x = min(max(0, Int(anchor.x.rounded()) - cropWidth / 2), width - cropWidth)
                let y = min(max(0, Int(anchor.y.rounded()) - cropHeight / 2), height - cropHeight)
                let rect = CGRect(x: x, y: height - y - cropHeight, width: cropWidth, height: cropHeight)
                let crop = image.cropped(to: rect)
                let filename = String(format: "frame-%03d-%.6f.png", index, timestamp)
                try save(crop, context: context, to: destination.appendingPathComponent(filename))
                frames.append(InspectionFrame(frameIndex: index, timestamp: timestamp, cropX: x, cropY: y, cropWidth: cropWidth, cropHeight: cropHeight, file: filename))
            }
        }
        guard reader.status != .failed else { throw reader.error ?? failure("Video read failed") }
        let manifest = InspectionManifest(width: dimensions.width, height: dimensions.height, frames: frames)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: destination.appendingPathComponent("manifest.json"), options: .atomic)
        print("Extracted \(frames.count) inspection crops; no reference labels inferred.")
    }

    static func interpolatedCropCentre(at time: Double, anchors: [CropAnchor]) -> (x: Double, y: Double) {
        guard let first = anchors.first, let last = anchors.last else { return (0, 0) }
        if time <= first.timestamp { return (first.x, first.y) }
        if time >= last.timestamp { return (last.x, last.y) }
        for (a, b) in zip(anchors, anchors.dropFirst()) where time >= a.timestamp && time <= b.timestamp {
            let fraction = (time - a.timestamp) / (b.timestamp - a.timestamp)
            return (a.x + fraction * (b.x - a.x), a.y + fraction * (b.y - a.y))
        }
        return (last.x, last.y)
    }

    static func save(_ image: CIImage, context: CIContext, to url: URL) throws {
        guard let cgImage = context.createCGImage(image, from: image.extent),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw failure("Cannot create inspection image")
        }
        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else { throw failure("Cannot write inspection image") }
    }

    static func failure(_ message: String) -> NSError {
        NSError(domain: "ExtractReferenceFrames", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
