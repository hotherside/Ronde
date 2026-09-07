@preconcurrency import AVFoundation
import CoreGraphics
import CoreImage
import CoreText
import Foundation

struct ShotVideoExportRequest: Sendable {
    let sourceURL: URL
    let edit: ShotVideoEdit
    let trace: ShotVideoTrace?
}

enum ShotVideoExportError: LocalizedError, Sendable {
    case unavailable, invalidRange, cannotRead, cannotWrite, cancelled
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable: "The original video is not available on this device."
        case .invalidRange: "Choose a cut inside the original video."
        case .cannotRead: "This video could not be decoded. Try another recording."
        case .cannotWrite: "Ronde could not create the MP4. Check available device storage and try again."
        case .cancelled: "Export cancelled."
        case let .failed(message): message
        }
    }
}

/// A local H.264/AAC encoder. A video composition performs only orientation and aspect-fit;
/// source-timed strokes are drawn into the output pixel buffer without Core Animation export.
/// This avoids the IOSurface/Core Animation path that failed on the earlier Simulator build.
actor ShotVideoExporter {
    func export(_ request: ShotVideoExportRequest, progress: @escaping @Sendable (Double) async -> Void) async throws -> URL {
        guard FileManager.default.fileExists(atPath: request.sourceURL.path) else { throw ShotVideoExportError.unavailable }
        try Task.checkCancellation()
        let asset = AVURLAsset(url: request.sourceURL)
        let duration = try await asset.load(.duration).seconds
        let edit = request.edit
        guard edit.trimStart.isFinite, edit.trimEnd.isFinite, edit.trimStart >= 0,
              edit.duration > 0, edit.trimEnd <= duration + 0.001 else { throw ShotVideoExportError.invalidRange }
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw ShotVideoExportError.cannotRead }
        let naturalSize = try await track.load(.naturalSize)
        let preferredTransform = try await track.load(.preferredTransform)
        let nominalRate = try await track.load(.nominalFrameRate)
        let display = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
        guard abs(display.width) > 1, abs(display.height) > 1 else { throw ShotVideoExportError.cannotRead }
        let ratio = abs(display.width / display.height)
        let canvas = edit.format.renderSize(sourceAspectRatio: ratio)
        let fitted = ShotVideoLayout.fittedRect(sourceAspectRatio: ratio, canvasSize: canvas)

        // AVFoundation owns source orientation. The same top-left fitted rectangle is used by UI.
        var transform = preferredTransform
        transform.tx -= display.minX
        transform.ty -= display.minY
        let scale = fitted.width / abs(display.width)
        transform = transform.concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(translationX: fitted.minX, y: fitted.minY))
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: CMTime(seconds: duration, preferredTimescale: 60_000))
        instruction.backgroundColor = CGColor(gray: 0, alpha: 1)
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
        layerInstruction.setTransform(transform, at: .zero)
        instruction.layerInstructions = [layerInstruction]
        let composition = AVMutableVideoComposition()
        composition.renderSize = canvas
        // High-frame-rate sources remain eligible. Social derivatives use at most 60 fps;
        // overlay time is always the decoded source PTS, never the output frame index.
        let rate: Int32 = nominalRate > 45 ? 60 : (nominalRate > 23 && nominalRate < 26 ? 25 : 30)
        composition.frameDuration = CMTime(value: 1, timescale: rate)
        composition.instructions = [instruction]

        let reader = try AVAssetReader(asset: asset)
        reader.timeRange = CMTimeRange(
            start: CMTime(seconds: edit.trimStart, preferredTimescale: 60_000),
            duration: CMTime(seconds: edit.duration, preferredTimescale: 60_000)
        )
        let videoOutput = AVAssetReaderVideoCompositionOutput(videoTracks: [track], videoSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        videoOutput.videoComposition = composition
        videoOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(videoOutput) else { throw ShotVideoExportError.cannotRead }
        reader.add(videoOutput)

        let destination = FileManager.default.temporaryDirectory.appendingPathComponent("ronde-export-\(UUID().uuidString).mp4")
        let writer = try AVAssetWriter(outputURL: destination, fileType: .mp4)
        writer.shouldOptimizeForNetworkUse = true
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(canvas.width),
            AVVideoHeightKey: Int(canvas.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: rate > 30 ? 14_000_000 : 9_000_000,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoExpectedSourceFrameRateKey: rate
            ]
        ])
        videoInput.expectsMediaDataInRealTime = false
        guard writer.canAdd(videoInput) else { throw ShotVideoExportError.cannotWrite }
        writer.add(videoInput)
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: videoInput, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(canvas.width),
            kCVPixelBufferHeightKey as String: Int(canvas.height),
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ])

        var audioOutput: AVAssetReaderAudioMixOutput?
        var audioInput: AVAssetWriterInput?
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        var preferredAudio: AVAssetTrack?
        for audioTrack in audioTracks {
            let descriptions = try await audioTrack.load(.formatDescriptions)
            let channels = descriptions.first.flatMap { CMAudioFormatDescriptionGetStreamBasicDescription($0)?.pointee.mChannelsPerFrame } ?? 0
            if channels == 2 { preferredAudio = audioTrack; break }
            if channels == 1, preferredAudio == nil { preferredAudio = audioTrack }
        }
        if let audioTrack = preferredAudio ?? audioTracks.last {
            let output = AVAssetReaderAudioMixOutput(audioTracks: [audioTrack], audioSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 2,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false
            ])
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 160_000
            ])
            input.expectsMediaDataInRealTime = false
            guard reader.canAdd(output), writer.canAdd(input) else { throw ShotVideoExportError.cannotWrite }
            reader.add(output); writer.add(input)
            audioOutput = output; audioInput = input
        }

        let pipeline = ShotVideoEncodingPipeline(reader: reader, writer: writer, videoOutput: videoOutput, videoInput: videoInput, adaptor: adaptor, audioOutput: audioOutput, audioInput: audioInput, edit: edit, canvas: canvas, sourceRect: fitted, trace: request.trace)
        do {
            try Task.checkCancellation()
            try await withTaskCancellationHandler {
                try await pipeline.run(progress: progress)
            } onCancel: {
                pipeline.cancel()
            }
            try Task.checkCancellation()
            await progress(1)
            return destination
        } catch {
            pipeline.cancel()
            try? FileManager.default.removeItem(at: destination)
            if error is CancellationError || Task.isCancelled { throw CancellationError() }
            throw error
        }
    }
}

/// AVFoundation's readers/writers are used by one serial pump. The cancellation handler only
/// invokes their thread-safe cancellation APIs; no mutable frame data crosses that boundary.
private final class ShotVideoEncodingPipeline: @unchecked Sendable {
    let reader: AVAssetReader
    let writer: AVAssetWriter
    let videoOutput: AVAssetReaderVideoCompositionOutput
    let videoInput: AVAssetWriterInput
    let adaptor: AVAssetWriterInputPixelBufferAdaptor
    let audioOutput: AVAssetReaderAudioMixOutput?
    let audioInput: AVAssetWriterInput?
    let edit: ShotVideoEdit
    let canvas: CGSize
    let sourceRect: CGRect
    let trace: ShotVideoTrace?
    let context = CIContext(options: [.cacheIntermediates: false])

    init(reader: AVAssetReader, writer: AVAssetWriter, videoOutput: AVAssetReaderVideoCompositionOutput, videoInput: AVAssetWriterInput, adaptor: AVAssetWriterInputPixelBufferAdaptor, audioOutput: AVAssetReaderAudioMixOutput?, audioInput: AVAssetWriterInput?, edit: ShotVideoEdit, canvas: CGSize, sourceRect: CGRect, trace: ShotVideoTrace?) {
        self.reader = reader; self.writer = writer; self.videoOutput = videoOutput; self.videoInput = videoInput
        self.adaptor = adaptor; self.audioOutput = audioOutput; self.audioInput = audioInput
        self.edit = edit; self.canvas = canvas; self.sourceRect = sourceRect; self.trace = trace
    }

    func cancel() {
        if reader.status == .reading { reader.cancelReading() }
        if writer.status == .writing { writer.cancelWriting() }
    }

    func run(progress: @escaping @Sendable (Double) async -> Void) async throws {
        guard writer.startWriting(), reader.startReading() else { throw failure() }
        writer.startSession(atSourceTime: .zero)
        var videoDone = false
        var audioDone = audioOutput == nil
        var lastProgress = -1.0
        var latestVideoTime = edit.trimStart
        var wroteVideo = false
        while !videoDone || !audioDone {
            try Task.checkCancellation()
            guard writer.status == .writing, reader.status != .failed else { throw failure() }
            var madeProgress = false
            if !videoDone, videoInput.isReadyForMoreMediaData {
                madeProgress = true
                let time: TimeInterval? = try autoreleasepool {
                    guard let sample = videoOutput.copyNextSampleBuffer() else { return nil }
                    let pts = CMSampleBufferGetPresentationTimeStamp(sample).seconds
                    guard pts < edit.trimEnd else { return nil }
                    guard let inputBuffer = CMSampleBufferGetImageBuffer(sample) else { throw ShotVideoExportError.cannotRead }
                    guard let pool = adaptor.pixelBufferPool else { throw ShotVideoExportError.cannotWrite }
                    var outputBuffer: CVPixelBuffer?
                    guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &outputBuffer) == kCVReturnSuccess,
                          let outputBuffer else { throw ShotVideoExportError.cannotWrite }
                    context.render(CIImage(cvPixelBuffer: inputBuffer), to: outputBuffer, bounds: CGRect(origin: .zero, size: canvas), colorSpace: CGColorSpaceCreateDeviceRGB())
                    if let trace { draw(trace: trace, at: pts, into: outputBuffer) }
                    // The first decoded image covers a fractional-frame trim boundary. All later
                    // frames preserve their original PTS relative to the requested source cut.
                    let relative = wroteVideo ? max(0, pts - edit.trimStart) : 0
                    guard adaptor.append(outputBuffer, withPresentationTime: CMTime(seconds: relative, preferredTimescale: 60_000)) else { throw failure() }
                    wroteVideo = true
                    return pts
                }
                if let time { latestVideoTime = time } else { videoDone = true; videoInput.markAsFinished() }
            }
            if !audioDone, let audioInput, let audioOutput, audioInput.isReadyForMoreMediaData {
                madeProgress = true
                let hasSample: Bool = try autoreleasepool {
                    guard let sample = audioOutput.copyNextSampleBuffer() else { return false }
                    if let shifted = try Self.audioSample(sample, range: edit.sourceRange) {
                        guard audioInput.append(shifted) else { throw failure() }
                    }
                    return true
                }
                if !hasSample { audioDone = true; audioInput.markAsFinished() }
            }
            let fraction = min(0.98, max(0, (latestVideoTime - edit.trimStart) / edit.duration))
            if fraction - lastProgress >= 0.015 { lastProgress = fraction; await progress(fraction) }
            if !madeProgress { try await Task.sleep(for: .milliseconds(3)) }
        }
        guard wroteVideo, reader.status != .failed else { throw failure() }
        writer.endSession(atSourceTime: CMTime(seconds: edit.duration, preferredTimescale: 60_000))
        await writer.finishWriting()
        guard writer.status == .completed else { throw failure() }
    }

    private func failure() -> ShotVideoExportError {
        if let error = reader.error ?? writer.error { return .failed(error.localizedDescription) }
        return .cannotWrite
    }

    private func draw(trace: ShotVideoTrace, at time: TimeInterval, into buffer: CVPixelBuffer) {
        let visible = trace.visiblePoints(at: time)
        guard visible.count > 1 else { return }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer),
              let cg = CGContext(data: base, width: Int(canvas.width), height: Int(canvas.height), bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue) else { return }
        cg.translateBy(x: 0, y: canvas.height)
        cg.scaleBy(x: 1, y: -1)
        let path = CGMutablePath()
        for (index, point) in visible.enumerated() {
            let position = ShotVideoLayout.point(point, in: sourceRect)
            if index == 0 { path.move(to: position) } else { path.addLine(to: position) }
        }
        cg.saveGState()
        cg.clip(to: sourceRect)
        cg.setLineCap(.round); cg.setLineJoin(.round)
        let lineWidth = max(3, min(sourceRect.width, sourceRect.height) * 0.004)
        cg.addPath(path); cg.setStrokeColor(CGColor(gray: 0, alpha: 0.5)); cg.setLineWidth(lineWidth + 2); cg.strokePath()
        cg.addPath(path); cg.setStrokeColor(CGColor(red: 0.53, green: 0.27, blue: 0.91, alpha: 1)); cg.setLineWidth(lineWidth); cg.strokePath()
        cg.restoreGState()
        // Provenance is burned into the derivative, including a manual-only label.
        let font = CTFontCreateWithName("HelveticaNeue-Medium" as CFString, max(18, min(canvas.width, canvas.height) * 0.022), nil)
        let text = NSAttributedString(string: trace.label, attributes: [.init(kCTFontAttributeName as String): font, .init(kCTForegroundColorAttributeName as String): CGColor(gray: 1, alpha: 1)])
        let line = CTLineCreateWithAttributedString(text)
        let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        let labelHeight: CGFloat = max(36, min(canvas.width, canvas.height) * 0.045)
        let inset: CGFloat = 20
        cg.setFillColor(CGColor(gray: 0, alpha: 0.72))
        cg.fill(CGRect(x: inset, y: canvas.height - inset - labelHeight, width: width + 24, height: labelHeight))
        cg.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        cg.textPosition = CGPoint(x: inset + 12, y: canvas.height - inset - labelHeight * 0.30)
        CTLineDraw(line, cg)
    }

    private static func audioSample(_ sample: CMSampleBuffer, range: ReviewTimeRange) throws -> CMSampleBuffer? {
        let pts = CMSampleBufferGetPresentationTimeStamp(sample).seconds
        let count = CMSampleBufferGetNumSamples(sample)
        guard count > 0, let description = CMSampleBufferGetFormatDescription(sample),
              let stream = CMAudioFormatDescriptionGetStreamBasicDescription(description) else { return nil }
        let rate = stream.pointee.mSampleRate
        guard rate > 0 else { return nil }
        let first = max(0, Int(ceil((range.start - pts) * rate - 0.001)))
        let end = min(count, Int(ceil((range.end - pts) * rate - 0.001)))
        guard end > first else { return nil }
        var clipped: CMSampleBuffer?
        guard CMSampleBufferCopySampleBufferForRange(allocator: kCFAllocatorDefault, sampleBuffer: sample, sampleRange: CFRange(location: first, length: end - first), sampleBufferOut: &clipped) == noErr, let clipped else { throw ShotVideoExportError.cannotRead }
        var needed = 0
        CMSampleBufferGetSampleTimingInfoArray(clipped, entryCount: 0, arrayToFill: nil, entriesNeededOut: &needed)
        var timing = [CMSampleTimingInfo](repeating: CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: .invalid, decodeTimeStamp: .invalid), count: needed)
        CMSampleBufferGetSampleTimingInfoArray(clipped, entryCount: needed, arrayToFill: &timing, entriesNeededOut: &needed)
        let offset = CMTime(seconds: range.start, preferredTimescale: 60_000)
        for index in timing.indices {
            timing[index].presentationTimeStamp = CMTimeSubtract(timing[index].presentationTimeStamp, offset)
            if timing[index].decodeTimeStamp.isValid { timing[index].decodeTimeStamp = CMTimeSubtract(timing[index].decodeTimeStamp, offset) }
        }
        var shifted: CMSampleBuffer?
        guard CMSampleBufferCreateCopyWithNewTiming(allocator: kCFAllocatorDefault, sampleBuffer: clipped, sampleTimingEntryCount: timing.count, sampleTimingArray: &timing, sampleBufferOut: &shifted) == noErr else { throw ShotVideoExportError.cannotRead }
        return shifted
    }
}
