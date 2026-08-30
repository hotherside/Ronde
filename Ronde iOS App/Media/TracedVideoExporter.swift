@preconcurrency import AVFoundation
import CoreGraphics
import CoreText
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
    let inferredLaunchConnector: [NormalizedPoint]
    let observedPoints: [NormalizedPoint]
    let observedPresentationTimes: [TimeInterval]
    let inferredContinuation: [NormalizedPoint]
    let provenance: TracedVideoTracerProvenance
    let inferredLaunchPresentationDuration: TimeInterval
    let observedPresentationDuration: TimeInterval?
    let inferredPresentationDuration: TimeInterval
    let estimatedFlightDuration: TimeInterval
    let apexPoint: NormalizedPoint?
    let estimatedCarry: EstimatedCarryDistance?

    init?(path: EvidenceAnchoredFlightPath) {
        guard path.observedPoints.count >= 3 else { return nil }
        self.inferredLaunchConnector = path.inferredLaunchConnector
        self.observedPoints = path.observedPoints
        self.observedPresentationTimes = path.observedPresentationTimes
        self.inferredContinuation = path.inferredContinuation
        self.provenance = path.source == .observedAndInferred ? .observedAndInferred : .observed
        self.inferredLaunchPresentationDuration = path.inferredLaunchPresentationDuration
        self.observedPresentationDuration = path.observedDuration
        self.inferredPresentationDuration = path.inferredPresentationDuration
        self.estimatedFlightDuration = path.estimatedFlightDuration
            ?? max(
                0.18,
                path.inferredLaunchPresentationDuration
                    + (path.observedDuration ?? 0)
                    + path.inferredPresentationDuration
            )
        self.apexPoint = path.apexPoint
        self.estimatedCarry = path.estimatedCarry
    }

    init(manualLaunch: NormalizedPoint, apex: NormalizedPoint, landing: NormalizedPoint) {
        self.inferredLaunchConnector = []
        self.observedPoints = Self.quadraticPoints(from: manualLaunch, through: apex, to: landing)
        self.observedPresentationTimes = []
        self.inferredContinuation = []
        self.provenance = .userAssisted
        self.inferredLaunchPresentationDuration = 0
        self.observedPresentationDuration = nil
        self.inferredPresentationDuration = 0
        self.estimatedFlightDuration = 0
        self.apexPoint = apex
        self.estimatedCarry = nil
    }

    var inferredLaunchSegmentPoints: [NormalizedPoint] {
        guard let firstObserved = observedPoints.first, !inferredLaunchConnector.isEmpty else { return [] }
        return inferredLaunchConnector + [firstObserved]
    }

    var inferredSegmentPoints: [NormalizedPoint] {
        guard let endpoint = observedPoints.last, !inferredContinuation.isEmpty else { return [] }
        return [endpoint] + inferredContinuation
    }

    var timedObservedPath: TimedTrajectoryPath? {
        TimedTrajectoryPath(
            points: observedPoints,
            presentationTimes: observedPresentationTimes
        )
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

        if let sourceAudioTrack = try await asset.loadTracks(withMediaType: .audio).first,
           let audioTrack = composition.addMutableTrack(
               withMediaType: .audio,
               preferredTrackID: kCMPersistentTrackID_Invalid
           ) {
            try? audioTrack.insertTimeRange(sourceTimeRange, of: sourceAudioTrack, at: .zero)
        }

        let naturalSize = try await sourceVideoTrack.load(.naturalSize)
        let displayRect = CGRect(origin: .zero, size: naturalSize).applying(transform)
        let renderSize = CGSize(width: abs(displayRect.width), height: abs(displayRect.height))
        guard renderSize.width > 1, renderSize.height > 1 else {
            throw TracedVideoExportError.sourceHasNoVideoTrack
        }

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = renderSize
        let nominalFrameRate = Double(try await sourceVideoTrack.load(.nominalFrameRate))
        let exportFrameRate = Self.closestCommonFrameRate(to: nominalFrameRate)
        videoComposition.frameDuration = CMTime(
            value: 1,
            timescale: CMTimeScale(exportFrameRate)
        )
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: sourceTimeRange.duration)
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
        var displayTransform = transform
        if displayRect.minX < 0 { displayTransform.tx -= displayRect.minX }
        if displayRect.minY < 0 { displayTransform.ty -= displayRect.minY }
        layerInstruction.setTransform(displayTransform, at: .zero)
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
            revealStartTime: max(0, request.revealStartTime - request.sourceRange.start),
            sourceRangeStartTime: request.sourceRange.start,
            sourceRangeDuration: request.sourceRange.duration
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
        revealStartTime: TimeInterval,
        sourceRangeStartTime: TimeInterval,
        sourceRangeDuration: TimeInterval
    ) -> CALayer {
        let container = CALayer()
        container.frame = CGRect(origin: .zero, size: renderSize)
        let observedDuration = max(0.16, geometry.observedPresentationDuration ?? 0.52)
        let timedObservedPath = geometry.timedObservedPath
        let observedStartTime = timedObservedPath
            .map { max(0, $0.startTime - sourceRangeStartTime) }
            ?? revealStartTime
        let observedEndTime = timedObservedPath
            .map { max(observedStartTime, $0.endTime - sourceRangeStartTime) }
            ?? (observedStartTime + observedDuration)
        let observedTrailLag = timedObservedPath?.suggestedTrailLag ?? 0
        let presentationFlightDuration = FullFlightRevealTimeline.presentationFlightDuration(
            modelFlightDuration: geometry.estimatedFlightDuration,
            impactTime: revealStartTime + sourceRangeStartTime,
            lastObservedTime: timedObservedPath?.endTime
                ?? (revealStartTime + sourceRangeStartTime),
            availablePostImpactDuration: sourceRangeDuration - revealStartTime,
            observedTrailLag: observedTrailLag
        )
        let fullFlightTimeline = geometry.provenance == .userAssisted
            ? nil
            : FullFlightRevealTimeline(
                impactTime: revealStartTime + sourceRangeStartTime,
                inferredLaunchConnector: geometry.inferredLaunchConnector,
                observedPoints: geometry.observedPoints,
                observedPresentationTimes: geometry.observedPresentationTimes,
                inferredContinuation: geometry.inferredContinuation,
                estimatedFlightDuration: geometry.estimatedFlightDuration > 0
                    ? geometry.estimatedFlightDuration
                    : presentationFlightDuration,
                presentationFlightDuration: presentationFlightDuration
            )

        if let fullFlightTimeline {
            addFullFlightTimelineStroke(
                timeline: fullFlightTimeline,
                sourceRangeStartTime: sourceRangeStartTime,
                renderSize: renderSize,
                to: container
            )
        } else if geometry.provenance == .userAssisted {
            addTracerStroke(
                points: geometry.observedPoints,
                estimated: false,
                beginTime: observedStartTime,
                duration: observedDuration,
                renderSize: renderSize,
                to: container
            )
        } else {
            addStaticTracerStroke(
                points: geometry.observedPoints,
                estimated: false,
                fadeInTime: observedEndTime,
                renderSize: renderSize,
                to: container
            )
        }

        addApexMarker(
            geometry: geometry,
            fullFlightTimeline: fullFlightTimeline,
            observedStartTime: observedStartTime,
            observedTrailLag: observedTrailLag,
            sourceRangeStartTime: sourceRangeStartTime,
            renderSize: renderSize,
            to: container
        )
        addEstimatedLandingMarker(
            geometry: geometry,
            fullFlightTimeline: fullFlightTimeline,
            sourceRangeStartTime: sourceRangeStartTime,
            renderSize: renderSize,
            to: container
        )

        let metricText = geometry.estimatedCarry.map { "MODEL CARRY  \($0.displayText)" }
        if let metricText,
           fullFlightTimeline?.revealsEstimatedLanding == true {
            let metricFontSize = max(22, min(46, renderSize.width * 0.012))
            let metricWidth = min(
                renderSize.width - 56,
                max(360, metricFontSize * CGFloat(metricText.count) * 0.72 + 32)
            )
            let metricBadge = textBadge(
                metricText,
                fontSize: metricFontSize,
                frame: CGRect(
                    x: 28,
                    y: renderSize.height - 82,
                    width: metricWidth,
                    height: 54
                )
            )
            let landingRevealTime = fullFlightTimeline
                .map { max(0, $0.endTime - sourceRangeStartTime) }
                ?? observedEndTime
            fadeIn(metricBadge, beginTime: landingRevealTime, duration: 0.08)
            container.addSublayer(metricBadge)
        }

        let provenanceBadge = textBadge(
            geometry.estimatedCarry == nil
                ? geometry.provenance.label.uppercased()
                : "ESTIMATE · UNCALIBRATED",
            fontSize: max(15, min(28, renderSize.width * 0.0075)),
            frame: CGRect(
                x: 28,
                y: renderSize.height - (geometry.estimatedCarry == nil ? 82 : 128),
                width: min(renderSize.width - 56, 560),
                height: 38
            )
        )
        fadeIn(
            provenanceBadge,
            beginTime: fullFlightTimeline
                .map { max(0, $0.impactTime - sourceRangeStartTime) }
                ?? observedStartTime
        )
        container.addSublayer(provenanceBadge)

        return container
    }

    private static func addTracerStroke(
        points: [NormalizedPoint],
        estimated: Bool,
        beginTime: TimeInterval,
        duration: TimeInterval,
        renderSize: CGSize,
        to container: CALayer
    ) {
        guard points.count >= 2 else { return }
        let tracerPurple = CGColor(red: 0.57, green: 0.28, blue: 0.98, alpha: 1)
        let provenanceOpacity: CGFloat = estimated ? 0.74 : 1
        let lineWidth = max(4, renderSize.width * 0.0048)
        let tracerPath = path(from: points, in: renderSize)

        let glow = CAShapeLayer()
        glow.path = tracerPath
        glow.fillColor = nil
        glow.strokeColor = tracerPurple.copy(alpha: 0.48 * provenanceOpacity)
        glow.lineWidth = max(10, lineWidth * 2.25)
        glow.lineCap = .round
        glow.lineJoin = .round
        glow.shadowColor = tracerPurple
        glow.shadowRadius = max(8, lineWidth * 0.8)
        glow.shadowOpacity = Float(0.88 * provenanceOpacity)
        container.addSublayer(glow)

        let stroke = CAShapeLayer()
        stroke.path = tracerPath
        stroke.fillColor = nil
        stroke.strokeColor = tracerPurple.copy(alpha: provenanceOpacity)
        stroke.lineWidth = lineWidth
        stroke.lineCap = .round
        stroke.lineJoin = .round
        container.addSublayer(stroke)

        animateStroke(glow, beginTime: beginTime, duration: duration)
        animateStroke(stroke, beginTime: beginTime, duration: duration)
    }

    private static func addFullFlightTimelineStroke(
        timeline: FullFlightRevealTimeline,
        sourceRangeStartTime: TimeInterval,
        renderSize: CGSize,
        to container: CALayer
    ) {
        let keyframes = timeline.strokeRevealKeyframes()
        let points = timeline.smoothedSamples.map(\.point)
        let tracerPath = path(from: points, in: renderSize)
        let beginTime = max(0, timeline.impactTime - sourceRangeStartTime)
        let duration = max(0.01, timeline.endTime - timeline.impactTime)
        let tracerPurple = CGColor(red: 0.57, green: 0.28, blue: 0.98, alpha: 1)
        let baseWidth = max(4, renderSize.width * 0.0048)

        func addSegment(_ range: FullFlightPathRange?, estimated: Bool) {
            guard let range, range.isDrawable else { return }
            let rangeLength = range.upperBound - range.lowerBound
            let provenanceOpacity: CGFloat = estimated ? 0.74 : 1
            let rangeValues = keyframes.strokeValues.map {
                min(range.upperBound, max(range.lowerBound, $0))
            }
            let rangeMidpoint = (range.lowerBound + range.upperBound) / 2
            let averageWidth = baseWidth * CGFloat(1 - (0.50 * pow(rangeMidpoint, 1.08)))

            let glow = CAShapeLayer()
            glow.path = tracerPath
            glow.fillColor = nil
            glow.strokeColor = tracerPurple.copy(alpha: 0.42 * provenanceOpacity)
            glow.lineWidth = averageWidth * 1.9
            glow.lineCap = .round
            glow.lineJoin = .round
            glow.shadowColor = tracerPurple
            glow.shadowRadius = max(8, averageWidth * 0.8)
            glow.shadowOpacity = Float(0.70 * provenanceOpacity)
            glow.strokeStart = CGFloat(range.lowerBound)
            container.addSublayer(glow)
            animateStroke(
                glow,
                beginTime: beginTime,
                duration: duration,
                keyTimes: keyframes.keyTimes,
                strokeValues: rangeValues
            )

            let sliceCount = max(1, Int(ceil(rangeLength * 40)))
            for index in 0..<sliceCount {
                let lower = range.lowerBound
                    + (rangeLength * Double(index) / Double(sliceCount))
                let upper = range.lowerBound
                    + (rangeLength * Double(index + 1) / Double(sliceCount))
                let midpoint = (lower + upper) / 2
                let lineWidth = baseWidth * CGFloat(1 - (0.50 * pow(midpoint, 1.08)))
                let values = keyframes.strokeValues.map {
                    min(upper, max(lower, $0))
                }
                let outlineWidth = lineWidth + max(2.4, renderSize.width * 0.0007)
                let layers: [(CAShapeLayer, CGColor, CGFloat)] = [
                    (CAShapeLayer(), CGColor(gray: 0.02, alpha: 0.34 * provenanceOpacity), outlineWidth),
                    (CAShapeLayer(), tracerPurple.copy(alpha: provenanceOpacity)!, lineWidth)
                ]
                for (layer, colour, width) in layers {
                    layer.path = tracerPath
                    layer.fillColor = nil
                    layer.strokeColor = colour
                    layer.lineWidth = width
                    layer.lineCap = .butt
                    layer.lineJoin = .round
                    layer.strokeStart = CGFloat(lower)
                    container.addSublayer(layer)
                    animateStroke(
                        layer,
                        beginTime: beginTime,
                        duration: duration,
                        keyTimes: keyframes.keyTimes,
                        strokeValues: values
                    )
                }
            }

            let highlight = CAShapeLayer()
            highlight.path = tracerPath
            highlight.fillColor = nil
            highlight.strokeColor = CGColor(gray: 1, alpha: 0.64 * provenanceOpacity)
            highlight.lineWidth = max(1, renderSize.width * 0.00024)
            highlight.lineCap = .round
            highlight.lineJoin = .round
            highlight.strokeStart = CGFloat(range.lowerBound)
            container.addSublayer(highlight)
            animateStroke(
                highlight,
                beginTime: beginTime,
                duration: duration,
                keyTimes: keyframes.keyTimes,
                strokeValues: rangeValues
            )
        }

        addSegment(timeline.launchRange, estimated: true)
        addSegment(timeline.observedRange, estimated: false)
        addSegment(timeline.continuationRange, estimated: true)
    }

    private static func addStaticTracerStroke(
        points: [NormalizedPoint],
        estimated: Bool,
        fadeInTime: TimeInterval,
        renderSize: CGSize,
        to container: CALayer
    ) {
        for layer in tracerLayers(points: points, estimated: estimated, renderSize: renderSize) {
            container.addSublayer(layer)
            fadeIn(layer, beginTime: fadeInTime)
        }
    }

    private static func tracerLayers(
        points: [NormalizedPoint],
        estimated: Bool,
        renderSize: CGSize
    ) -> [CAShapeLayer] {
        guard points.count >= 2 else { return [] }
        let tracerPurple = CGColor(red: 0.57, green: 0.28, blue: 0.98, alpha: 1)
        let provenanceOpacity: CGFloat = estimated ? 0.74 : 1
        let lineWidth = max(4, renderSize.width * 0.0048)
        let tracerPath = path(from: points, in: renderSize)

        let glow = CAShapeLayer()
        glow.path = tracerPath
        glow.fillColor = nil
        glow.strokeColor = tracerPurple.copy(alpha: 0.48 * provenanceOpacity)
        glow.lineWidth = max(10, lineWidth * 2.25)
        glow.lineCap = .round
        glow.lineJoin = .round
        glow.shadowColor = tracerPurple
        glow.shadowRadius = max(8, lineWidth * 0.8)
        glow.shadowOpacity = Float(0.88 * provenanceOpacity)

        let stroke = CAShapeLayer()
        stroke.path = tracerPath
        stroke.fillColor = nil
        stroke.strokeColor = tracerPurple.copy(alpha: provenanceOpacity)
        stroke.lineWidth = lineWidth
        stroke.lineCap = .round
        stroke.lineJoin = .round

        return [glow, stroke]
    }

    private static func addApexMarker(
        geometry: TracedVideoTracerGeometry,
        fullFlightTimeline: FullFlightRevealTimeline?,
        observedStartTime: TimeInterval,
        observedTrailLag: TimeInterval,
        sourceRangeStartTime: TimeInterval,
        renderSize: CGSize,
        to container: CALayer
    ) {
        guard let apex = geometry.apexPoint else { return }
        let hasEstimatedGeometry = !geometry.inferredLaunchConnector.isEmpty
            || !geometry.inferredContinuation.isEmpty
        let appearTime: TimeInterval
        if let fullFlightTimeline {
            guard let revealTime = fullFlightTimeline.revealTime(for: apex) else { return }
            appearTime = max(0, revealTime - sourceRangeStartTime)
        } else if let apexTime = geometry.timedObservedPath?.presentationTime(for: apex) {
            appearTime = max(
                observedStartTime + observedTrailLag,
                apexTime - sourceRangeStartTime + observedTrailLag
            )
        } else {
            appearTime = observedStartTime
        }
        let centre = point(from: apex, in: renderSize)
        let radius = max(9, renderSize.width * 0.0042)

        let marker = CAShapeLayer()
        marker.path = CGPath(
            ellipseIn: CGRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2),
            transform: nil
        )
        marker.fillColor = CGColor(red: 0.57, green: 0.28, blue: 0.98, alpha: 1)
        marker.strokeColor = CGColor(gray: 1, alpha: 0.96)
        marker.lineWidth = max(3, radius * 0.28)
        marker.shadowColor = CGColor(red: 0.57, green: 0.28, blue: 0.98, alpha: 1)
        marker.shadowRadius = radius
        marker.shadowOpacity = 0.9
        fadeIn(marker, beginTime: appearTime)
        container.addSublayer(marker)

        let labelWidth = max(92, renderSize.width * 0.05)
        let apexLabel = textBadge(
            hasEstimatedGeometry ? "EST. APEX" : "APEX",
            fontSize: max(15, min(28, renderSize.width * 0.0075)),
            frame: CGRect(
                x: min(renderSize.width - labelWidth - 12, centre.x + radius + 10),
                y: min(renderSize.height - 36, centre.y + radius + 4),
                width: labelWidth,
                height: 34
            )
        )
        fadeIn(apexLabel, beginTime: appearTime)
        container.addSublayer(apexLabel)
    }

    private static func addEstimatedLandingMarker(
        geometry: TracedVideoTracerGeometry,
        fullFlightTimeline: FullFlightRevealTimeline?,
        sourceRangeStartTime: TimeInterval,
        renderSize: CGSize,
        to container: CALayer
    ) {
        guard let landing = geometry.inferredContinuation.last,
              let fullFlightTimeline,
              fullFlightTimeline.revealsEstimatedLanding else {
            return
        }
        let appearTime = max(0, fullFlightTimeline.endTime - sourceRangeStartTime)
        let centre = point(from: landing, in: renderSize)
        let radius = max(8, renderSize.width * 0.0036)

        let marker = CAShapeLayer()
        marker.path = CGPath(
            ellipseIn: CGRect(
                x: centre.x - radius,
                y: centre.y - radius,
                width: radius * 2,
                height: radius * 2
            ),
            transform: nil
        )
        marker.fillColor = CGColor(red: 0.57, green: 0.28, blue: 0.98, alpha: 1)
        marker.strokeColor = CGColor(gray: 1, alpha: 0.96)
        marker.lineWidth = max(3, radius * 0.28)
        marker.shadowColor = CGColor(red: 0.57, green: 0.28, blue: 0.98, alpha: 1)
        marker.shadowRadius = radius
        marker.shadowOpacity = 0.8
        fadeIn(marker, beginTime: appearTime, duration: 0.08)
        container.addSublayer(marker)

        let labelWidth = max(130, renderSize.width * 0.072)
        let label = textBadge(
            "EST. LANDING",
            fontSize: max(15, min(28, renderSize.width * 0.0075)),
            frame: CGRect(
                x: min(renderSize.width - labelWidth - 12, centre.x + radius + 10),
                y: max(12, min(renderSize.height - 36, centre.y - radius - 38)),
                width: labelWidth,
                height: 34
            )
        )
        fadeIn(label, beginTime: appearTime, duration: 0.08)
        container.addSublayer(label)
    }

    private static func textBadge(
        _ text: String,
        fontSize: CGFloat,
        frame: CGRect
    ) -> CALayer {
        let badge = CALayer()
        badge.frame = frame
        badge.backgroundColor = CGColor(gray: 0.03, alpha: 0.68)
        badge.cornerRadius = max(8, frame.height * 0.22)

        let label = CALayer()
        label.contents = textImage(
            text,
            fontSize: fontSize,
            size: CGSize(width: frame.width - 20, height: frame.height - 8)
        )
        label.contentsGravity = .resizeAspect
        label.frame = CGRect(x: 10, y: 4, width: frame.width - 20, height: frame.height - 8)
        badge.addSublayer(label)
        badge.opacity = 0
        return badge
    }

    /// `CATextLayer` is not reliably rendered by `AVVideoCompositionCoreAnimationTool` across
    /// current iOS/macOS runtimes. Rasterising the small label with Core Text makes exported
    /// provenance and apex text deterministic without depending on a live UI process.
    private static func textImage(
        _ text: String,
        fontSize: CGFloat,
        size: CGSize
    ) -> CGImage? {
        let width = max(1, Int(size.width.rounded(.up)))
        let height = max(1, Int(size.height.rounded(.up)))
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        let font = CTFontCreateWithName("HelveticaNeue-Bold" as CFString, fontSize, nil)
        let attributed = NSAttributedString(
            string: text,
            attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 1, alpha: 0.98)
            ]
        )
        let line = CTLineCreateWithAttributedString(attributed)
        let bounds = CTLineGetBoundsWithOptions(line, [.useGlyphPathBounds])
        context.textPosition = CGPoint(
            x: max(0, (CGFloat(width) - bounds.width) / 2 - bounds.minX),
            y: max(0, (CGFloat(height) - bounds.height) / 2 - bounds.minY)
        )
        CTLineDraw(line, context)
        return context.makeImage()
    }

    private static func fadeIn(
        _ layer: CALayer,
        beginTime: TimeInterval,
        duration: TimeInterval = 0.16
    ) {
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.beginTime = AVCoreAnimationBeginTimeAtZero + beginTime
        fade.duration = duration
        fade.fillMode = .both
        fade.isRemovedOnCompletion = false
        layer.add(fade, forKey: "fadeIn")
    }

    private static func closestCommonFrameRate(to nominalRate: Double) -> Int32 {
        guard nominalRate.isFinite, nominalRate >= 1 else { return 30 }
        let supported = [24, 25, 30, 50, 60, 120, 240]
        return Int32(supported.min(by: {
            abs(Double($0) - nominalRate) < abs(Double($1) - nominalRate)
        }) ?? 30)
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

    private static func animateStroke(
        _ layer: CAShapeLayer,
        beginTime: TimeInterval,
        duration: TimeInterval,
        keyTimes: [Double]? = nil,
        strokeValues: [Double]? = nil
    ) {
        layer.strokeEnd = 0
        let animation: CAPropertyAnimation
        if let keyTimes,
           let strokeValues,
           keyTimes.count == strokeValues.count,
           keyTimes.count >= 2 {
            let keyframe = CAKeyframeAnimation(keyPath: "strokeEnd")
            keyframe.keyTimes = keyTimes.map { NSNumber(value: $0) }
            keyframe.values = strokeValues.map { NSNumber(value: $0) }
            keyframe.calculationMode = .linear
            animation = keyframe
        } else {
            let basic = CABasicAnimation(keyPath: "strokeEnd")
            basic.fromValue = 0
            basic.toValue = 1
            animation = basic
        }
        layer.strokeEnd = CGFloat(strokeValues?.first ?? 0)
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
