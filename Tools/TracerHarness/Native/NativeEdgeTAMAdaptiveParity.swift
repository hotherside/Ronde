import CoreGraphics
import CryptoKit
import Foundation
import ImageIO

/// Local-only full-interval adaptive EdgeTAM diagnostic.
///
/// Inputs, source cache, model packages, constants, masks, and JSON output must
/// all remain outside the repository. The command never reads labels.
@main
struct NativeEdgeTAMAdaptiveParity {
    private struct Config: Decodable {
        struct Prompt: Decodable { let time_seconds: Double; let x_px: Double; let y_px: Double }
        let clip_id: String
        let source_path: String
        let avfoundation_frame_manifest: String
        let start_time_seconds: Double
        let end_time_seconds: Double
        let prompts: [Prompt]
        let frame_cache_manifest: String
        let source_time_gap_seconds: Double
    }

    private struct AVManifest: Decodable { let frameTimes: [Double]; let width: Int; let height: Int }

    private struct CacheManifest: Decodable {
        struct Frame: Decodable {
            let cropHeight: Int; let cropWidth: Int; let cropX: Int; let cropY: Int
            let file: String; let frameIndex: Int; let timestamp: Double
        }
        let coordinateOrigin: String
        let frames: [Frame]
        let height: Int
        let width: Int
    }

    private struct ObservedMask: Encodable {
        let sourceFrameIndex: Int
        let sourcePTS: Double
        let kind: String
        let crop: EdgeTAMSourceCrop
        let segmentID: Int
        let direction: String
        let visible: Bool
        let objectScoreLogit: Float
        let componentCount: Int
        let selectedArea: Int
        let positiveArea: Int
        let centroidX: Double?
        let centroidY: Double?
        let rawBinaryMaskPath: String
        let rawBinaryMaskSHA256: String
    }

    private struct Output: Encodable {
        let schemaVersion: Int
        let status: String
        let input: [String: String]
        let source: [String: AnyCodableValue]
        /// The Core ML tracker uses this interval-relative index. Observations
        /// already carry the corresponding absolute source frame index.
        let intervalSourceFrameIndices: [Int]
        let resultIndexSpace: String
        let observedMasks: [ObservedMask]
        let result: EdgeTAMAdaptiveResult?
        let elapsedSeconds: Double?
        let error: String?
    }

    /// `JSONEncoder` has no `Any` support; this keeps evidence scalar-only.
    private enum AnyCodableValue: Encodable {
        case string(String), int(Int), double(Double), bool(Bool)
        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case let .string(value): try container.encode(value)
            case let .int(value): try container.encode(value)
            case let .double(value): try container.encode(value)
            case let .bool(value): try container.encode(value)
            }
        }
    }

    private static func sha(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func sha(_ url: URL) throws -> String { sha(try Data(contentsOf: url)) }

    private static func outsideRepository(_ url: URL) throws -> URL {
        let resolved = url.resolvingSymlinksInPath().standardizedFileURL
        var repository = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { repository.deleteLastPathComponent() }
        let root = repository.resolvingSymlinksInPath().standardizedFileURL.path
        guard resolved.path != root, !resolved.path.hasPrefix(root + "/") else {
            throw EdgeTAMNativeError.invalidState("Private diagnostic input/output must be outside the repository")
        }
        return resolved
    }

    private static func child(_ name: String, in directory: URL) throws -> URL {
        let url = try outsideRepository(directory.appendingPathComponent(name))
        guard url.path.hasPrefix(directory.path + "/") else {
            throw EdgeTAMNativeError.invalidState("Cache child escapes its external directory")
        }
        return url
    }

    private static func write<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(value).write(to: url, options: .atomic)
    }

    private static func rgbPNG(_ url: URL, width: Int, height: Int) throws -> [UInt8] {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              image.width == width, image.height == height else {
            throw EdgeTAMNativeError.invalidState("Cache PNG dimensions do not match the validated source frame")
        }
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = rgba.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(
                data: raw.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.interpolationQuality = .none
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { throw EdgeTAMNativeError.invalidState("Could not decode cache PNG") }
        var rgb = [UInt8](repeating: 0, count: width * height * 3)
        for pixel in 0..<(width * height) {
            rgb[pixel * 3] = rgba[pixel * 4]
            rgb[pixel * 3 + 1] = rgba[pixel * 4 + 1]
            rgb[pixel * 3 + 2] = rgba[pixel * 4 + 2]
        }
        return rgb
    }

    private static func usage() -> Never {
        fatalError("Usage: native-edgetam-adaptive-parity --config external-config.json --models external-model-map.json --constants external-constants.json --output new-external-directory")
    }

    static func main() throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard arguments.count == 8,
              arguments[0] == "--config", arguments[2] == "--models",
              arguments[4] == "--constants", arguments[6] == "--output" else { usage() }
        let configURL = try outsideRepository(URL(fileURLWithPath: arguments[1]))
        let modelsURL = try outsideRepository(URL(fileURLWithPath: arguments[3]))
        let constantsURL = try outsideRepository(URL(fileURLWithPath: arguments[5]))
        let output = try outsideRepository(URL(fileURLWithPath: arguments[7]))
        guard !FileManager.default.fileExists(atPath: output.path) else {
            throw EdgeTAMNativeError.invalidState("Refusing to overwrite prior adaptive evidence")
        }

        let configData = try Data(contentsOf: configURL)
        let config = try JSONDecoder().decode(Config.self, from: configData)
        guard config.start_time_seconds.isFinite, config.end_time_seconds.isFinite,
              config.end_time_seconds > config.start_time_seconds,
              config.source_time_gap_seconds == 0.20,
              config.prompts.count == 1 else {
            throw EdgeTAMNativeError.invalidState("Expected one finite prompt and frozen 0.20s source gap")
        }
        let prompt = config.prompts[0]
        let avURL = try outsideRepository(URL(fileURLWithPath: config.avfoundation_frame_manifest))
        let cacheURL = try outsideRepository(URL(fileURLWithPath: config.frame_cache_manifest))
        let sourceURL = try outsideRepository(URL(fileURLWithPath: config.source_path))
        let avData = try Data(contentsOf: avURL)
        let cacheData = try Data(contentsOf: cacheURL)
        let av = try JSONDecoder().decode(AVManifest.self, from: avData)
        let cache = try JSONDecoder().decode(CacheManifest.self, from: cacheData)
        let constantsData = try Data(contentsOf: constantsURL)
        let constants = try JSONDecoder().decode(EdgeTAMLearnedConstants.self, from: constantsData)
        try constants.validate()
        guard av.width == cache.width, av.height == cache.height,
              cache.coordinateOrigin == "top-left", av.width > 0, av.height > 0,
              prompt.x_px >= 0, prompt.x_px < Double(av.width), prompt.y_px >= 0, prompt.y_px < Double(av.height) else {
            throw EdgeTAMNativeError.invalidState("Prompt, source dimensions, or top-left cache contract is invalid")
        }
        guard av.frameTimes.enumerated().allSatisfy({ index, time in
            time.isFinite && time >= 0 && (index == 0 || time > av.frameTimes[index - 1])
        }) else { throw EdgeTAMNativeError.invalidState("AVFoundation PTS must be strictly increasing") }
        guard let seedIndex = av.frameTimes.firstIndex(where: { abs($0 - prompt.time_seconds) < 0.000_000_001 }) else {
            throw EdgeTAMNativeError.invalidState("Prompt PTS is absent from the canonical AVFoundation manifest")
        }
        let expected = Set(av.frameTimes.indices.filter { index in
            av.frameTimes[index] >= config.start_time_seconds && av.frameTimes[index] <= config.end_time_seconds
        })
        guard expected.contains(seedIndex), !expected.isEmpty else {
            throw EdgeTAMNativeError.invalidState("Configured interval does not contain the prompt PTS")
        }
        var cacheFiles: [Int: URL] = [:]
        for frame in cache.frames {
            guard (0..<av.frameTimes.count).contains(frame.frameIndex),
                  frame.cropX == 0, frame.cropY == 0,
                  frame.cropWidth == av.width, frame.cropHeight == av.height,
                  abs(frame.timestamp - av.frameTimes[frame.frameIndex]) < 0.000_000_001,
                  cacheFiles[frame.frameIndex] == nil else {
                throw EdgeTAMNativeError.invalidState("Cache must contain unique full-source frames at canonical AVFoundation PTS")
            }
            cacheFiles[frame.frameIndex] = try child(frame.file, in: cacheURL.deletingLastPathComponent())
        }
        guard expected.isSubset(of: Set(cacheFiles.keys)) else {
            throw EdgeTAMNativeError.invalidState("Cache does not cover the requested source PTS interval")
        }
        let intervalSourceFrameIndices = expected.sorted()
        let intervalFrameTimes = intervalSourceFrameIndices.map { av.frameTimes[$0] }
        guard let intervalSeedIndex = intervalSourceFrameIndices.firstIndex(of: seedIndex) else {
            throw EdgeTAMNativeError.invalidState("Prompt PTS is absent from the configured source interval")
        }

        let mapData = try Data(contentsOf: modelsURL)
        let modelMap = try JSONDecoder().decode([String: String].self, from: mapData)
        let packageURLs = try modelMap.mapValues { try outsideRepository(URL(fileURLWithPath: $0)) }
        let components = try EdgeTAMCoreMLComponents(packageURLs: packageURLs, allowPackageCompilationOnMac: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let masks = output.appendingPathComponent("observed-masks", isDirectory: true)
        try FileManager.default.createDirectory(at: masks, withIntermediateDirectories: true)
        let input = ["configSHA256": sha(configData), "cacheManifestSHA256": sha(cacheData),
                     "avPTSManifestSHA256": sha(avData), "constantsSHA256": sha(constantsData),
                     "modelsMapSHA256": sha(mapData), "sourceSHA256": try sha(sourceURL)]
        var observations: [ObservedMask] = []
        let start = Date()
        do {
            let tracker = EdgeTAMAdaptiveTracker(components: components, constants: constants)
            let result = try tracker.track(
                frameTimes: intervalFrameTimes, sourceWidth: av.width, sourceHeight: av.height,
                seedIndex: intervalSeedIndex, point: (x: prompt.x_px, y: prompt.y_px),
                maximumSourceTimeGapSeconds: config.source_time_gap_seconds,
                frameProvider: { index, crop in
                    guard (0..<intervalSourceFrameIndices.count).contains(index),
                          let url = cacheFiles[intervalSourceFrameIndices[index]] else {
                        throw EdgeTAMNativeError.invalidState("Tracker requested source index outside validated cache interval")
                    }
                    let rgb = try rgbPNG(url, width: av.width, height: av.height)
                    return try EdgeTAMImagePreprocessor().tensor(rgbBytes: rgb, width: av.width, height: av.height, crop: crop)
                },
                observer: { observation in
                    let sourceFrameIndex = intervalSourceFrameIndices[observation.index]
                    let suffix = String(format: "f%05d-%03d-%@", sourceFrameIndex, observations.count, observation.kind)
                    let maskURL = masks.appendingPathComponent("mask-\(suffix).u8")
                    let bytes = Data(observation.mask.binaryMask)
                    try bytes.write(to: maskURL, options: .atomic)
                    observations.append(ObservedMask(
                        sourceFrameIndex: sourceFrameIndex, sourcePTS: observation.timestamp,
                        kind: observation.kind, crop: observation.crop, segmentID: observation.segmentID,
                        direction: observation.direction, visible: observation.mask.selectedArea > 0,
                        objectScoreLogit: observation.objectScoreLogit,
                        componentCount: observation.mask.componentCount,
                        selectedArea: observation.mask.selectedArea, positiveArea: observation.mask.positiveArea,
                        centroidX: observation.mask.centroidX, centroidY: observation.mask.centroidY,
                        rawBinaryMaskPath: maskURL.path, rawBinaryMaskSHA256: sha(bytes)
                    ))
                }
            )
            try write(Output(schemaVersion: 1, status: "completed", input: input,
                             source: ["width": .int(av.width), "height": .int(av.height),
                                      "seedSourceFrameIndex": .int(seedIndex), "seedPTS": .double(prompt.time_seconds),
                                      "maximumSourceTimeGapSeconds": .double(config.source_time_gap_seconds),
                                      "referenceLabelsRead": .bool(false)],
                             intervalSourceFrameIndices: intervalSourceFrameIndices,
                             resultIndexSpace: "interval-relative; map through intervalSourceFrameIndices",
                             observedMasks: observations, result: result,
                             elapsedSeconds: Date().timeIntervalSince(start), error: nil),
                      to: output.appendingPathComponent("adaptive-evidence.json"))
        } catch {
            try write(Output(schemaVersion: 1, status: "error", input: input,
                             source: ["referenceLabelsRead": .bool(false)],
                             intervalSourceFrameIndices: intervalSourceFrameIndices,
                             resultIndexSpace: "interval-relative; map through intervalSourceFrameIndices",
                             observedMasks: observations, result: nil, elapsedSeconds: Date().timeIntervalSince(start), error: String(describing: error)),
                      to: output.appendingPathComponent("adaptive-evidence.json"))
            throw error
        }
    }
}
