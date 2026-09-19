import CryptoKit
import Foundation

/// Standalone, local-only fixed-crop diagnostic. No labels are inputs. Its
/// source RGB fixture and all outputs must live outside the repository.
@main
struct NativeEdgeTAMParity {
    private struct Manifest: Decodable {
        struct Frame: Decodable {
            let sourceFrameIndex: Int
            let timestamp: Double
            let rgb: String
            let rgbSHA256: String
        }
        let schemaVersion: Int
        let sourceHash: String
        let sourceWidth: Int
        let sourceHeight: Int
        let crop: [Int]
        let seedIndex: Int
        let pointModel: [Float]
        let constants: String
        let frames: [Frame]
    }

    private struct Sample: Encodable {
        let sourceFrameIndex: Int
        let timestamp: Double
        let direction: String
        let visible: Bool
        let x: Double?
        let y: Double?
        let componentCount: Int
        let selectedArea: Int
        let positiveArea: Int
        let objectScoreLogit: Float
        let rawBinaryMaskPath: String
        let rawBinaryMaskSHA256: String
        let spatialMemoryFrames: [Int]
        let pointerFrames: [Int]
    }

    private static func sha(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

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

    private static func child(_ path: String, in directory: URL) throws -> URL {
        let result = try outsideRepository(directory.appendingPathComponent(path))
        guard result.path.hasPrefix(directory.path + "/") else {
            throw EdgeTAMNativeError.invalidState("Fixture file escapes its directory")
        }
        return result
    }

    private static func floats(_ url: URL, count: Int) throws -> [Float] {
        let data = try Data(contentsOf: url)
        guard data.count == count * MemoryLayout<Float>.size else {
            throw EdgeTAMNativeError.invalidTensor("Golden float data has the wrong size")
        }
        return data.withUnsafeBytes { bytes in
            (0..<count).map { bytes.loadUnaligned(fromByteOffset: $0 * 4, as: Float.self) }
        }
    }

    private static func maxError(_ left: [Float], _ right: [Float]) throws -> Float {
        guard left.count == right.count, right.allSatisfy(\.isFinite) else {
            throw EdgeTAMNativeError.invalidTensor("Golden values are invalid")
        }
        return zip(left, right).reduce(0) { max($0, abs($1.0 - $1.1)) }
    }

    private static func save(_ value: [String: Any], to url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
    }

    static func main() throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard arguments.count == 6, arguments[0] == "--fixture",
              arguments[2] == "--models", arguments[4] == "--output" else {
            throw EdgeTAMNativeError.invalidState("Usage: native-edgetam-parity --fixture manifest.json --models model-urls.json --output private-new-directory")
        }
        let manifestURL = try outsideRepository(URL(fileURLWithPath: arguments[1]))
        let modelURLs = try outsideRepository(URL(fileURLWithPath: arguments[3]))
        let output = try outsideRepository(URL(fileURLWithPath: arguments[5]))
        guard !FileManager.default.fileExists(atPath: output.path) else {
            throw EdgeTAMNativeError.invalidState("Refusing to overwrite previous native evidence")
        }
        let fixture = manifestURL.deletingLastPathComponent()
        let manifestData = try Data(contentsOf: manifestURL)
        let manifest = try JSONDecoder().decode(Manifest.self, from: manifestData)
        guard manifest.schemaVersion == 1, manifest.crop.count == 4,
              manifest.crop.allSatisfy({ $0 >= 0 }), manifest.crop[2] > 0, manifest.crop[3] > 0,
              manifest.crop[0] <= manifest.sourceWidth - manifest.crop[2],
              manifest.crop[1] <= manifest.sourceHeight - manifest.crop[3],
              (0..<manifest.frames.count).contains(manifest.seedIndex),
              manifest.pointModel.count == 2 else {
            throw EdgeTAMNativeError.invalidState("Invalid source fixture geometry or seed")
        }
        for (index, frame) in manifest.frames.enumerated() {
            guard frame.timestamp.isFinite, frame.timestamp >= 0,
                  index == 0 || (frame.sourceFrameIndex == manifest.frames[index - 1].sourceFrameIndex + 1
                      && frame.timestamp > manifest.frames[index - 1].timestamp) else {
                throw EdgeTAMNativeError.invalidState("Fixture frames must have consecutive indices and increasing source PTS")
            }
        }
        let constantsURL = try child(manifest.constants, in: fixture)
        let constantsData = try Data(contentsOf: constantsURL)
        let constants = try JSONDecoder().decode(EdgeTAMLearnedConstants.self, from: constantsData)
        try constants.validate()
        let crop = EdgeTAMSourceCrop(x: 0, y: 0, width: manifest.crop[2], height: manifest.crop[3])
        let preprocessor = EdgeTAMImagePreprocessor()
        func prepared(_ index: Int) throws -> EdgeTAMTensor {
            let frame = manifest.frames[index]
            let bytes = try Data(contentsOf: child(frame.rgb, in: fixture))
            guard sha(bytes) == frame.rgbSHA256 else {
                throw EdgeTAMNativeError.invalidState("Source RGB fixture hash changed")
            }
            return try preprocessor.tensor(rgbBytes: Array(bytes), width: crop.width, height: crop.height, crop: crop)
        }
        let start = Date()
        let seedImage = try prepared(manifest.seedIndex)
        let imageError = try maxError(seedImage.values, floats(child("expected-seed-image.f32", in: fixture), count: seedImage.values.count))
        let position = try EdgeTAMSegmentTracker.imagePositionEncoding()
        let positionError = try maxError(position.values, floats(child("expected-position.f32", in: fixture), count: position.values.count))
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        var evidence: [String: Any] = [
            "status": "preflight", "fixtureManifestSHA256": sha(manifestData),
            "constantsSHA256": sha(constantsData), "sourceHash": manifest.sourceHash,
            "nativePreprocessingMaximumError": imageError, "nativePositionMaximumError": positionError,
            "requestedFrameCount": manifest.frames.count, "computeUnits": "all",
            "mode": "one-point-assisted", "referenceLabelsRead": false
        ]
        try save(evidence, to: output.appendingPathComponent("evidence.json"))
        guard imageError == 0, positionError <= 0.000001 else {
            throw EdgeTAMNativeError.invalidState("Native input/position parity failed before model prediction")
        }
        let paths = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: modelURLs))
        let packages = try paths.mapValues { try outsideRepository(URL(fileURLWithPath: $0)) }
        let backend = try EdgeTAMCoreMLComponents(packageURLs: packages, allowPackageCompilationOnMac: true)
        evidence["compiledModelURLs"] = backend.compiledModelURLs.mapValues(\.path)
        evidence["status"] = "running"
        try save(evidence, to: output.appendingPathComponent("evidence.json"))
        var samples: [Int: Sample] = [:]
        for reverse in [false, true] {
            let tracker = try EdgeTAMSegmentTracker(components: backend, constants: constants,
                                                   frameCount: manifest.frames.count, reverse: reverse)
            let indices = reverse ? Array(stride(from: manifest.seedIndex, through: 0, by: -1))
                : Array(manifest.seedIndex..<manifest.frames.count)
            for index in indices {
                try autoreleasepool {
                    let frame = manifest.frames[index]
                    let isSeed = index == manifest.seedIndex
                    let image = isSeed ? seedImage : try prepared(index)
                    let point: (x: Float, y: Float)? = isSeed ? (manifest.pointModel[0], manifest.pointModel[1]) : nil
                    let result = try tracker.process(imageNormalised: image, frameIndex: index,
                                                     sourceTime: frame.timestamp, point: point)
                    if reverse && isSeed { return }
                    let observation = try EdgeTAMMaskObservation.extract(lowMask: result.masks.lowMask, width: crop.width, height: crop.height)
                    let maskURL = output.appendingPathComponent(String(format: "mask-%05d.u8", frame.sourceFrameIndex))
                    let mask = Data(observation.binaryMask)
                    try mask.write(to: maskURL, options: .atomic)
                    samples[index] = Sample(
                        sourceFrameIndex: frame.sourceFrameIndex, timestamp: frame.timestamp,
                        direction: reverse ? "reverse" : "forward", visible: observation.selectedArea > 0,
                        x: observation.centroidX.map { ($0 + Double(manifest.crop[0])) / Double(manifest.sourceWidth) },
                        y: observation.centroidY.map { ($0 + Double(manifest.crop[1])) / Double(manifest.sourceHeight) },
                        componentCount: observation.componentCount, selectedArea: observation.selectedArea,
                        positiveArea: observation.positiveArea, objectScoreLogit: result.masks.objectScore.values[0],
                        rawBinaryMaskPath: maskURL.path, rawBinaryMaskSHA256: sha(mask),
                        spatialMemoryFrames: result.spatialMemoryFrames.map { manifest.frames[$0].sourceFrameIndex },
                        pointerFrames: result.pointerFrames.map { manifest.frames[$0].sourceFrameIndex })
                }
                if samples.count.isMultiple(of: 8) { print("Native frames retained: \(samples.count)") }
            }
        }
        guard samples.count == manifest.frames.count else { throw EdgeTAMNativeError.invalidState("Native source-frame output is incomplete") }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let encoded = try encoder.encode(samples.sorted { $0.key < $1.key }.map(\.value))
        try encoded.write(to: output.appendingPathComponent("samples.json"), options: .atomic)
        evidence["status"] = "completed"
        evidence["emittedFrameCount"] = samples.count
        evidence["nonemptyFrameCount"] = samples.values.filter(\.visible).count
        evidence["samplesSHA256"] = sha(encoded)
        evidence["elapsedSeconds"] = Date().timeIntervalSince(start)
        try save(evidence, to: output.appendingPathComponent("evidence.json"))
        print("Native fixed-crop diagnostic completed: \(samples.count) frames")
    }
}
