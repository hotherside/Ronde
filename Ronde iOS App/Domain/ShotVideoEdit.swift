import CoreGraphics
import Foundation

enum ShotVideoExportFormat: String, CaseIterable, Codable, Identifiable, Sendable {
    case original, portrait, square, landscape

    var id: String { rawValue }
    var title: String {
        switch self {
        case .original: "Original"
        case .portrait: "9:16 vertical"
        case .square: "1:1 square"
        case .landscape: "16:9 landscape"
        }
    }

    func aspectRatio(sourceAspectRatio: Double) -> Double {
        switch self {
        case .original: sourceAspectRatio.isFinite && sourceAspectRatio > 0 ? sourceAspectRatio : 16.0 / 9
        case .portrait: 9.0 / 16
        case .square: 1
        case .landscape: 16.0 / 9
        }
    }

    /// Even dimensions inside the Full HD envelope, retaining the requested canvas ratio.
    func renderSize(sourceAspectRatio: Double) -> CGSize {
        let ratio = aspectRatio(sourceAspectRatio: sourceAspectRatio)
        let bounds = ratio < 1 ? CGSize(width: 1080, height: 1920) : CGSize(width: 1920, height: 1080)
        let width = min(bounds.width, bounds.height * ratio)
        let height = width / ratio
        return CGSize(width: max(2, floor(width / 2) * 2), height: max(2, floor(height / 2) * 2))
    }
}

enum ShotVideoOverlayMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case original, automatic, seeded, manual
    var id: String { rawValue }
    var title: String {
        switch self {
        case .original: "Original"
        case .automatic: "Ball track"
        case .seeded: "Tracked ball"
        case .manual: "Manual trace"
        }
    }
}

/// Reversible presentation edits. Source media and detector timestamps are never rewritten.
struct ShotVideoEdit: Codable, Equatable, Sendable {
    var trimStart: TimeInterval
    var trimEnd: TimeInterval
    var format: ShotVideoExportFormat = .original
    var overlay: ShotVideoOverlayMode = .automatic
    var hiddenOverlay: ShotVideoOverlayMode? = nil

    mutating func setTraceVisible(_ visible: Bool, availableModes: [ShotVideoOverlayMode]) {
        if visible {
            overlay = hiddenOverlay.flatMap { availableModes.contains($0) ? $0 : nil }
                ?? availableModes.last(where: { $0 != .original }) ?? .original
        } else {
            if overlay != .original { hiddenOverlay = overlay }
            overlay = .original
        }
    }

    var duration: TimeInterval { max(0, trimEnd - trimStart) }
    var sourceRange: ReviewTimeRange { ReviewTimeRange(start: trimStart, duration: duration) }

    static func minimumDuration(for sourceDuration: TimeInterval) -> TimeInterval {
        min(0.5, max(0, sourceDuration))
    }

    func normalised(sourceDuration: TimeInterval) -> ShotVideoEdit {
        let end = sourceDuration.isFinite ? max(0, sourceDuration) : 0
        let minimum = Self.minimumDuration(for: end)
        var result = self
        result.trimStart = min(max(0, trimStart.isFinite ? trimStart : 0), max(0, end - minimum))
        result.trimEnd = min(end, max(result.trimStart + minimum, trimEnd.isFinite ? trimEnd : end))
        return result
    }

    static func fullSource(
        duration: TimeInterval,
        hasAutomaticTrace: Bool,
        hasManualTrace: Bool,
        hasSeededTrace: Bool = false
    ) -> ShotVideoEdit {
        ShotVideoEdit(
            trimStart: 0,
            trimEnd: max(0, duration),
            overlay: hasManualTrace ? .manual : hasSeededTrace ? .seeded : hasAutomaticTrace ? .automatic : .original
        )
    }
}

enum ShotVideoLayout {
    /// Shared by the player, export preview and encoder. No crop or coordinate stretching.
    static func fittedRect(sourceAspectRatio: Double, canvasSize: CGSize) -> CGRect {
        let ratio = sourceAspectRatio.isFinite && sourceAspectRatio > 0 ? sourceAspectRatio : 16.0 / 9
        let width = min(canvasSize.width, canvasSize.height * ratio)
        let height = width / ratio
        return CGRect(x: (canvasSize.width - width) / 2, y: (canvasSize.height - height) / 2, width: width, height: height)
    }

    static func point(_ point: NormalizedPoint, in sourceRect: CGRect) -> CGPoint {
        CGPoint(x: sourceRect.minX + point.x * sourceRect.width, y: sourceRect.minY + point.y * sourceRect.height)
    }

    static func adjacentFrame(to time: TimeInterval, direction: Int, presentationTimes: [TimeInterval]) -> TimeInterval? {
        if direction > 0 { return presentationTimes.first { $0 > time + 0.000_001 } }
        return presentationTimes.last { $0 < time - 0.000_001 }
    }

    static func nearestFrame(to time: TimeInterval, presentationTimes: [TimeInterval]) -> TimeInterval {
        guard !presentationTimes.isEmpty else { return time }
        var lower = 0
        var upper = presentationTimes.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if presentationTimes[middle] < time { lower = middle + 1 } else { upper = middle }
        }
        guard lower > 0 else { return presentationTimes[0] }
        guard lower < presentationTimes.count else { return presentationTimes[presentationTimes.count - 1] }
        return time - presentationTimes[lower - 1] <= presentationTimes[lower] - time ? presentationTimes[lower - 1] : presentationTimes[lower]
    }
}

/// The current studio intentionally offers observed samples or a separately authored annotation.
/// Full-flight extrapolation and carry are never copied into this render model.
struct ShotVideoTrace: Sendable, Equatable {
    let points: [NormalizedPoint]
    let presentationTimes: [TimeInterval]
    let isManual: Bool
    let isSeeded: Bool
    let seedWasDetected: Bool
    let impactTime: TimeInterval
    private let sourceSegments: [[TimedTrajectorySample]]

    init?(candidate: ReviewCandidate, mode: ShotVideoOverlayMode) {
        impactTime = candidate.impactTime
        seedWasDetected = mode == .seeded && candidate.seededTrace?.seedOrigin == .detectedBall
        switch mode {
        case .original:
            return nil
        case .automatic:
            guard let path = candidate.evidenceAnchoredPath,
                  path.observedPoints.count >= 3,
                  TimedTrajectoryPath(points: path.observedPoints, presentationTimes: path.observedPresentationTimes) != nil else { return nil }
            points = path.observedPoints
            presentationTimes = path.observedPresentationTimes
            isManual = false
            isSeeded = false
            sourceSegments = [zip(path.observedPoints, path.observedPresentationTimes).map {
                TimedTrajectorySample(point: $0.0, presentationTime: $0.1)
            }]
        case .seeded:
            guard let seeded = candidate.seededTrace,
                  seeded.observedSegments.contains(where: { $0.count >= 2 }) else { return nil }
            let segments = seeded.observedSegments
            points = segments.flatMap { $0.map(\.point) }
            presentationTimes = segments.flatMap { $0.map(\.presentationTime) }
            isManual = false
            isSeeded = true
            sourceSegments = segments
        case .manual:
            guard let manual = candidate.assistedTracer else { return nil }
            if let drawn = manual.drawnPoints, drawn.count >= 2 {
                points = drawn.map { NormalizedPoint(x: $0.x, y: $0.y) }
            } else {
                let geometry = TracedVideoTracerGeometry(
                    manualLaunch: NormalizedPoint(x: manual.launch.x, y: manual.launch.y),
                    apex: NormalizedPoint(x: manual.apex.x, y: manual.apex.y),
                    landing: NormalizedPoint(x: manual.landing.x, y: manual.landing.y)
                )
                points = geometry.observedPoints
            }
            presentationTimes = []
            isManual = true
            isSeeded = false
            sourceSegments = []
        }
    }

    var label: String {
        if isManual { return "Manual trace" }
        return isSeeded && !seedWasDetected ? "Tracked from selected ball point" : "Observed ball track"
    }

    /// Source-timed visible strokes. Seeded trace segments are deliberately independent: no
    /// interpolation, smoothing, or stroke can cross a missing source-frame observation.
    func visibleSegments(at sourceTime: TimeInterval) -> [[NormalizedPoint]] {
        if isManual { return sourceTime >= impactTime ? [points] : [] }
        if !isSeeded {
            let visible = visiblePoints(at: sourceTime)
            return visible.isEmpty ? [] : [visible]
        }
        return sourceSegments.compactMap { segment in
            guard let first = segment.first, sourceTime >= first.presentationTime else { return nil }
            guard segment.count >= 2 else { return [first.point] }
            let path = TimedTrajectoryPath(
                points: segment.map(\.point),
                presentationTimes: segment.map(\.presentationTime)
            )
            let visible = path?.visibleTrailSamples(at: sourceTime).map(\.point) ?? []
            return visible.isEmpty ? nil : visible
        }
    }

    func visiblePoints(at sourceTime: TimeInterval) -> [NormalizedPoint] {
        if isManual { return sourceTime >= impactTime ? points : [] }
        if isSeeded { return visibleSegments(at: sourceTime).flatMap { $0 } }
        return TimedTrajectoryPath(points: points, presentationTimes: presentationTimes)?
            .visibleTrailSamples(at: sourceTime).map(\.point) ?? []
    }
}
