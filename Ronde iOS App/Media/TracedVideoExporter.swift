@preconcurrency import AVFoundation
import CoreGraphics
import Foundation
import QuartzCore

enum TracedVideoExportError: LocalizedError, Sendable, Equatable {
    case sourceUnavailable
    case sourceIsNotExportable
    case sourceHasNoVideoTrack
    case invalidRange
    case noStoredTracerGeometry
    case cannotCreateExportSession
    case cancelled
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .sourceUnavailable:
            "The local source video is no longer available for export."
        case .sourceIsNotExportable:
            "This video cannot be exported on this device."
        case .sourceHasNoVideoTrack:
            "This video does not contain a readable video track."
        case .invalidRange:
            "The requested shot clip is outside the source video."
        case .noStoredTracerGeometry:
            "There is no stored tracer geometry to render."
        case .cannotCreateExportSession:
            "Ronde could not create a traced-video export."
        case .cancelled:
            "Traced-video export was cancelled."
        case let .failed(message):
            message
        }
    }
}

/// Provenance travels with the render request so the exporter can never draw a user-assisted arc
/// with the visual treatment reserved for source-frame ball observations.
enum TracedVideoTracerProvenance: Sendable, Equatable {
    case observed
    case observedAndInferred
    case userAssisted

    var label: String {
        switch self {
        case .observed: "Observed ball track"
        case .observedAndInferred: "Observed launch · estimated flight"
        case .userAssisted: "Manual tracer"
        }
    }
}

/// Immutable source-independent geometry passed into export. No detector or image analysis is
/// reachable from this type, which guarantees export reuses the reviewer's stored path.
struct TracedVideoTracerGeometry: Sendable, Equatable {
    let observedPoints: [NormalizedPoint]
    let inferredContinuation: [NormalizedPoint]
    let provenance: TracedVideoTracerProvenance
    let observedPresentationDuration: TimeInterval?
    let inferredPresentationDuration: TimeInterval

    init?(path: EvidenceAnchoredFlightPath) {
        guard path.observedPoints.count >= 3 else { return nil }
        self.observedPoints = path.observedPoints
        self.inferredContinuation = path.inferredContinuation
        self.provenance = path.source == .observedAndInferred ? .observedAndInferred : .observed
        self.observedPresentationDuration = path.observedDuration
        self.inferredPresentationDuration = path.inferredPresentationDuration
    }

    init(manualLaunch: NormalizedPoint, apex: NormalizedPoint, landing: NormalizedPoint) {
        self.observedPoints = Self.quadraticPoints(from: manualLaunch, through: apex, to: landing)
        self.inferredContinuation = []
        self.provenance = .userAssisted
        self.observedPresentationDuration = nil
        self.inferredPresentationDuration = 0
    }

    var inferredSegmentPoints: [NormalizedPoint] {
        guard let endpoint = observedPoints.last, !inferredContinuation.isEmpty else { return [] }
        return [endpoint] + inferredContinuation
    }

    private static func quadraticPoints(
        from launch: NormalizedPoint,
        through apex: NormalizedPoint,
        to landing: NormalizedPoint
    ) -> [NormalizedPoint] {
        // The editor's apex handle lies on the curve at t = 0.5, so derive the quadratic control
        // point rather than treating the handle itself as a Bézier control point.
        let controlX = (2 * apex.x) - ((launch.x + landing.x) / 2)
        let controlY = (2 * apex.y) - ((launch.y + landing.y) / 2)
        return (0...14).map { index in
            let t = Double(index) / 14
            let inverse = 1 - t
            return NormalizedPoint(
                x: (inverse * inverse * launch.x) + (2 * inverse * t * controlX) + (t * t * landing.x),
                y: (inverse * inverse * launch.y) + (2 * inverse * t * controlY) + (t * t * landing.y)
            )
        }
    }
}

struct TracedVideoExportRequest: Sendable, Equatable {
    let sourceURL: URL
    let sourceRange: ReviewTimeRange
    /// Source presentation time at which the stored overlay begins to reveal.
    let revealStartTime: TimeInterval
    let geometry: TracedVideoTracerGeometry

    init(sourceURL: URL, sourceRange: ReviewTimeRange, revealStartTime: TimeInterval, geometry: TracedVideoTracerGeometry) {
        self.sourceURL = sourceURL
        self.sourceRange = sourceRange
        self.revealStartTime = max(0, revealStartTime)
        self.geometry = geometry
    }
}

/// Renders a self-contained local MOV with the stored review geometry. The exporter never calls a
/// tracker, requests a frame, or creates a fallback trajectory while rendering.
actor TracedVideoExporter {
    func export(_ request: TracedVideoExportRequest) async throws -> URL {
        guard request.geometry.observedPoints.count >= 3 else {
            throw TracedVideoExportError.noStoredTracerGeometry
        }

        let asset = AVURLAsset(url: request.sourceURL)
        guard try await asset.load(.isExportable) else {
            throw TracedVideoExportError.sourceIsNotExportable
        }
        let duration = CMTimeGetSeconds(try await asset.load(.duration))
        guard request.sourceRange.start < duration,
              request.sourceRange.duration > 0,
              request.sourceRange.end <= duration + 0.001 else {
            throw TracedVideoExportError.invalidRange
        }
        guard let sourceVideoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw TracedVideoExportError.sourceHasNoVideoTrack
        }

        let composition = AVMutableComposition()
        guard let videoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw TracedVideoExportError.cannotCreateExportSession
        }
        let sourceTimeRange = CMTimeRange(
            start: CMTime(seconds: request.sourceRange.start, preferredTimescale: 60_000),
            duration: CMTime(seconds: request.sourceRange.duration, preferredTimescale: 60_000)
        )
        try videoTrack.insertTimeRange(sourceTimeRange, of: sourceVideoTrack, at: .zero)
        let transform = try await sourceVideoTrack.load(.preferredTransform)
        videoTrack.preferredTransform = transform

        if let sourceAudioTrack = try await asset.loadTracks(withMediaType: .audio).first,
           let audioTrack = composition.addMutableTrack(
               withMediaType: .audio,
               preferredTrackID: kCMPersistentTrackID_Invalid
           ) {
            try? audioTrack.insertTimeRange(sourceTimeRange, of: sourceAudioTrack, at: .zero)
        }

        let naturalSize = try await sourceVideoTrack.load(.naturalSize)
        let transformedSize = naturalSize.applying(transform)
        let renderSize = CGSize(width: abs(transformedSize.width), height: abs(transformedSize.height))
        guard renderSize.width > 1, renderSize.height > 1 else {
            throw TracedVideoExportError.sourceHasNoVideoTrack
        }

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = renderSize
        let sourceMinimumFrameDuration = try await sourceVideoTrack.load(.minFrameDuration)
        let sourceFrameSeconds = CMTimeGetSeconds(sourceMinimumFrameDuration)
        let exportFrameSeconds: TimeInterval
        if sourceMinimumFrameDuration.isValid, sourceFrameSeconds.isFinite, sourceFrameSeconds > 0 {
            // Preserve common 25/30/50/60/120/240 fps sources while bounding malformed or
            // extreme metadata. Tracking and reveal timing still use source PTS, not this cadence.
            exportFrameSeconds = min(1.0 / 24.0, max(1.0 / 240.0, sourceFrameSeconds))
        } else {
            exportFrameSeconds = 1.0 / 30.0
        }
        videoComposition.frameDuration = CMTime(seconds: exportFrameSeconds, preferredTimescale: 60_000)
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: sourceTimeRange.duration)
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
        instruction.layerInstructions = [layerInstruction]
        videoComposition.instructions = [instruction]

        let parentLayer = CALayer()
        parentLayer.frame = CGRect(origin: .zero, size: renderSize)
        let videoLayer = CALayer()
        videoLayer.frame = parentLayer.bounds
        parentLayer.addSublayer(videoLayer)
        parentLayer.addSublayer(Self.makeTracerLayer(
            geometry: request.geometry,
            renderSize: renderSize,
            revealStartTime: max(0, request.revealStartTime - request.sourceRange.start)
        ))
        videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(
            postProcessingAsVideoLayer: videoLayer,
            in: parentLayer
        )

        guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw TracedVideoExportError.cannotCreateExportSession
        }
        let destinationURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ronde-traced-\(UUID().uuidString)")
            .appendingPathExtension("mov")
        exportSession.outputURL = destinationURL
        exportSession.outputFileType = .mov
        exportSession.videoComposition = videoComposition

        let sessionBox = ExportSessionBox(exportSession)
        try await withCheckedThrowingContinuation { continuation in
            sessionBox.session.exportAsynchronously {
                switch sessionBox.session.status {
                case .completed:
                    continuation.resume(returning: ())
                case .cancelled:
                    continuation.resume(throwing: TracedVideoExportError.cancelled)
                default:
                    continuation.resume(throwing: TracedVideoExportError.failed(
                        sessionBox.session.error?.localizedDescription ?? "Traced-video export failed."
                    ))
                }
            }
        }
        return destinationURL
    }

    private static func makeTracerLayer(
        geometry: TracedVideoTracerGeometry,
        renderSize: CGSize,
        revealStartTime: TimeInterval
    ) -> CALayer {
        let container = CALayer()
        container.frame = CGRect(origin: .zero, size: renderSize)

        let observedPath = path(from: geometry.observedPoints, in: renderSize)
        let observedGlow = CAShapeLayer()
        observedGlow.path = observedPath
        observedGlow.fillColor = nil
        observedGlow.strokeColor = CGColor(red: 0.95, green: 0.70, blue: 0.23, alpha: 0.45)
        observedGlow.lineWidth = max(8, renderSize.width * 0.010)
        observedGlow.lineCap = .round
        observedGlow.lineJoin = .round
        observedGlow.shadowColor = CGColor(red: 0.96, green: 0.72, blue: 0.24, alpha: 1)
        observedGlow.shadowRadius = 8
        observedGlow.shadowOpacity = 0.85
        container.addSublayer(observedGlow)

        let observedStroke = CAShapeLayer()
        observedStroke.path = observedPath
        observedStroke.fillColor = nil
        observedStroke.strokeColor = CGColor(red: 0.96, green: 0.72, blue: 0.24, alpha: 1)
        observedStroke.lineWidth = max(3.5, renderSize.width * 0.0048)
        observedStroke.lineCap = .round
        observedStroke.lineJoin = .round
        container.addSublayer(observedStroke)

        let observedDuration = max(0.16, geometry.observedPresentationDuration ?? 0.52)
        animateStroke(observedGlow, beginTime: revealStartTime, duration: observedDuration)
        animateStroke(observedStroke, beginTime: revealStartTime, duration: observedDuration)

        if !geometry.inferredSegmentPoints.isEmpty {
            let inferredStroke = CAShapeLayer()
            inferredStroke.path = path(from: geometry.inferredSegmentPoints, in: renderSize)
            inferredStroke.fillColor = nil
            inferredStroke.strokeColor = CGColor(red: 0.96, green: 0.72, blue: 0.24, alpha: 0.84)
            inferredStroke.lineWidth = max(2.5, renderSize.width * 0.0038)
            inferredStroke.lineCap = .round
            inferredStroke.lineJoin = .round
            inferredStroke.lineDashPattern = [8, 7]
            container.addSublayer(inferredStroke)
            animateStroke(
                inferredStroke,
                beginTime: revealStartTime + observedDuration,
                duration: max(0.12, geometry.inferredPresentationDuration)
            )
        }

        let label = CATextLayer()
        label.string = geometry.provenance.label
        label.font = CGFont("HelveticaNeue-Medium" as CFString)
        label.fontSize = max(12, min(20, renderSize.width * 0.026))
        label.foregroundColor = CGColor(gray: 1, alpha: 0.94)
        label.alignmentMode = .left
        label.contentsScale = 2
        label.frame = CGRect(x: 24, y: renderSize.height - 52, width: renderSize.width - 48, height: 30)
        label.opacity = 0
        container.addSublayer(label)
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.beginTime = AVCoreAnimationBeginTimeAtZero + revealStartTime
        fade.duration = 0.15
        fade.fillMode = .both
        fade.isRemovedOnCompletion = false
        label.add(fade, forKey: "labelFade")

        return container
    }

    private static func path(from points: [NormalizedPoint], in size: CGSize) -> CGPath {
        let path = CGMutablePath()
        guard let first = points.first else { return path }
        path.move(to: point(from: first, in: size))
        for normalizedPoint in points.dropFirst() {
            path.addLine(to: point(from: normalizedPoint, in: size))
        }
        return path
    }

    private static func point(from normalized: NormalizedPoint, in size: CGSize) -> CGPoint {
        // AVVideoComposition Core Animation uses a lower-left origin, while the review model is
        // normalised for SwiftUI's top-left overlay. Convert exactly once at this boundary.
        CGPoint(x: normalized.x * size.width, y: (1 - normalized.y) * size.height)
    }

    private static func animateStroke(_ layer: CAShapeLayer, beginTime: TimeInterval, duration: TimeInterval) {
        layer.strokeEnd = 0
        let animation = CABasicAnimation(keyPath: "strokeEnd")
        animation.fromValue = 0
        animation.toValue = 1
        animation.beginTime = AVCoreAnimationBeginTimeAtZero + beginTime
        animation.duration = duration
        animation.fillMode = .both
        animation.isRemovedOnCompletion = false
        layer.add(animation, forKey: "strokeReveal")
    }
}

private final class ExportSessionBox: @unchecked Sendable {
    let session: AVAssetExportSession

    init(_ session: AVAssetExportSession) {
        self.session = session
    }
}
