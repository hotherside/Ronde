@preconcurrency import AVFoundation
import CoreGraphics
import CoreImage
import Foundation

struct EdgeTAMPreferredTransform: Sendable, Equatable {
    let a: Double
    let b: Double
    let c: Double
    let d: Double
    let tx: Double
    let ty: Double

    init(_ transform: CGAffineTransform) {
        a = Double(transform.a)
        b = Double(transform.b)
        c = Double(transform.c)
        d = Double(transform.d)
        tx = Double(transform.tx)
        ty = Double(transform.ty)
    }
}

struct EdgeTAMSourceFrameInfo: Sendable, Equatable {
    let sourceWidth: Int
    let sourceHeight: Int
    let orientedWidth: Int
    let orientedHeight: Int
    let duration: TimeInterval
    let preferredTransform: EdgeTAMPreferredTransform
    let sourceInterval: ClosedRange<TimeInterval>?
}

struct EdgeTAMSourceFrame: Sendable {
    /// Sequential decoder index for the configured reader interval.
    let sourceFrameIndex: Int
    /// The sample buffer's presentation timestamp in the source timeline.
    let presentationTime: TimeInterval
    let width: Int
    let height: Int
    /// Owned, tightly packed top-left RGB bytes, three bytes per pixel.
    let rgbBytes: [UInt8]
}

/// Sequential AVFoundation reader with bounded retained state.
///
/// The callback receives one owned RGB frame at a time. The reader does not
/// cache frames or infer timestamps from nominal frame rate. Preferred track
/// orientation is applied before RGB extraction, so portrait dimensions and
/// row order are in the displayed top-left coordinate space.
struct EdgeTAMSourceFrameReader: Sendable {
    let url: URL
    let sourceInterval: ClosedRange<TimeInterval>?

    init(url: URL, sourceInterval: ClosedRange<TimeInterval>? = nil) throws {
        if let sourceInterval {
            guard sourceInterval.lowerBound.isFinite,
                  sourceInterval.upperBound.isFinite,
                  sourceInterval.lowerBound >= 0,
                  sourceInterval.upperBound > sourceInterval.lowerBound else {
                throw EdgeTAMNativeError.invalidState("Source interval must be finite, positive and non-negative")
            }
        }
        self.url = url
        self.sourceInterval = sourceInterval
    }

    @discardableResult
    func read(
        onFrame: @escaping @Sendable (EdgeTAMSourceFrameInfo, EdgeTAMSourceFrame) throws -> Void
    ) async throws -> EdgeTAMSourceFrameInfo {
        let asset = AVURLAsset(url: url)
        guard try await asset.load(.isReadable) else {
            throw EdgeTAMNativeError.invalidState("Source asset is not readable")
        }
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw EdgeTAMNativeError.invalidState("Source has no video track")
        }
        let duration = try await asset.load(.duration).seconds
        let naturalSize = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let orientedExtent = CGRect(origin: .zero, size: naturalSize).applying(transform).standardized
        let orientedWidth = max(1, Int(orientedExtent.width.rounded()))
        let orientedHeight = max(1, Int(orientedExtent.height.rounded()))
        let info = EdgeTAMSourceFrameInfo(
            sourceWidth: max(1, Int(naturalSize.width.rounded())),
            sourceHeight: max(1, Int(naturalSize.height.rounded())),
            orientedWidth: orientedWidth,
            orientedHeight: orientedHeight,
            duration: duration,
            preferredTransform: EdgeTAMPreferredTransform(transform),
            sourceInterval: sourceInterval
        )

        let reader = try AVAssetReader(asset: asset)
        if let sourceInterval {
            reader.timeRange = CMTimeRange(
                start: CMTime(seconds: sourceInterval.lowerBound, preferredTimescale: 60_000),
                duration: CMTime(seconds: sourceInterval.upperBound - sourceInterval.lowerBound, preferredTimescale: 60_000)
            )
        }
        let output = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        )
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else {
            throw EdgeTAMNativeError.invalidState("Cannot add source video output")
        }
        reader.add(output)
        guard reader.startReading() else {
            throw reader.error ?? EdgeTAMNativeError.invalidState("Source reader failed to start")
        }

        let context = CIContext(options: [.cacheIntermediates: false])
        var frameIndex = 0
        var lastPresentationTime: TimeInterval?
        while let sampleBuffer = output.copyNextSampleBuffer() {
            if Task.isCancelled {
                reader.cancelReading()
                throw CancellationError()
            }
            let currentIndex = frameIndex
            frameIndex += 1
            let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
            guard timestamp.isFinite else {
                throw EdgeTAMNativeError.invalidState("Source frame has a non-finite presentation timestamp")
            }
            if let lastPresentationTime, timestamp < lastPresentationTime {
                throw EdgeTAMNativeError.invalidState("Source presentation timestamps are not monotonic")
            }
            lastPresentationTime = timestamp
            if let sourceInterval,
               timestamp < sourceInterval.lowerBound || timestamp > sourceInterval.upperBound {
                continue
            }
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                throw EdgeTAMNativeError.invalidState("Source sample has no image buffer")
            }
            let rgb = try Self.copyRGB(
                pixelBuffer: pixelBuffer,
                preferredTransform: transform,
                context: context
            )
            let frame = EdgeTAMSourceFrame(
                sourceFrameIndex: currentIndex,
                presentationTime: timestamp,
                width: rgb.width,
                height: rgb.height,
                rgbBytes: rgb.bytes
            )
            try onFrame(info, frame)
        }
        guard reader.status != .failed else {
            throw reader.error ?? EdgeTAMNativeError.invalidState("Source reader failed")
        }
        return info
    }

    static func copyRGB(
        pixelBuffer: CVPixelBuffer,
        preferredTransform: CGAffineTransform,
        context: CIContext
    ) throws -> (width: Int, height: Int, bytes: [UInt8]) {
        // Match the reference PNG path for every source, including identity
        // transforms: bypassing Core Image changes decoded RGB colour values.

        let source = CIImage(cvPixelBuffer: pixelBuffer).transformed(by: preferredTransform)
        let translated = source.transformed(
            by: CGAffineTransform(translationX: -source.extent.minX, y: -source.extent.minY)
        )
        let extent = translated.extent.integral
        let width = max(1, Int(extent.width.rounded()))
        let height = max(1, Int(extent.height.rounded()))
        guard let image = context.createCGImage(translated, from: extent) else {
            throw EdgeTAMNativeError.invalidState("Could not orient source pixel buffer")
        }
        var rgba = Array(repeating: UInt8.zero, count: width * height * 4)
        let rendered = rgba.withUnsafeMutableBytes { rawBuffer -> Bool in
            guard let context = CGContext(
                data: rawBuffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard rendered else { throw EdgeTAMNativeError.invalidState("Could not render oriented RGB frame") }
        var rgb = Array(repeating: UInt8.zero, count: width * height * 3)
        for pixel in 0..<(width * height) {
            rgb[pixel * 3] = rgba[pixel * 4]
            rgb[pixel * 3 + 1] = rgba[pixel * 4 + 1]
            rgb[pixel * 3 + 2] = rgba[pixel * 4 + 2]
        }
        return (width, height, rgb)
    }

}
