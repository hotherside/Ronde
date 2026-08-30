@preconcurrency import AVFoundation
import Accelerate
import CoreGraphics
import CoreImage
import CoreML
import CoreVideo
import Foundation

struct WASBGolfBallTrackingConfiguration: Sendable, Equatable {
    var maximumPostImpactDuration: TimeInterval
    var minimumPeakConfidence: Double
    var maximumCandidatesPerFrame: Int
    /// Temporal spacing for accepted decoded frames. Sources slower than this are never
    /// interpolated: their real presentation timestamps remain authoritative.
    var analysisCadence: TimeInterval
    /// A full-frame scan is performed at this interval after acquisition to recover if a local
    /// search window loses the ball.
    var reacquisitionInterval: TimeInterval
    /// Optional normalised source-frame tile origins used by a signed local diagnostic probe.
    /// Production analysis leaves this nil and scans the source-resolution search area.
    var diagnosticTileOrigins: [NormalizedPoint]?

    init(
        maximumPostImpactDuration: TimeInterval,
        minimumPeakConfidence: Double,
        maximumCandidatesPerFrame: Int,
        diagnosticTileOrigins: [NormalizedPoint]? = nil,
        analysisCadence: TimeInterval = 1.0 / 30.0,
        reacquisitionInterval: TimeInterval = 0.28
    ) {
        self.maximumPostImpactDuration = min(4.0, max(0.2, maximumPostImpactDuration))
        self.minimumPeakConfidence = min(max(minimumPeakConfidence, 0), 1)
        self.maximumCandidatesPerFrame = max(1, maximumCandidatesPerFrame)
        self.diagnosticTileOrigins = diagnosticTileOrigins
        self.analysisCadence = max(1.0 / 120.0, analysisCadence)
        self.reacquisitionInterval = max(analysisCadence, reacquisitionInterval)
    }

    static let uploadedVideo = WASBGolfBallTrackingConfiguration(
        maximumPostImpactDuration: 4.0,
        minimumPeakConfidence: 0.08,
        maximumCandidatesPerFrame: 30
    )
}

/// A small top-left-origin luminance crop used by the launch evidence gate. Keeping this pure and
/// frame-format agnostic lets the detector be regression-tested without private video fixtures.
struct GolfBallLaunchLuminancePlane: Sendable, Equatable {
    let sourceWidth: Int
    let sourceHeight: Int
    let originX: Int
    let originY: Int
    let width: Int
    let height: Int
    let values: [Float]

    init(
        sourceWidth: Int,
        sourceHeight: Int,
        originX: Int = 0,
        originY: Int = 0,
        width: Int,
        height: Int,
        values: [Float]
    ) {
        self.sourceWidth = sourceWidth
        self.sourceHeight = sourceHeight
        self.originX = originX
        self.originY = originY
        self.width = width
        self.height = height
        self.values = values
    }

    subscript(x: Int, y: Int) -> Float {
        values[(y * width) + x]
    }
}

struct GolfBallLaunchAnchorDetection: Sendable, Equatable {
    let point: NormalizedPoint
    let confidence: Double
}

/// Looks for a compact bright object that is present beside the first accepted flight corridor at
/// impact and absent one source frame later. It does not extrapolate a launch point and returns nil
/// unless the disappearing candidate is both strong and locally unique.
struct GolfBallLaunchAnchorDetector: Sendable {
    func detect(
        before: GolfBallLaunchLuminancePlane,
        after: GolfBallLaunchLuminancePlane,
        firstObservedPoint: NormalizedPoint
    ) -> GolfBallLaunchAnchorDetection? {
        guard before.sourceWidth == after.sourceWidth,
              before.sourceHeight == after.sourceHeight,
              before.originX == after.originX,
              before.originY == after.originY,
              before.width == after.width,
              before.height == after.height,
              before.values.count == before.width * before.height,
              after.values.count == after.width * after.height,
              before.width >= 5,
              before.height >= 5 else {
            return nil
        }

        let integralWidth = before.width + 1
        var integral = [Double](repeating: 0, count: integralWidth * (before.height + 1))
        for y in 0..<before.height {
            var rowSum = 0.0
            for x in 0..<before.width {
                let initial = Double(before[x, y])
                let departed = Double(after[x, y])
                let difference = initial - departed
                let signal = initial >= 55 && difference >= 18 ? difference : 0
                rowSum += signal
                integral[((y + 1) * integralWidth) + x + 1]
                    = integral[(y * integralWidth) + x + 1] + rowSum
            }
        }

        func summedSignal(x0: Int, y0: Int, x1: Int, y1: Int) -> Double {
            integral[(y1 * integralWidth) + x1]
                - integral[(y0 * integralWidth) + x1]
                - integral[(y1 * integralWidth) + x0]
                + integral[(y0 * integralWidth) + x0]
        }

        struct Candidate {
            let score: Double
            let x: Int
            let y: Int
            let diameter: Int
        }

        let sourceShortSide = min(before.sourceWidth, before.sourceHeight)
        let minimumDiameter = max(5, Self.odd(Int((Double(sourceShortSide) * 0.006).rounded())))
        let maximumDiameter = max(minimumDiameter, Self.odd(Int((Double(sourceShortSide) * 0.018).rounded())))
        let scanStep = max(1, sourceShortSide / 540)
        var candidates: [Candidate] = []

        for diameter in stride(from: minimumDiameter, through: maximumDiameter, by: 2) {
            let radius = diameter / 2
            guard before.width > diameter, before.height > diameter else { continue }
            for y in stride(from: radius, to: before.height - radius, by: scanStep) {
                for x in stride(from: radius, to: before.width - radius, by: scanStep) {
                    let averageSignal = summedSignal(
                        x0: x - radius,
                        y0: y - radius,
                        x1: x + radius + 1,
                        y1: y + radius + 1
                    ) / Double(diameter * diameter)
                    guard averageSignal >= 2 else { continue }
                    let sourceX = Double(before.originX + x) / Double(before.sourceWidth)
                    let corridorDistance = abs(sourceX - firstObservedPoint.x)
                    let corridorWeight = 1 - min(0.35, corridorDistance / 0.07 * 0.35)
                    candidates.append(Candidate(
                        score: averageSignal * corridorWeight,
                        x: x,
                        y: y,
                        diameter: diameter
                    ))
                }
            }
        }

        let exclusionDistance = max(16, Int((Double(sourceShortSide) * 0.015).rounded()))
        var separated: [Candidate] = []
        for candidate in candidates.sorted(by: { $0.score > $1.score }) {
            guard separated.allSatisfy({
                hypot(Double(candidate.x - $0.x), Double(candidate.y - $0.y))
                    > Double(exclusionDistance)
            }) else { continue }
            separated.append(candidate)
            if separated.count == 2 { break }
        }
        guard let best = separated.first,
              best.score >= 5.5 else {
            return nil
        }
        if let runnerUp = separated.dropFirst().first {
            // A club head can leave a second compact difference immediately below the ball. The
            // ball must still win by a material absolute and relative margin, but demanding a
            // near two-to-one gap rejects clean impact frames where both objects depart together.
            guard best.score - runnerUp.score >= 4.5,
                  best.score >= runnerUp.score * 1.30 else {
                return nil
            }
        }

        let radius = best.diameter / 2
        var weightSum = 0.0
        var weightedX = 0.0
        var weightedY = 0.0
        for y in max(0, best.y - radius)...min(before.height - 1, best.y + radius) {
            for x in max(0, best.x - radius)...min(before.width - 1, best.x + radius) {
                let initial = Double(before[x, y])
                let difference = initial - Double(after[x, y])
                let weight = initial >= 55 && difference >= 18 ? difference : 0
                weightSum += weight
                weightedX += Double(x) * weight
                weightedY += Double(y) * weight
            }
        }
        guard weightSum > 0 else { return nil }
        let refinedX = weightedX / weightSum
        let refinedY = weightedY / weightSum
        let point = NormalizedPoint(
            x: Double(before.originX) / Double(before.sourceWidth)
                + (refinedX / Double(before.sourceWidth)),
            y: Double(before.originY) / Double(before.sourceHeight)
                + (refinedY / Double(before.sourceHeight))
        )
        guard abs(point.x - firstObservedPoint.x) <= 0.07,
              point.y >= firstObservedPoint.y + 0.06,
              point.y <= 0.94 else {
            return nil
        }

        let runnerUpScore = separated.dropFirst().first?.score ?? 0
        let strength = min(1, max(0, (best.score - 5.5) / 12))
        let separation = min(1, max(0, (best.score - runnerUpScore - 4.5) / 10))
        return GolfBallLaunchAnchorDetection(
            point: point,
            confidence: 0.55 + (0.25 * strength) + (0.20 * separation)
        )
    }

    private static func odd(_ value: Int) -> Int {
        value.isMultiple(of: 2) ? value + 1 : value
    }
}

/// Pure timestamp-based state for local continuation after competitive acquisition. It retains
/// the last three linked observations for prediction and stops after a sustained miss rather than
/// scanning a whole upload forever.
struct TrackingContinuationGate: Sendable, Equatable {
    private static let maximumObservationGap: TimeInterval = 0.115
    private static let maximumMissDuration: TimeInterval = 0.4
    private static let maximumInitialSearchDuration: TimeInterval = 0.9

    private(set) var observations: [GolfBallDetectionCandidate] = []

    var lastObservation: GolfBallDetectionCandidate? {
        observations.last
    }

    var isAcquired: Bool {
        observations.count >= 3
    }

    mutating func acceptBest(
        from candidates: [GolfBallDetectionCandidate],
        at time: TimeInterval
    ) -> GolfBallDetectionCandidate? {
        guard !candidates.isEmpty else { return nil }

        let prediction = lastObservation.map {
            predictedCentre(at: time, fallingBackTo: $0.point)
        }
        let ranked = candidates.sorted {
            score($0, around: prediction) > score($1, around: prediction)
        }
        guard let selected = ranked.first(where: { canLink($0) }) else {
            // Before acquisition there is no defensible motion history. Re-anchor to the best
            // local observation and keep searching, but never call it a linked track.
            if !isAcquired, let anchor = ranked.first {
                observations = [anchor]
                return anchor
            }
            return nil
        }
        observations.append(selected)
        if observations.count > 3 { observations.removeFirst() }
        return selected
    }

    mutating func reset() {
        observations.removeAll(keepingCapacity: true)
    }

    mutating func seed(with linkedObservations: [GolfBallDetectionCandidate]) {
        observations = Array(linkedObservations.suffix(3))
    }

    func shouldStopAfterMisses(at time: TimeInterval) -> Bool {
        guard isAcquired, let lastObservation else { return false }
        return time - lastObservation.presentationTime >= Self.maximumMissDuration
    }

    func shouldAbandonInitialSearch(startedAt: TimeInterval, at time: TimeInterval) -> Bool {
        !isAcquired && time - startedAt + 1e-9 >= Self.maximumInitialSearchDuration
    }

    func predictedCentre(
        at time: TimeInterval,
        fallingBackTo fallback: NormalizedPoint
    ) -> NormalizedPoint {
        guard observations.count >= 2,
              let previous = observations.dropLast().last,
              let last = observations.last else {
            return fallback
        }
        let previousElapsed = last.presentationTime - previous.presentationTime
        let projectedElapsed = max(0, time - last.presentationTime)
        guard previousElapsed > 0, projectedElapsed <= Self.maximumMissDuration else { return fallback }
        return NormalizedPoint(
            x: last.point.x + ((last.point.x - previous.point.x) / previousElapsed * projectedElapsed),
            y: last.point.y + ((last.point.y - previous.point.y) / previousElapsed * projectedElapsed)
        )
    }

    private func canLink(_ candidate: GolfBallDetectionCandidate) -> Bool {
        guard let last = observations.last else { return true }
        let elapsed = candidate.presentationTime - last.presentationTime
        guard elapsed > 0, elapsed <= Self.maximumObservationGap else { return false }
        let velocity = vector(from: last.point, to: candidate.point, dividedBy: elapsed)
        let speed = hypot(velocity.x, velocity.y)
        guard speed >= 0.008, speed <= 2.4 else { return false }

        guard observations.count >= 2,
              let previous = observations.dropLast().last else {
            return true
        }
        let previousElapsed = last.presentationTime - previous.presentationTime
        guard previousElapsed > 0 else { return false }
        let previousVelocity = vector(from: previous.point, to: last.point, dividedBy: previousElapsed)
        let previousSpeed = hypot(previousVelocity.x, previousVelocity.y)
        guard previousSpeed > 0 else { return false }
        let cosine = ((previousVelocity.x * velocity.x) + (previousVelocity.y * velocity.y))
            / (previousSpeed * speed)
        guard cosine >= 0.45 else { return false }
        let predicted = NormalizedPoint(
            x: last.point.x + (previousVelocity.x * elapsed),
            y: last.point.y + (previousVelocity.y * elapsed)
        )
        let predictionError = hypot(candidate.point.x - predicted.x, candidate.point.y - predicted.y)
        return predictionError <= max(0.006, (previousSpeed * elapsed * 1.7) + 0.008)
    }

    private func score(_ candidate: GolfBallDetectionCandidate, around prediction: NormalizedPoint?) -> Double {
        guard let prediction else { return candidate.confidence }
        return candidate.confidence - (hypot(
            candidate.point.x - prediction.x,
            candidate.point.y - prediction.y
        ) * 0.35)
    }

    private func vector(
        from start: NormalizedPoint,
        to end: NormalizedPoint,
        dividedBy divisor: Double
    ) -> (x: Double, y: Double) {
        ((end.x - start.x) / divisor, (end.y - start.y) / divisor)
    }
}

/// Holds full-frame candidates until a sufficiently supported post-impact path can own the local
/// search window. Final display is also gated on this commitment, so a shorter coherent speck
/// cannot become a tracer merely because the initial search timed out.
struct CompetitiveTrackAcquisitionGate: Sendable, Equatable {
    private static let competitionDuration: TimeInterval = 0.65
    private static let minimumDetectionCount = 8

    private let impactTime: TimeInterval
    private var candidates: [GolfBallDetectionCandidate] = []
    private(set) var committedTrack: GolfBallTrack?

    init(impactTime: TimeInterval) {
        self.impactTime = impactTime
    }

    var hasCommittedTrack: Bool {
        committedTrack != nil
    }

    mutating func record(
        _ detections: [GolfBallDetectionCandidate],
        at time: TimeInterval
    ) -> GolfBallTrack? {
        if let committedTrack { return committedTrack }
        candidates.append(contentsOf: detections)
        guard time >= impactTime + Self.competitionDuration,
              let track = GolfBallTrackSelector.select(
                  from: candidates,
                  impactTime: impactTime,
                  minimumDetectionCount: Self.minimumDetectionCount
              ) else {
            return nil
        }
        committedTrack = track
        return track
    }
}

/// Aggregate local processing information. The callback does not receive media URLs, frames,
/// coordinates or model scores, so it can support on-device diagnostics without exposing footage.
struct WASBGolfBallTrackingMetrics: Sendable, Equatable {
    /// Presentation-time span decoded inside the requested post-impact window.
    let analysedDuration: TimeInterval
    let sourceSamplesDecoded: Int
    let sourceSamplesSkippedForCadence: Int
    let sampledFrameCount: Int
    let modelWindowCount: Int
    /// The tracker allocates exactly one reusable 9-channel input buffer for each analysed
    /// three-frame model window, rather than one for every tile inference.
    let inputBufferAllocationCount: Int
    let tilesEvaluated: Int
    let acquisitionSearchCount: Int
    let localSearchCount: Int
    let reacquisitionSearchCount: Int
    let candidateCount: Int
    let selectedTrackPointCount: Int

    /// Full-frame passes, including initial acquisition and periodic reacquisition.
    var fullFrameSearchCount: Int {
        acquisitionSearchCount + reacquisitionSearchCount
    }

    /// One Core ML prediction is made for each evaluated tile.
    var tileInferenceCount: Int {
        tilesEvaluated
    }

    init(
        analysedDuration: TimeInterval = 0,
        sourceSamplesDecoded: Int = 0,
        sourceSamplesSkippedForCadence: Int = 0,
        sampledFrameCount: Int = 0,
        modelWindowCount: Int = 0,
        inputBufferAllocationCount: Int = 0,
        tilesEvaluated: Int = 0,
        acquisitionSearchCount: Int = 0,
        localSearchCount: Int = 0,
        reacquisitionSearchCount: Int = 0,
        candidateCount: Int = 0,
        selectedTrackPointCount: Int = 0
    ) {
        self.analysedDuration = max(0, analysedDuration)
        self.sourceSamplesDecoded = sourceSamplesDecoded
        self.sourceSamplesSkippedForCadence = sourceSamplesSkippedForCadence
        self.sampledFrameCount = sampledFrameCount
        self.modelWindowCount = modelWindowCount
        self.inputBufferAllocationCount = inputBufferAllocationCount
        self.tilesEvaluated = tilesEvaluated
        self.acquisitionSearchCount = acquisitionSearchCount
        self.localSearchCount = localSearchCount
        self.reacquisitionSearchCount = reacquisitionSearchCount
        self.candidateCount = candidateCount
        self.selectedTrackPointCount = selectedTrackPointCount
    }
}

enum WASBGolfBallTrackingError: LocalizedError, Sendable, Equatable {
    case unreadableAsset
    case noVideoTrack
    case unsupportedFrameSize
    case modelUnavailable
    case modelFailed(String)
    case readerFailed(String)
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
        case let .readerFailed(message):
            "Ball-flight decoding failed: \(message)"
        case .noDefensibleBallTrack:
            "The ball was not tracked reliably enough to draw a tracer."
        }
    }
}

/// Offline golf-ball tracking built on the MIT-licensed WASB-SBDT sports-ball model.
///
/// Source samples are decoded sequentially and selected by their presentation timestamps. Three
/// oriented source frames near a stable temporal cadence are evaluated in overlapping 512 x 288
/// tiles. Model peaks are only observations; `GolfBallTrackSelector` must link them into a
/// directionally stable post-impact track before this service returns displayable geometry.
actor WASBGolfBallTrackingService {
    private static let modelWidth = 512
    private static let modelHeight = 288
    private static let horizontalStep = 448
    private static let verticalStep = 224

    private var loadedModel: MLModel?
    private let diagnosticModelURL: URL?
    private let imageContext = CIContext()

    init(diagnosticModelURL: URL? = nil) {
        self.diagnosticModelURL = diagnosticModelURL
    }

    func analyse(
        url: URL,
        impactTime: TimeInterval,
        configuration: WASBGolfBallTrackingConfiguration = .uploadedVideo,
        progress: (@Sendable (Double) -> Void)? = nil,
        instrumentation: (@Sendable (WASBGolfBallTrackingMetrics) -> Void)? = nil
    ) async throws -> BallFlightEstimate {
        let asset = AVURLAsset(url: url)
        guard try await asset.load(.isReadable) else {
            throw WASBGolfBallTrackingError.unreadableAsset
        }
        let duration = max(0, CMTimeGetSeconds(try await asset.load(.duration)))
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw WASBGolfBallTrackingError.noVideoTrack
        }

        let cadence = configuration.analysisCadence
        let startTime = min(duration, max(0, impactTime + 0.04 - (2 * cadence)))
        let endTime = min(duration, impactTime + configuration.maximumPostImpactDuration)
        guard endTime - startTime >= max(cadence * 4, 0.16) else {
            throw WASBGolfBallTrackingError.noDefensibleBallTrack
        }

        let model = try loadModel()
        let preferredTransform = try await track.load(.preferredTransform)
        let reader = try AVAssetReader(asset: asset)
        reader.timeRange = CMTimeRange(
            start: CMTime(seconds: startTime, preferredTimescale: 60_000),
            end: CMTime(seconds: endTime, preferredTimescale: 60_000)
        )
        let output = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        )
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else {
            throw WASBGolfBallTrackingError.unreadableAsset
        }
        reader.add(output)
        guard reader.startReading() else {
            throw WASBGolfBallTrackingError.readerFailed(
                reader.error?.localizedDescription ?? "The reader could not start."
            )
        }

        var sourceSamplesDecoded = 0
        var sourceSamplesSkippedForCadence = 0
        var sampledFrameCount = 0
        var modelWindowCount = 0
        var inputBufferAllocationCount = 0
        var tilesEvaluated = 0
        var acquisitionSearchCount = 0
        var localSearchCount = 0
        var reacquisitionSearchCount = 0
        var candidateCount = 0
        var selectedTrackPointCount = 0
        var lastDecodedPresentationTime = startTime
        defer {
            instrumentation?(WASBGolfBallTrackingMetrics(
                analysedDuration: lastDecodedPresentationTime - startTime,
                sourceSamplesDecoded: sourceSamplesDecoded,
                sourceSamplesSkippedForCadence: sourceSamplesSkippedForCadence,
                sampledFrameCount: sampledFrameCount,
                modelWindowCount: modelWindowCount,
                inputBufferAllocationCount: inputBufferAllocationCount,
                tilesEvaluated: tilesEvaluated,
                acquisitionSearchCount: acquisitionSearchCount,
                localSearchCount: localSearchCount,
                reacquisitionSearchCount: reacquisitionSearchCount,
                candidateCount: candidateCount,
                selectedTrackPointCount: selectedTrackPointCount
            ))
        }

        var sampler = PresentationTimestampFrameSampler(startTime: startTime, cadence: cadence)
        var frameWindow: [RGBFrame] = []
        var launchEvidenceFrames: [(time: TimeInterval, frame: RGBFrame)] = []
        var detections: [GolfBallDetectionCandidate] = []
        var frameIndex = 0
        var searchState = SearchState(
            analysisStartTime: startTime,
            impactTime: impactTime,
            reacquisitionInterval: configuration.reacquisitionInterval
        )

        while let sampleBuffer = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            sourceSamplesDecoded += 1

            let sampleTime = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
            guard sampleTime.isFinite, sampleTime >= startTime else { continue }
            guard sampleTime <= endTime else { break }
            lastDecodedPresentationTime = sampleTime
            guard sampler.accepts(presentationTime: sampleTime) else {
                sourceSamplesSkippedForCadence += 1
                continue
            }
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                continue
            }

            let frame = try RGBFrame(
                pixelBuffer: pixelBuffer,
                preferredTransform: preferredTransform,
                imageContext: imageContext
            )
            sampledFrameCount += 1
            frameWindow.append(frame)
            if frameWindow.count > 3 { frameWindow.removeFirst() }
            if sampleTime >= impactTime - 0.075,
               sampleTime <= impactTime + 0.11 {
                launchEvidenceFrames.append((time: sampleTime, frame: frame))
            }

            if frameWindow.count == 3 {
                let searchPlan = searchState.plan(at: sampleTime)
                if searchPlan.shouldEvaluate {
                    switch searchPlan.kind {
                    case .acquisition: acquisitionSearchCount += 1
                    case .tracking: localSearchCount += 1
                    case .reacquisition: reacquisitionSearchCount += 1
                    }
                    let batch = try detectCandidates(
                        in: frameWindow,
                        frameIndex: frameIndex,
                        presentationTime: sampleTime,
                        searchPlan: searchPlan,
                        model: model,
                        configuration: configuration,
                        onTileEvaluated: { completedTiles, totalTiles in
                            guard totalTiles > 0 else { return }
                            // A 4K full-frame window may have dozens of tiles. Advance within
                            // that window so the review surface does not appear frozen while the
                            // synchronous Core ML work is in progress. This remains based on
                            // source presentation time and cannot run ahead of the current sample.
                            let previousSampleTime = max(startTime, sampleTime - cadence)
                            let previousProgress = (previousSampleTime - startTime)
                                / max(0.001, endTime - startTime)
                            let currentProgress = (sampleTime - startTime)
                                / max(0.001, endTime - startTime)
                            let tileProgress = Double(completedTiles) / Double(totalTiles)
                            progress?(min(1, max(0, previousProgress + (
                                (currentProgress - previousProgress) * tileProgress
                            ))))
                        }
                    )
                    modelWindowCount += 1
                    inputBufferAllocationCount += batch.inputBufferAllocationCount
                    tilesEvaluated += batch.tileCount
                    candidateCount += batch.detections.count
                    detections.append(contentsOf: batch.detections)
                    searchState.record(batch.detections, from: searchPlan, at: sampleTime)
                }
                if searchState.shouldTerminate(at: sampleTime) {
                    break
                }
            }

            frameIndex += 1
            progress?(min(1, max(0, (sampleTime - startTime) / max(0.001, endTime - startTime))))
        }

        if reader.status == .failed {
            throw WASBGolfBallTrackingError.readerFailed(
                reader.error?.localizedDescription ?? "The reader failed while decoding."
            )
        }
        progress?(1)

        guard searchState.hasCommittedTrack else {
            throw WASBGolfBallTrackingError.noDefensibleBallTrack
        }

        guard let selectedTrack = GolfBallTrackSelector.select(
            from: detections,
            impactTime: impactTime
        ) else {
            throw WASBGolfBallTrackingError.noDefensibleBallTrack
        }
        selectedTrackPointCount = selectedTrack.detections.count
        let launchAnchor = try? Self.detectLaunchAnchor(
            in: launchEvidenceFrames,
            impactTime: impactTime,
            firstObservedPoint: selectedTrack.detections[0].point
        )
        return Self.estimate(from: selectedTrack, launchAnchor: launchAnchor)
    }

    private func loadModel() throws -> MLModel {
        if let loadedModel { return loadedModel }
        guard let url = diagnosticModelURL
            ?? Bundle.main.url(forResource: "GolfBallTracker", withExtension: "mlmodelc") else {
            throw WASBGolfBallTrackingError.modelUnavailable
        }
        do {
            let configuration = MLModelConfiguration()
#if targetEnvironment(simulator)
            // This converted Espresso model currently fails through the Simulator's MPSGraph
            // backend on Xcode 26.5. CPU execution preserves the exact decoder, model and
            // association code for local regression work; physical iPhones retain all units.
            configuration.computeUnits = .cpuOnly
#else
            configuration.computeUnits = .all
#endif
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
        searchPlan: SearchPlan,
        model: MLModel,
        configuration: WASBGolfBallTrackingConfiguration,
        onTileEvaluated: ((Int, Int) -> Void)? = nil
    ) throws -> CandidateBatch {
        guard frames.count == 3,
              let current = frames.last,
              frames.allSatisfy({ $0.width == current.width && $0.height == current.height }),
              current.width >= Self.modelWidth,
              current.height >= Self.modelHeight else {
            throw WASBGolfBallTrackingError.unsupportedFrameSize
        }

        let tileOrigins: [(x: Int, y: Int)]
        if let diagnosticOrigins = configuration.diagnosticTileOrigins {
            tileOrigins = diagnosticOrigins.map {
                (
                    x: min(current.width - Self.modelWidth, Int($0.x * Double(current.width))),
                    y: min(current.height - Self.modelHeight, Int($0.y * Double(current.height)))
                )
            }
        } else {
            tileOrigins = Self.tileOrigins(
                width: current.width,
                height: current.height,
                region: searchPlan.normalizedRegion
            )
        }
        var peaks: [PixelPeak] = []
        peaks.reserveCapacity(tileOrigins.count)
        // The model input is 5.3 MB (512 * 288 * 9 Float32 values). Reusing one buffer for the
        // entire three-frame window keeps its allocation independent of source resolution and
        // tile count. `writeInput` fills every channel on every tile before prediction.
        let input = try Self.makeInputBuffer()
        let progressNotificationStride = max(1, (tileOrigins.count + 3) / 4)

        for (index, origin) in tileOrigins.enumerated() {
            try Task.checkCancellation()
            try Self.writeInput(
                frames: frames,
                to: input,
                xOrigin: origin.x,
                yOrigin: origin.y
            )

            // MLFeatureValue, MLDictionaryFeatureProvider and MLFeatureProvider are ObjC-backed.
            // Core ML may autorelease a substantial temporary graph for each prediction, so keep
            // only the scalar peak beyond this scope and drain it before moving to the next tile.
            let peak: PixelPeak? = try autoreleasepool {
                let features = try MLDictionaryFeatureProvider(dictionary: [
                    "input_frames": MLFeatureValue(multiArray: input)
                ])
                let prediction = try model.prediction(from: features)
                guard let heatmap = prediction.featureValue(for: "heatmap")?.multiArrayValue,
                      let heatmapPeak = Self.peak(in: heatmap),
                      heatmapPeak.confidence >= configuration.minimumPeakConfidence else {
                    return nil
                }
                return PixelPeak(
                    x: origin.x + heatmapPeak.x,
                    y: origin.y + heatmapPeak.y,
                    confidence: heatmapPeak.confidence
                )
            }
            if let peak { peaks.append(peak) }

            // Report roughly four times per tiled window, avoiding a flood of main-actor work
            // on 4K full-frame scans.
            // Cancellation remains checked for every prediction above.
            let completedTiles = index + 1
            if completedTiles.isMultiple(of: progressNotificationStride)
                || completedTiles == tileOrigins.count {
                onTileEvaluated?(completedTiles, tileOrigins.count)
            }
        }

        var retained: [PixelPeak] = []
        for peak in peaks.sorted(by: { $0.confidence > $1.confidence }) {
            guard retained.allSatisfy({ hypot(Double(peak.x - $0.x), Double(peak.y - $0.y)) > 16 }) else {
                continue
            }
            retained.append(peak)
            if retained.count == configuration.maximumCandidatesPerFrame { break }
        }

        return CandidateBatch(
            detections: retained.map { peak in
                GolfBallDetectionCandidate(
                    frameIndex: frameIndex,
                    presentationTime: presentationTime,
                    point: NormalizedPoint(
                        x: Double(peak.x) / Double(current.width),
                        y: Double(peak.y) / Double(current.height)
                    ),
                    confidence: peak.confidence
                )
            },
            tileCount: tileOrigins.count,
            inputBufferAllocationCount: 1
        )
    }

    private static func makeInputBuffer() throws -> MLMultiArray {
        try MLMultiArray(
            shape: [1, 9, NSNumber(value: modelHeight), NSNumber(value: modelWidth)],
            dataType: .float32
        )
    }

    private static func writeInput(
        frames: [RGBFrame],
        to array: MLMultiArray,
        xOrigin: Int,
        yOrigin: Int
    ) throws {
        let pointer = array.dataPointer.bindMemory(to: Float32.self, capacity: array.count)
        let channelStride = array.strides[1].intValue
        let rowStride = array.strides[2].intValue
        let columnStride = array.strides[3].intValue

        for (frameOffset, frame) in frames.enumerated() {
            try frame.writeRGBTile(
                to: pointer,
                frameOffset: frameOffset,
                channelStride: channelStride,
                rowStride: rowStride,
                columnStride: columnStride,
                xOrigin: xOrigin,
                yOrigin: yOrigin
            )
        }
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

    private static func tileOrigins(width: Int, height: Int, region: CGRect?) -> [(x: Int, y: Int)] {
        let xOrigins: [Int]
        let yOrigins: [Int]
        if let region {
            xOrigins = localTileOrigins(
                length: width,
                tileLength: modelWidth,
                step: horizontalStep,
                lowerBound: region.minX,
                upperBound: region.maxX
            )
            yOrigins = localTileOrigins(
                length: height,
                tileLength: modelHeight,
                step: verticalStep,
                lowerBound: region.minY,
                upperBound: region.maxY
            )
        } else {
            xOrigins = tileOrigins(length: width, tileLength: modelWidth, step: horizontalStep)
            yOrigins = tileOrigins(length: height, tileLength: modelHeight, step: verticalStep)
        }
        return yOrigins.flatMap { y in xOrigins.map { x in (x: x, y: y) } }
    }

    private static func localTileOrigins(
        length: Int,
        tileLength: Int,
        step: Int,
        lowerBound: CGFloat,
        upperBound: CGFloat
    ) -> [Int] {
        let maximumOrigin = max(0, length - tileLength)
        let paddedLower = max(0, Int(lowerBound * CGFloat(length)) - tileLength)
        let paddedUpper = min(maximumOrigin, Int(upperBound * CGFloat(length)))
        let lower = min(paddedLower, paddedUpper)
        var values = Array(stride(from: lower, through: paddedUpper, by: step))
        if values.last != paddedUpper { values.append(paddedUpper) }
        return values
    }

    private static func tileOrigins(length: Int, tileLength: Int, step: Int) -> [Int] {
        guard length >= tileLength else { return [] }
        var values = Array(stride(from: 0, through: length - tileLength, by: step))
        let last = length - tileLength
        if values.last != last { values.append(last) }
        return values
    }

    private static func detectLaunchAnchor(
        in frames: [(time: TimeInterval, frame: RGBFrame)],
        impactTime: TimeInterval,
        firstObservedPoint: NormalizedPoint
    ) throws -> NormalizedPoint? {
        let beforeFrames = frames.filter { $0.time <= impactTime + 0.02 }
        let afterFrames = frames.filter { $0.time >= impactTime + 0.02 }
        guard !beforeFrames.isEmpty, !afterFrames.isEmpty else { return nil }

        var strongest: GolfBallLaunchAnchorDetection?
        for before in beforeFrames {
            for after in afterFrames {
                let elapsed = after.time - before.time
                guard elapsed >= 0.02, elapsed <= 0.095,
                      before.frame.width == after.frame.width,
                      before.frame.height == after.frame.height else {
                    continue
                }
                let searchRegion = CGRect(
                    x: max(0, firstObservedPoint.x - 0.07),
                    y: min(0.92, firstObservedPoint.y + 0.06),
                    width: min(1, firstObservedPoint.x + 0.07)
                        - max(0, firstObservedPoint.x - 0.07),
                    height: max(
                        0,
                        min(0.94, firstObservedPoint.y + 0.72)
                            - min(0.92, firstObservedPoint.y + 0.06)
                    )
                )
                guard searchRegion.width > 0.01, searchRegion.height > 0.01 else { continue }
                let initial = try before.frame.luminancePlane(in: searchRegion)
                let departed = try after.frame.luminancePlane(in: searchRegion)
                guard let detection = GolfBallLaunchAnchorDetector().detect(
                    before: initial,
                    after: departed,
                    firstObservedPoint: firstObservedPoint
                ) else { continue }
                if strongest.map({ detection.confidence > $0.confidence }) ?? true {
                    strongest = detection
                }
            }
        }
        return strongest?.point
    }

    private static func estimate(
        from track: GolfBallTrack,
        launchAnchor: NormalizedPoint?
    ) -> BallFlightEstimate {
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
            observedLaunchAnchor: launchAnchor,
            source: .observed,
            confidence: track.confidence,
            observedPointCount: points.count,
            observedTrajectory: trajectory
        )
    }

    private struct CandidateBatch {
        let detections: [GolfBallDetectionCandidate]
        let tileCount: Int
        let inputBufferAllocationCount: Int
    }

    private enum SearchKind: Equatable {
        case acquisition
        case tracking
        case reacquisition
    }

    private struct SearchPlan {
        let kind: SearchKind
        /// nil is an intentional full-frame scan, including the lower third of the source frame.
        let normalizedRegion: CGRect?
        let shouldEvaluate: Bool
    }

    private struct SearchState {
        private let analysisStartTime: TimeInterval
        private let reacquisitionInterval: TimeInterval
        private var continuation = TrackingContinuationGate()
        private var acquisition: CompetitiveTrackAcquisitionGate
        private var acquisitionPlanCount = 0
        private var lastFullSearchTime: TimeInterval?

        init(
            analysisStartTime: TimeInterval,
            impactTime: TimeInterval,
            reacquisitionInterval: TimeInterval
        ) {
            self.analysisStartTime = analysisStartTime
            self.reacquisitionInterval = reacquisitionInterval
            acquisition = CompetitiveTrackAcquisitionGate(impactTime: impactTime)
        }

        var hasCommittedTrack: Bool {
            acquisition.hasCommittedTrack
        }

        mutating func plan(at time: TimeInterval) -> SearchPlan {
            guard acquisition.hasCommittedTrack else {
                lastFullSearchTime = time
                defer { acquisitionPlanCount += 1 }
                return SearchPlan(
                    kind: .acquisition,
                    normalizedRegion: nil,
                    shouldEvaluate: acquisitionPlanCount.isMultiple(of: 2)
                )
            }
            guard let lastPeak = continuation.lastObservation else {
                lastFullSearchTime = time
                return SearchPlan(kind: .acquisition, normalizedRegion: nil, shouldEvaluate: true)
            }
            if let lastFullSearchTime, time - lastFullSearchTime >= reacquisitionInterval {
                self.lastFullSearchTime = time
                return SearchPlan(kind: .reacquisition, normalizedRegion: nil, shouldEvaluate: true)
            }

            let centre = predictedCentre(at: time, fallingBackTo: lastPeak.point)
            let region = CGRect(
                x: max(0, centre.x - 0.19),
                y: max(0, centre.y - 0.20),
                width: min(1, centre.x + 0.19) - max(0, centre.x - 0.19),
                height: min(1, centre.y + 0.20) - max(0, centre.y - 0.20)
            )
            return SearchPlan(kind: .tracking, normalizedRegion: region, shouldEvaluate: true)
        }

        mutating func record(
            _ detections: [GolfBallDetectionCandidate],
            from plan: SearchPlan,
            at time: TimeInterval
        ) {
            if !acquisition.hasCommittedTrack {
                if let track = acquisition.record(detections, at: time) {
                    continuation.seed(with: track.detections)
                    lastFullSearchTime = time
                }
                return
            }

            guard !detections.isEmpty else {
                if !continuation.isAcquired, plan.kind != .tracking {
                    continuation.reset()
                }
                return
            }
            _ = continuation.acceptBest(from: detections, at: time)
        }

        func shouldTerminate(at time: TimeInterval) -> Bool {
            guard acquisition.hasCommittedTrack else {
                return continuation.shouldAbandonInitialSearch(
                    startedAt: analysisStartTime,
                    at: time
                )
            }
            if continuation.shouldStopAfterMisses(at: time) {
                return true
            }
            return false
        }

        private func predictedCentre(at time: TimeInterval, fallingBackTo fallback: NormalizedPoint) -> NormalizedPoint {
            continuation.predictedCentre(at: time, fallingBackTo: fallback)
        }
    }

    private struct PixelPeak {
        let x: Int
        let y: Int
        let confidence: Double
    }

    private struct RGBFrame {
        let width: Int
        let height: Int
        private let storage: Storage

        private enum Storage {
            /// AVAssetReader's BGRA frames can be sampled directly tile-by-tile when no display
            /// orientation transform is required. Retaining the pixel buffer avoids a full-frame
            /// RGBA copy for the common landscape source path.
            case bgraPixelBuffer(CVPixelBuffer)
            /// Transformed portrait/mirrored frames require an oriented render. They remain a
            /// compatibility path while direct source-frame inference stays the hot path.
            case rgba([UInt8])
        }

        init(
            pixelBuffer: CVPixelBuffer,
            preferredTransform: CGAffineTransform,
            imageContext: CIContext
        ) throws {
            if Self.isOrientationSafe(preferredTransform) {
                self.init(
                    width: CVPixelBufferGetWidth(pixelBuffer),
                    height: CVPixelBufferGetHeight(pixelBuffer),
                    storage: .bgraPixelBuffer(pixelBuffer)
                )
                return
            }
            let source = CIImage(cvPixelBuffer: pixelBuffer)
            let transformed = source.transformed(by: preferredTransform)
            let extent = transformed.extent.integral
            guard extent.width >= 1,
                  extent.height >= 1,
                  let image = imageContext.createCGImage(transformed, from: extent) else {
                throw WASBGolfBallTrackingError.modelFailed("The source frame could not be oriented.")
            }
            try self.init(image: image)
        }

        init(image: CGImage) throws {
            let frameWidth = image.width
            let frameHeight = image.height
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
            self.init(width: frameWidth, height: frameHeight, storage: .rgba(bytes))
        }

        private init(width: Int, height: Int, storage: Storage) {
            self.width = width
            self.height = height
            self.storage = storage
        }

        func writeRGBTile(
            to destination: UnsafeMutablePointer<Float32>,
            frameOffset: Int,
            channelStride: Int,
            rowStride: Int,
            columnStride: Int,
            xOrigin: Int,
            yOrigin: Int
        ) throws {
            switch storage {
            case let .bgraPixelBuffer(pixelBuffer):
                let lockResult = CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
                guard lockResult == kCVReturnSuccess,
                      let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
                    throw WASBGolfBallTrackingError.modelFailed("The source frame could not be locked.")
                }
                defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
                try Self.writeRGBRows(
                    source: baseAddress.assumingMemoryBound(to: UInt8.self),
                    bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
                    channelOffsets: (red: 2, green: 1, blue: 0),
                    destination: destination,
                    frameOffset: frameOffset,
                    channelStride: channelStride,
                    rowStride: rowStride,
                    columnStride: columnStride,
                    xOrigin: xOrigin,
                    yOrigin: yOrigin
                )
            case let .rgba(bytes):
                try bytes.withUnsafeBytes { rawBuffer in
                    guard let baseAddress = rawBuffer.bindMemory(to: UInt8.self).baseAddress else {
                        throw WASBGolfBallTrackingError.modelFailed("The oriented frame was empty.")
                    }
                    try Self.writeRGBRows(
                        source: baseAddress,
                        bytesPerRow: width * 4,
                        channelOffsets: (red: 0, green: 1, blue: 2),
                        destination: destination,
                        frameOffset: frameOffset,
                        channelStride: channelStride,
                        rowStride: rowStride,
                        columnStride: columnStride,
                        xOrigin: xOrigin,
                        yOrigin: yOrigin
                    )
                }
            }
        }

        func luminancePlane(in normalizedRegion: CGRect) throws -> GolfBallLaunchLuminancePlane {
            let x0 = min(width - 1, max(0, Int(floor(normalizedRegion.minX * CGFloat(width)))))
            let y0 = min(height - 1, max(0, Int(floor(normalizedRegion.minY * CGFloat(height)))))
            let x1 = min(width, max(x0 + 1, Int(ceil(normalizedRegion.maxX * CGFloat(width)))))
            let y1 = min(height, max(y0 + 1, Int(ceil(normalizedRegion.maxY * CGFloat(height)))))
            let planeWidth = x1 - x0
            let planeHeight = y1 - y0
            var values = [Float](repeating: 0, count: planeWidth * planeHeight)

            switch storage {
            case let .bgraPixelBuffer(pixelBuffer):
                let lockResult = CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
                guard lockResult == kCVReturnSuccess,
                      let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
                    throw WASBGolfBallTrackingError.modelFailed("The launch frame could not be locked.")
                }
                defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
                Self.writeLuminanceRows(
                    source: baseAddress.assumingMemoryBound(to: UInt8.self),
                    bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
                    channelOffsets: (red: 2, green: 1, blue: 0),
                    destination: &values,
                    xOrigin: x0,
                    yOrigin: y0,
                    width: planeWidth,
                    height: planeHeight
                )
            case let .rgba(bytes):
                bytes.withUnsafeBytes { rawBuffer in
                    guard let baseAddress = rawBuffer.bindMemory(to: UInt8.self).baseAddress else { return }
                    Self.writeLuminanceRows(
                        source: baseAddress,
                        bytesPerRow: width * 4,
                        channelOffsets: (red: 0, green: 1, blue: 2),
                        destination: &values,
                        xOrigin: x0,
                        yOrigin: y0,
                        width: planeWidth,
                        height: planeHeight
                    )
                }
            }
            return GolfBallLaunchLuminancePlane(
                sourceWidth: width,
                sourceHeight: height,
                originX: x0,
                originY: y0,
                width: planeWidth,
                height: planeHeight,
                values: values
            )
        }

        private static func writeLuminanceRows(
            source: UnsafePointer<UInt8>,
            bytesPerRow: Int,
            channelOffsets: (red: Int, green: Int, blue: Int),
            destination: inout [Float],
            xOrigin: Int,
            yOrigin: Int,
            width: Int,
            height: Int
        ) {
            for y in 0..<height {
                let row = source.advanced(by: ((yOrigin + y) * bytesPerRow) + (xOrigin * 4))
                for x in 0..<width {
                    let pixel = row.advanced(by: x * 4)
                    destination[(y * width) + x] = (0.2126 * Float(pixel[channelOffsets.red]))
                        + (0.7152 * Float(pixel[channelOffsets.green]))
                        + (0.0722 * Float(pixel[channelOffsets.blue]))
                }
            }
        }

        private static func writeRGBRows(
            source: UnsafePointer<UInt8>,
            bytesPerRow: Int,
            channelOffsets: (red: Int, green: Int, blue: Int),
            destination: UnsafeMutablePointer<Float32>,
            frameOffset: Int,
            channelStride: Int,
            rowStride: Int,
            columnStride: Int,
            xOrigin: Int,
            yOrigin: Int
        ) throws {
            var scale = Float32(1.0 / 255.0)
            let offsets = [channelOffsets.red, channelOffsets.green, channelOffsets.blue]
            for y in 0..<WASBGolfBallTrackingService.modelHeight {
                let sourceRow = source.advanced(by: ((yOrigin + y) * bytesPerRow) + (xOrigin * 4))
                let destinationRow = y * rowStride
                for channel in 0..<3 {
                    let destinationChannel = ((frameOffset * 3) + channel) * channelStride
                    let destinationPixel = destination.advanced(by: destinationChannel + destinationRow)
                    vDSP_vfltu8(
                        sourceRow.advanced(by: offsets[channel]),
                        4,
                        destinationPixel,
                        vDSP_Stride(columnStride),
                        vDSP_Length(WASBGolfBallTrackingService.modelWidth)
                    )
                    vDSP_vsmul(
                        destinationPixel,
                        vDSP_Stride(columnStride),
                        &scale,
                        destinationPixel,
                        vDSP_Stride(columnStride),
                        vDSP_Length(WASBGolfBallTrackingService.modelWidth)
                    )
                }
            }
        }

        private static func isOrientationSafe(_ transform: CGAffineTransform) -> Bool {
            abs(transform.a - 1) < 0.000_001
                && abs(transform.b) < 0.000_001
                && abs(transform.c) < 0.000_001
                && abs(transform.d - 1) < 0.000_001
                && abs(transform.tx) < 0.000_001
                && abs(transform.ty) < 0.000_001
        }
    }
}
