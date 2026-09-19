@preconcurrency import AVFoundation
import CoreImage
import Foundation

/// Pull-based, single-owner video decoding for the native tracker.
///
/// Open and use this instance on one serial task. It deliberately does not
/// conform to Sendable. Only timestamp metadata and one full RGB frame are
/// retained; tensors and frame caches are never written to disk.
final class EdgeTAMDirectVideoFrames {
    let sourceWidth: Int
    let sourceHeight: Int
    let frameTimes: [Double]
    /// Indices in the complete source decode, not the selected interval.
    let sourceFrameIndices: [Int]

    private let asset: AVURLAsset
    private let track: AVAssetTrack
    private let transform: CGAffineTransform
    private let sampleTimes: [CMTime]
    private let decodeEnd: CMTime
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let preprocessor = EdgeTAMImagePreprocessor()
    private var reader: AVAssetReader?
    private var output: AVAssetReaderTrackOutput?
    private var cursorNextIndex: Int?
    private var cachedIndex: Int?
    private var cachedFrame: EdgeTAMSourceFrame?
    private var stopped = false

    // Aggregate diagnostics, with no image content or private coordinates.
    private(set) var readerStartCount = 0
    private(set) var sequentialReuseCount = 0
    private(set) var rgbConversionCount = 0
    private(set) var sameFrameCacheHitCount = 0
    var retainedRGBFrameCount: Int { cachedFrame == nil ? 0 : 1 }
    var retainedRGBByteCount: Int { cachedFrame?.rgbBytes.count ?? 0 }

    private init(asset: AVURLAsset, track: AVAssetTrack, transform: CGAffineTransform,
                 width: Int, height: Int, sampleTimes: [CMTime], sourceIndices: [Int],
                 decodeEnd: CMTime) {
        self.asset = asset
        self.track = track
        self.transform = transform
        sourceWidth = width
        sourceHeight = height
        self.sampleTimes = sampleTimes
        frameTimes = sampleTimes.map(\.seconds)
        sourceFrameIndices = sourceIndices
        self.decodeEnd = decodeEnd
    }

    static func open(url: URL, sourceInterval: ClosedRange<Double>) async throws -> sending EdgeTAMDirectVideoFrames {
        guard sourceInterval.lowerBound.isFinite, sourceInterval.upperBound.isFinite,
              sourceInterval.lowerBound >= 0, sourceInterval.upperBound > sourceInterval.lowerBound else {
            throw EdgeTAMNativeError.invalidState("Video interval must have finite increasing non-negative bounds")
        }
        try Task.checkCancellation()
        let asset = AVURLAsset(url: url)
        guard try await asset.load(.isReadable),
              let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw EdgeTAMNativeError.invalidState("Direct video source is unreadable or has no video track")
        }
        let duration = try await asset.load(.duration)
        let size = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let extent = CGRect(origin: .zero, size: size).applying(transform).standardized
        guard duration.isNumeric, duration.seconds > 0,
              extent.width.isFinite, extent.height.isFinite,
              extent.width >= 1, extent.height >= 1 else {
            throw EdgeTAMNativeError.invalidState("Direct video source has invalid duration or dimensions")
        }
        let width = Int(extent.width.rounded())
        let height = Int(extent.height.rounded())
        let (reader, output) = try makeReader(asset: asset, track: track, timeRange: nil)
        defer { reader.cancelReading() }
        var sampleTimes: [CMTime] = []
        var sourceIndices: [Int] = []
        var sourceIndex = 0
        var lastTime: Double?
        var decodeEnd = duration
        // Decode from source start so source indices match the full BGRA decode.
        // No RGB conversion, image retention, nominal FPS or compressed indices.
        while let sample = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            let time = CMSampleBufferGetPresentationTimeStamp(sample)
            let seconds = time.seconds
            guard time.isNumeric, seconds.isFinite,
                  lastTime == nil || seconds > lastTime! else {
                throw EdgeTAMNativeError.invalidState("Direct video PTS must be finite and strictly increasing")
            }
            guard CMSampleBufferGetImageBuffer(sample) != nil else {
                throw EdgeTAMNativeError.invalidState("Metadata decode returned no BGRA image buffer")
            }
            lastTime = seconds
            if seconds > sourceInterval.upperBound {
                decodeEnd = time
                break
            }
            if seconds >= sourceInterval.lowerBound {
                sampleTimes.append(time)
                sourceIndices.append(sourceIndex)
            }
            sourceIndex += 1
        }
        try checkReader(reader, stage: "metadata decode")
        guard !sampleTimes.isEmpty, CMTimeCompare(decodeEnd, sampleTimes.last!) > 0 else {
            throw EdgeTAMNativeError.invalidState("Requested video interval contains no usable source frames")
        }
        try Task.checkCancellation()
        return EdgeTAMDirectVideoFrames(asset: asset, track: track, transform: transform,
                                        width: width, height: height, sampleTimes: sampleTimes,
                                        sourceIndices: sourceIndices, decodeEnd: decodeEnd)
    }

    func tensor(index: Int, crop: EdgeTAMSourceCrop) throws -> EdgeTAMTensor {
        guard frameTimes.indices.contains(index) else {
            throw EdgeTAMNativeError.invalidState("Requested video frame index is outside the selected interval")
        }
        guard crop.x >= 0, crop.y >= 0, crop.width > 0, crop.height > 0,
              crop.width <= sourceWidth, crop.height <= sourceHeight,
              crop.x <= sourceWidth - crop.width, crop.y <= sourceHeight - crop.height else {
            throw EdgeTAMNativeError.invalidState("Requested video crop is outside the upright source image")
        }
        guard !stopped else { throw EdgeTAMNativeError.invalidState("Direct video provider has stopped") }
        do {
            try Task.checkCancellation()
            let frame = try frame(index: index)
            let result = try preprocessor.tensor(rgbBytes: frame.rgbBytes, width: frame.width,
                                                  height: frame.height, crop: crop)
            try Task.checkCancellation()
            return result
        } catch {
            close()
            throw error
        }
    }

    /// Drop the full upright RGB frame once its normalised tensor exists. The
    /// sequential decoder cursor remains usable; only a same-index crop reset
    /// must decode that source frame again. This keeps source pixels out of the
    /// first Core ML prediction's peak memory window.
    func discardCachedFrame() {
        cachedIndex = nil
        cachedFrame = nil
    }

    /// Release the decoder and its single RGB cache. The instance cannot reopen.
    func close() {
        reader?.cancelReading()
        reader = nil
        output = nil
        cursorNextIndex = nil
        cachedIndex = nil
        cachedFrame = nil
        stopped = true
    }

    deinit { reader?.cancelReading() }

    private func frame(index: Int) throws -> EdgeTAMSourceFrame {
        if cachedIndex == index, let cachedFrame {
            sameFrameCacheHitCount += 1
            return cachedFrame
        }
        // Drop the prior RGB cache before creating another full RGB image.
        cachedIndex = nil
        cachedFrame = nil
        if cursorNextIndex == index, reader?.status == .reading, output != nil {
            sequentialReuseCount += 1
        } else {
            reader?.cancelReading()
            reader = nil
            output = nil
            cursorNextIndex = nil
            let range = CMTimeRange(start: sampleTimes[index],
                                    duration: CMTimeSubtract(decodeEnd, sampleTimes[index]))
            let created = try Self.makeReader(asset: asset, track: track, timeRange: range)
            reader = created.0
            output = created.1
            readerStartCount += 1
        }
        guard let reader, let output else {
            throw EdgeTAMNativeError.invalidState("Direct video decoder is missing")
        }
        let expected = frameTimes[index]
        while let sample = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            let timestamp = CMSampleBufferGetPresentationTimeStamp(sample).seconds
            guard timestamp.isFinite else {
                throw EdgeTAMNativeError.invalidState("Direct video decoder returned non-finite PTS")
            }
            // Some decoders expose preroll before the requested exact source PTS.
            if timestamp < expected - 0.000_001 { continue }
            guard abs(timestamp - expected) <= 0.000_001,
                  let pixelBuffer = CMSampleBufferGetImageBuffer(sample) else {
                throw EdgeTAMNativeError.invalidState("Direct video seek did not return the requested source PTS")
            }
            let rgb = try autoreleasepool {
                try EdgeTAMSourceFrameReader.copyRGB(pixelBuffer: pixelBuffer,
                                                     preferredTransform: transform, context: context)
            }
            guard rgb.width == sourceWidth, rgb.height == sourceHeight else {
                throw EdgeTAMNativeError.invalidState("Direct video frame dimensions changed during decode")
            }
            let frame = EdgeTAMSourceFrame(sourceFrameIndex: sourceFrameIndices[index],
                                           presentationTime: timestamp, width: rgb.width,
                                           height: rgb.height, rgbBytes: rgb.bytes)
            cachedFrame = frame
            cachedIndex = index
            cursorNextIndex = index + 1
            rgbConversionCount += 1
            return frame
        }
        try Self.checkReader(reader, stage: "requested frame decode")
        throw EdgeTAMNativeError.invalidState("Direct video ended before the requested source frame")
    }

    private static func makeReader(asset: AVURLAsset, track: AVAssetTrack,
                                   timeRange: CMTimeRange?) throws -> (AVAssetReader, AVAssetReaderTrackOutput) {
        let reader = try AVAssetReader(asset: asset)
        if let timeRange { reader.timeRange = timeRange }
        let output = AVAssetReaderTrackOutput(track: track,
            outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else {
            throw EdgeTAMNativeError.invalidState("Cannot add direct video BGRA output")
        }
        reader.add(output)
        guard reader.startReading() else {
            throw reader.error ?? EdgeTAMNativeError.invalidState("Cannot start direct video decode")
        }
        return (reader, output)
    }

    private static func checkReader(_ reader: AVAssetReader, stage: String) throws {
        if reader.status == .failed {
            throw reader.error ?? EdgeTAMNativeError.invalidState("Direct video failed during \(stage)")
        }
        if reader.status == .cancelled { throw CancellationError() }
    }
}
