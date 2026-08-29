@preconcurrency import AVFoundation
import CoreGraphics
import CoreML
import Foundation

struct WASBGolfBallTrackingConfiguration: Sendable, Equatable {
    var maximumPostImpactDuration: TimeInterval
    var minimumPeakConfidence: Double
    var maximumCandidatesPerFrame: Int
    /// Optional normalised source-frame tile origins used by a signed local diagnostic probe.
    /// Production analysis leaves this nil and scans the source-resolution search area.
    var diagnosticTileOrigins: [NormalizedPoint]?

    static let uploadedVideo = WASBGolfBallTrackingConfiguration(
        maximumPostImpactDuration: 1.15,
        minimumPeakConfidence: 0.08,
        maximumCandidatesPerFrame: 30,
        diagnosticTileOrigins: nil
    )
}

enum WASBGolfBallTrackingError: LocalizedError, Sendable, Equatable {
    case unreadableAsset
    case noVideoTrack
    case unsupportedFrameSize
    case modelUnavailable
    case modelFailed(String)
    case noDefensibleBallTrack

    var errorDescription: String? {
        switch self {
        case .unreadableAsset:
            "The selected video cannot be read on this device."
        case .noVideoTrack:
            "The selected video has no readable video track."
        case .unsupportedFrameSize:
            "The source frames are too small for source-resolution ball tracking."
        case .modelUnavailable:
            "The on-device ball tracker is missing from this build."
        case let .modelFailed(message):
            "The on-device ball tracker failed: \(message)"
        case .noDefensibleBallTrack:
            "The ball was not tracked reliably enough to draw a tracer."
        }
    }
}

/// Offline golf-ball tracking built on the MIT-licensed WASB-SBDT sports-ball model.
///
/// Three consecutive, oriented source frames are evaluated in overlapping 512 x 288 tiles. Model
/// peaks are only observations; `GolfBallTrackSelector` must link at least seven of them into a
/// directionally stable post-impact track before this service returns displayable geometry.
actor WASBGolfBallTrackingService {
    private static let modelWidth = 512
    private static let modelHeight = 288
    private static let horizontalStep = 448
    private static let verticalStep = 224

    private var loadedModel: MLModel?

    func analyse(
        url: URL,
        impactTime: TimeInterval,
        configuration: WASBGolfBallTrackingConfiguration = .uploadedVideo,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> BallFlightEstimate {
        let asset = AVURLAsset(url: url)
        guard try await asset.load(.isReadable) else {
            throw WASBGolfBallTrackingError.unreadableAsset
        }
        let duration = max(0, CMTimeGetSeconds(try await asset.load(.duration)))
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw WASBGolfBallTrackingError.noVideoTrack
        }

        let model = try loadModel()
        let nominalFrameRate = min(120, max(24, Double(try await track.load(.nominalFrameRate))))
        let frameDuration = 1 / nominalFrameRate
        let startTime = min(duration, max(0, impactTime + 0.04 - (2 * frameDuration)))
        let endTime = min(duration, impactTime + configuration.maximumPostImpactDuration)
        guard endTime - startTime >= frameDuration * 8 else {
            throw WASBGolfBallTrackingError.noDefensibleBallTrack
        }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero

        var frameWindow: [RGBFrame] = []
        var detections: [GolfBallDetectionCandidate] = []
        var requestedTime = startTime
        var frameIndex = 0

        while requestedTime <= endTime + (frameDuration * 0.25) {
            try Task.checkCancellation()
            let request = CMTime(seconds: requestedTime, preferredTimescale: 60_000)
            do {
                let result = try await generator.image(at: request)
                let frame = try RGBFrame(image: result.image)
                frameWindow.append(frame)
                if frameWindow.count > 3 { frameWindow.removeFirst() }

                if frameWindow.count == 3 {
                    let actualTime = max(0, CMTimeGetSeconds(result.actualTime))
                    let frameDetections = try detectCandidates(
                        in: frameWindow,
                        frameIndex: frameIndex,
                        presentationTime: actualTime,
                        model: model,
                        configuration: configuration
                    )
                    detections.append(contentsOf: frameDetections)
                }
            } catch let error as WASBGolfBallTrackingError {
                throw error
            } catch {
                throw WASBGolfBallTrackingError.modelFailed(error.localizedDescription)
            }

            frameIndex += 1
            requestedTime += frameDuration
            progress?(min(1, max(0, (requestedTime - startTime) / max(0.001, endTime - startTime))))
        }
        progress?(1)

        guard let track = GolfBallTrackSelector.select(
            from: detections,
            impactTime: impactTime
        ) else {
            throw WASBGolfBallTrackingError.noDefensibleBallTrack
        }
        return Self.estimate(from: track)
    }

    private func loadModel() throws -> MLModel {
        if let loadedModel { return loadedModel }
        guard let url = Bundle.main.url(forResource: "GolfBallTracker", withExtension: "mlmodelc") else {
            throw WASBGolfBallTrackingError.modelUnavailable
        }
        do {
            let configuration = MLModelConfiguration()
            configuration.computeUnits = .all
            let model = try MLModel(contentsOf: url, configuration: configuration)
            loadedModel = model
            return model
        } catch {
            throw WASBGolfBallTrackingError.modelFailed(error.localizedDescription)
        }
    }

    private func detectCandidates(
        in frames: [RGBFrame],
        frameIndex: Int,
        presentationTime: TimeInterval,
        model: MLModel,
        configuration: WASBGolfBallTrackingConfiguration
    ) throws -> [GolfBallDetectionCandidate] {
        guard frames.count == 3,
              let current = frames.last,
              frames.allSatisfy({ $0.width == current.width && $0.height == current.height }),
              current.width >= Self.modelWidth,
              current.height >= Self.modelHeight else {
            throw WASBGolfBallTrackingError.unsupportedFrameSize
        }

        let maximumY = max(Self.modelHeight, Int(Double(current.height) * 0.67))
        let tileOrigins: [(x: Int, y: Int)]
        if let diagnosticOrigins = configuration.diagnosticTileOrigins {
            tileOrigins = diagnosticOrigins.map {
                (
                    x: min(current.width - Self.modelWidth, Int($0.x * Double(current.width))),
                    y: min(current.height - Self.modelHeight, Int($0.y * Double(current.height)))
                )
            }
        } else {
            let xOrigins = Self.tileOrigins(
                length: current.width,
                tileLength: Self.modelWidth,
                step: Self.horizontalStep
            )
            let yOrigins = Self.tileOrigins(
                length: min(current.height, maximumY),
                tileLength: Self.modelHeight,
                step: Self.verticalStep
            )
            tileOrigins = yOrigins.flatMap { y in xOrigins.map { x in (x: x, y: y) } }
        }
        var peaks: [PixelPeak] = []
        peaks.reserveCapacity(tileOrigins.count)

        for origin in tileOrigins {
            try Task.checkCancellation()
            let input = try Self.makeInput(
                frames: frames,
                xOrigin: origin.x,
                yOrigin: origin.y
            )
            let features = try MLDictionaryFeatureProvider(dictionary: [
                "input_frames": MLFeatureValue(multiArray: input)
            ])
            let prediction = try model.prediction(from: features)
            guard let heatmap = prediction.featureValue(for: "heatmap")?.multiArrayValue,
                  let peak = Self.peak(in: heatmap),
                  peak.confidence >= configuration.minimumPeakConfidence else {
                continue
            }
            peaks.append(PixelPeak(
                x: origin.x + peak.x,
                y: origin.y + peak.y,
                confidence: peak.confidence
            ))
        }

        var retained: [PixelPeak] = []
        for peak in peaks.sorted(by: { $0.confidence > $1.confidence }) {
            guard retained.allSatisfy({ hypot(Double(peak.x - $0.x), Double(peak.y - $0.y)) > 16 }) else {
                continue
            }
            retained.append(peak)
            if retained.count == configuration.maximumCandidatesPerFrame { break }
        }

        return retained.map { peak in
            GolfBallDetectionCandidate(
                frameIndex: frameIndex,
                presentationTime: presentationTime,
                point: NormalizedPoint(
                    x: Double(peak.x) / Double(current.width),
                    y: Double(peak.y) / Double(current.height)
                ),
                confidence: peak.confidence
            )
        }
    }

    private static func makeInput(
        frames: [RGBFrame],
        xOrigin: Int,
        yOrigin: Int
    ) throws -> MLMultiArray {
        let array = try MLMultiArray(
            shape: [1, 9, NSNumber(value: modelHeight), NSNumber(value: modelWidth)],
            dataType: .float32
        )
        let pointer = array.dataPointer.bindMemory(to: Float32.self, capacity: array.count)
        let channelStride = array.strides[1].intValue
        let rowStride = array.strides[2].intValue
        let columnStride = array.strides[3].intValue

        for (frameOffset, frame) in frames.enumerated() {
            frame.rgba.withUnsafeBytes { rawBuffer in
                guard let source = rawBuffer.bindMemory(to: UInt8.self).baseAddress else { return }
                for y in 0..<modelHeight {
                    let sourceRow = ((yOrigin + y) * frame.width + xOrigin) * 4
                    let destinationRow = y * rowStride
                    for x in 0..<modelWidth {
                        let sourcePixel = sourceRow + (x * 4)
                        let destinationPixel = destinationRow + (x * columnStride)
                        for channel in 0..<3 {
                            let destinationChannel = ((frameOffset * 3) + channel) * channelStride
                            pointer[destinationChannel + destinationPixel] = Float32(source[sourcePixel + channel]) / 255
                        }
                    }
                }
            }
        }
        return array
    }

    private static func peak(in heatmap: MLMultiArray) -> (x: Int, y: Int, confidence: Double)? {
        guard heatmap.dataType == .float32, heatmap.shape.count == 4 else { return nil }
        let pointer = heatmap.dataPointer.bindMemory(to: Float32.self, capacity: heatmap.count)
        let rowStride = heatmap.strides[2].intValue
        let columnStride = heatmap.strides[3].intValue
        var bestValue = -Float32.infinity
        var bestX = 0
        var bestY = 0
        for y in 0..<modelHeight {
            let row = y * rowStride
            for x in 0..<modelWidth {
                let value = pointer[row + (x * columnStride)]
                if value > bestValue {
                    bestValue = value
                    bestX = x
                    bestY = y
                }
            }
        }
        return (bestX, bestY, Double(bestValue))
    }

    private static func tileOrigins(length: Int, tileLength: Int, step: Int) -> [Int] {
        guard length >= tileLength else { return [] }
        var values = Array(stride(from: 0, through: length - tileLength, by: step))
        let last = length - tileLength
        if values.last != last { values.append(last) }
        return values
    }

    private static func estimate(from track: GolfBallTrack) -> BallFlightEstimate {
        let points = track.detections.map(\.point)
        let times = track.detections.map(\.presentationTime)
        let trajectory = DetectedTrajectory(
            detectedPoints: points,
            projectedPoints: [],
            presentationTimes: times,
            equationCoefficients: [],
            confidence: track.confidence
        )
        return BallFlightEstimate(
            launch: points[0],
            apex: points[points.count / 2],
            landing: points[points.count - 1],
            source: .observed,
            confidence: track.confidence,
            observedPointCount: points.count,
            observedTrajectory: trajectory
        )
    }

    private struct PixelPeak {
        let x: Int
        let y: Int
        let confidence: Double
    }

    private struct RGBFrame {
        let width: Int
        let height: Int
        let rgba: [UInt8]

        init(image: CGImage) throws {
            let frameWidth = image.width
            let frameHeight = image.height
            width = frameWidth
            height = frameHeight
            var bytes = [UInt8](repeating: 0, count: frameWidth * frameHeight * 4)
            let rendered = bytes.withUnsafeMutableBytes { rawBuffer -> Bool in
                guard let context = CGContext(
                    data: rawBuffer.baseAddress,
                    width: frameWidth,
                    height: frameHeight,
                    bitsPerComponent: 8,
                    bytesPerRow: frameWidth * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue
                        | CGImageAlphaInfo.premultipliedLast.rawValue
                ) else { return false }
                context.draw(image, in: CGRect(x: 0, y: 0, width: frameWidth, height: frameHeight))
                return true
            }
            guard rendered else {
                throw WASBGolfBallTrackingError.modelFailed("The source frame could not be decoded.")
            }
            rgba = bytes
        }
    }
}
