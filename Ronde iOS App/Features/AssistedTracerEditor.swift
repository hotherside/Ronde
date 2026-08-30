import AVFoundation
import SwiftUI

/// A screen-space tracer for the review surface.
///
/// Automatic geometry renders as one chronological ribbon whose opacity ranges retain
/// observed-versus-estimated provenance. User rescue geometry stays explicitly labelled
/// as a Manual trace.
struct AssistedTracerPoints: Equatable {
    var launch: CGPoint
    var apex: CGPoint
    var landing: CGPoint

    static let `default` = AssistedTracerPoints(
        launch: CGPoint(x: 0.69, y: 0.61),
        apex: CGPoint(x: 0.72, y: 0.20),
        landing: CGPoint(x: 0.76, y: 0.48)
    )

    init(launch: CGPoint, apex: CGPoint, landing: CGPoint) {
        self.launch = launch
        self.apex = apex
        self.landing = landing
    }

    init(path: AssistedTracerPath) {
        launch = path.launch.cgPoint
        apex = path.apex.cgPoint
        landing = path.landing.cgPoint
    }

    var path: AssistedTracerPath {
        AssistedTracerPath(
            launch: ReviewPoint(launch),
            apex: ReviewPoint(apex),
            landing: ReviewPoint(landing)
        )
    }
}

enum AssistedTracerHandle: String, CaseIterable, Identifiable {
    case impact = "Impact"
    case apex = "Apex"
    case landing = "Landing"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .impact: return "smallcircle.filled.circle"
        case .apex: return "triangle.fill"
        case .landing: return "flag.fill"
        }
    }
}

/// Maps the player's actual item time to the visible portion of an assisted
/// tracer. The values are intentionally independent of the source frame rate:
/// AVPlayer provides the authoritative presentation time for any imported file.
struct TracerRevealTimeline: Equatable {
    static let defaultFlightDuration: TimeInterval = 1.35

    let impactTime: TimeInterval
    let flightDuration: TimeInterval

    init(impactTime: TimeInterval, flightDuration: TimeInterval = Self.defaultFlightDuration) {
        self.impactTime = max(0, impactTime)
        self.flightDuration = max(0.01, flightDuration)
    }

    func progress(at itemTime: TimeInterval, reducesMotion: Bool = false) -> CGFloat {
        guard itemTime >= impactTime else { return 0 }
        if reducesMotion { return 1 }
        return CGFloat(min(1, max(0, (itemTime - impactTime) / flightDuration)))
    }

    func accessibilityValue(at itemTime: TimeInterval, reducesMotion: Bool = false) -> String {
        let visibleProgress = progress(at: itemTime, reducesMotion: reducesMotion)
        switch visibleProgress {
        case 0:
            return "Tracer hidden until impact"
        case 1:
            return "Full flight path visible"
        default:
            return "Flight path \(Int((visibleProgress * 100).rounded())) percent revealed"
        }
    }
}

struct AssistedTracerEditor: View {
    @Binding var points: AssistedTracerPoints
    let inferredLaunchPoints: [NormalizedPoint]
    let observedPoints: [NormalizedPoint]
    let observedPresentationTimes: [TimeInterval]
    let inferredPoints: [NormalizedPoint]
    let automaticApex: NormalizedPoint?
    let estimatedCarry: EstimatedCarryDistance?
    let playbackTime: TimeInterval
    let impactTime: TimeInterval
    /// Original fitted impact-to-landing duration. `flightDuration` may be shorter solely to fit
    /// the remaining source while preserving the model-timed ascent.
    let modelFlightDuration: TimeInterval?
    let flightDuration: TimeInterval
    let isEditing: Bool
    let isManual: Bool
    let onFinishEditing: () -> Void
    var selectedHandle: AssistedTracerHandle? = nil
    var showsEditingBanner = true
    var showsEvidenceChrome = true
    var onSelectHandle: (AssistedTracerHandle) -> Void = { _ in }
    var onBeginHandleAdjustment: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reducesMotion
    @State private var activeDragHandle: AssistedTracerHandle?

    private var revealTimeline: TracerRevealTimeline {
        TracerRevealTimeline(impactTime: impactTime, flightDuration: flightDuration)
    }

    private var timedObservedPath: TimedTrajectoryPath? {
        TimedTrajectoryPath(
            points: observedPoints,
            presentationTimes: observedPresentationTimes
        )
    }

    private var fullFlightTimeline: FullFlightRevealTimeline? {
        guard !isManual else { return nil }
        return FullFlightRevealTimeline(
            impactTime: impactTime,
            inferredLaunchConnector: inferredLaunchPoints,
            observedPoints: observedPoints,
            observedPresentationTimes: observedPresentationTimes,
            inferredContinuation: inferredPoints,
            estimatedFlightDuration: modelFlightDuration ?? flightDuration,
            presentationFlightDuration: flightDuration
        )
    }

    private var carryOpacity: Double {
        guard !isEditing,
              estimatedCarry != nil,
              let fullFlightTimeline,
              fullFlightTimeline.revealsEstimatedLanding else {
            return 0
        }
        let visibleDistance = fullFlightTimeline.visibleDistance(
            at: playbackTime,
            reducesMotion: reducesMotion
        )
        return visibleDistance >= 1 - 0.000_001 ? 1 : 0
    }

    var body: some View {
        GeometryReader { geometry in
            let manualProgress = isEditing
                ? CGFloat(1)
                : revealTimeline.progress(at: playbackTime, reducesMotion: reducesMotion)
            ZStack {
                tracerPath(
                    in: geometry.size,
                    manualProgress: manualProgress
                )

                if !isEditing,
                   !isManual,
                   let automaticApex,
                   automaticApexOpacity > 0 {
                    ZStack {
                        ZStack {
                            Circle().fill(.white).frame(width: 17, height: 17)
                            Circle().fill(RondeReviewDesign.tracerPurple).frame(width: 10, height: 10)
                        }
                        .shadow(color: RondeReviewDesign.tracerPurple.opacity(0.9), radius: 8)
                        Text(hasEstimatedGeometry ? "EST. APEX" : "APEX")
                            .font(.system(size: 9, weight: .heavy, design: .rounded))
                            .tracking(0.8)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(.black.opacity(0.66), in: Capsule())
                            .offset(y: -25)
                    }
                    .position(canvasPoint(automaticApex, in: geometry.size))
                    .opacity(automaticApexOpacity)
                    .accessibilityLabel(hasEstimatedGeometry ? "Estimated apex" : "Observed apex")
                }

                if !isEditing,
                   !isManual,
                   let automaticLanding = inferredPoints.last,
                   carryOpacity > 0 {
                    ZStack {
                        ZStack {
                            Circle().fill(.white).frame(width: 15, height: 15)
                            Circle().fill(RondeReviewDesign.tracerPurple).frame(width: 8, height: 8)
                        }
                        .shadow(color: RondeReviewDesign.tracerPurple.opacity(0.8), radius: 7)
                        Text("EST. LANDING")
                            .font(.system(size: 9, weight: .heavy, design: .rounded))
                            .tracking(0.7)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(.black.opacity(0.66), in: Capsule())
                            .offset(y: 24)
                    }
                    .position(canvasPoint(automaticLanding, in: geometry.size))
                    .opacity(carryOpacity)
                    .accessibilityLabel("Estimated landing position")
                }

                if !isEditing,
                   let estimatedCarry,
                   showsEvidenceChrome,
                   carryOpacity > 0 {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("MODEL CARRY")
                            .font(.system(size: 9, weight: .heavy, design: .rounded))
                            .tracking(1)
                        Text(estimatedCarry.displayText)
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .monospacedDigit()
                        Text("ESTIMATE · UNCALIBRATED")
                            .font(.system(size: 8, weight: .bold, design: .rounded))
                            .tracking(0.6)
                            .foregroundStyle(.white.opacity(0.76))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.62), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .padding(12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .opacity(carryOpacity)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Modelled uncalibrated carry estimate, \(estimatedCarry.displayText)")
                }

                if isEditing {
                    handle(.impact, point: $points.launch, in: geometry.size)
                    handle(.apex, point: $points.apex, in: geometry.size)
                    handle(.landing, point: $points.landing, in: geometry.size)
                }

                if isEditing && showsEditingBanner {
                    HStack(spacing: 7) {
                        Image(systemName: "hand.draw.fill")
                        Text("Place the flight path")
                        Button("Done", action: onFinishEditing)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(RondeReviewDesign.tracerPurple)
                            .buttonStyle(.plain)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(.black.opacity(0.52), in: Capsule())
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .topTrailing)
                }

                if !isEditing && showsEvidenceChrome {
                    Text(sourceLabel)
                        .font(.system(.caption2, design: .rounded).weight(.bold))
                        .tracking(0.8)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 7)
                        .background(.black.opacity(0.58), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .padding(12)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(sourceAccessibilityLabel)
                }
            }
            .allowsHitTesting(isEditing)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(isEditing ? "Tracer editor. Drag the launch, apex and landing handles to place the arc." : sourceAccessibilityLabel)
            .accessibilityValue(tracerAccessibilityValue)
        }
    }

    private var sourceLabel: String {
        if isManual { return "MANUAL TRACE" }
        return inferredLaunchPoints.isEmpty && inferredPoints.isEmpty
            ? "OBSERVED"
            : "OBSERVED BALL · ESTIMATED FLIGHT"
    }

    private var sourceAccessibilityLabel: String {
        if isManual {
            return "Manual trace placed by you. It is a visual aid, not observed ball flight."
        }
        if inferredLaunchPoints.isEmpty && inferredPoints.isEmpty {
            return "Observed ball flight from the uploaded frames."
        }
        return "Observed ball points with an estimated connector, apex and landing."
    }

    private var hasEstimatedGeometry: Bool {
        !inferredLaunchPoints.isEmpty || !inferredPoints.isEmpty
    }

    private var automaticApexOpacity: Double {
        guard let automaticApex else { return 0 }
        if let fullFlightTimeline {
            guard let apexRevealTime = fullFlightTimeline.revealTime(for: automaticApex) else {
                return 0
            }
            let revealThreshold = reducesMotion ? impactTime : apexRevealTime
            return playbackTime >= revealThreshold ? 1 : 0
        }
        guard let timedObservedPath,
              let apexTime = timedObservedPath.presentationTime(for: automaticApex) else {
            return playbackTime >= impactTime + flightDuration ? 1 : 0
        }
        return playbackTime >= apexTime + timedObservedPath.suggestedTrailLag ? 1 : 0
    }

    private var tracerAccessibilityValue: String {
        if isEditing || isManual {
            return revealTimeline.accessibilityValue(at: playbackTime, reducesMotion: reducesMotion)
        }
        guard let fullFlightTimeline else {
            return playbackTime >= impactTime + flightDuration
                ? "Completed ball path visible"
                : "Ball path waiting for source timing"
        }
        if playbackTime < impactTime {
            return "Tracer hidden until impact"
        }
        let visibleDistance = fullFlightTimeline.visibleDistance(
            at: playbackTime,
            reducesMotion: reducesMotion
        )
        if visibleDistance >= 1 - 0.000_001 {
            return "Complete chronological ball path visible"
        }
        if visibleDistance < fullFlightTimeline.observedRange.lowerBound {
            return "Estimated launch path revealing from impact"
        }
        if visibleDistance < fullFlightTimeline.observedRange.upperBound {
            return "Observed tracer following the tracked ball"
        }
        return "Estimated continuation revealing towards landing"
    }

    private func tracerPath(
        in size: CGSize,
        manualProgress: CGFloat
    ) -> some View {
        Canvas { context, canvasSize in
            let launch = canvasPoint(points.launch, in: canvasSize)
            let apex = canvasPoint(points.apex, in: canvasSize)
            let landing = canvasPoint(points.landing, in: canvasSize)
            // The control point of a quadratic curve is not on the curve.
            // Derive it so the labelled apex handle is the actual midpoint.
            let control = CGPoint(
                x: (2 * apex.x) - ((launch.x + landing.x) / 2),
                y: (2 * apex.y) - ((launch.y + landing.y) / 2)
            )

            if isEditing || isManual || (observedPoints.count < 3 && inferredPoints.isEmpty) {
                guard manualProgress > 0 else { return }
                var manualArc = Path()
                manualArc.move(to: launch)
                manualArc.addQuadCurve(to: landing, control: control)
                let revealedArc = manualArc.trimmedPath(from: 0, to: manualProgress)
                strokeObserved(revealedArc, in: &context)
            } else if let fullFlightTimeline {
                let fullPath = makePath(
                    from: fullFlightTimeline.smoothedSamples.map(\.point),
                    in: canvasSize
                )
                let visibleDistance = fullFlightTimeline.visibleDistance(
                    at: playbackTime,
                    reducesMotion: reducesMotion
                )

                if let launchRange = fullFlightTimeline.launchRange?.visibleRange(
                    through: visibleDistance
                ) {
                    strokeFlightRibbon(
                        fullPath,
                        range: launchRange,
                        provenanceOpacity: 0.74,
                        in: &context
                    )
                }
                if let observedRange = fullFlightTimeline.observedRange.visibleRange(
                    through: visibleDistance
                ) {
                    strokeFlightRibbon(
                        fullPath,
                        range: observedRange,
                        provenanceOpacity: 1,
                        in: &context
                    )
                }
                if let continuationRange = fullFlightTimeline.continuationRange?.visibleRange(
                    through: visibleDistance
                ) {
                    strokeFlightRibbon(
                        fullPath,
                        range: continuationRange,
                        provenanceOpacity: 0.74,
                        in: &context
                    )
                }
            } else {
                guard manualProgress > 0 else { return }
                var manualArc = Path()
                manualArc.move(to: launch)
                manualArc.addQuadCurve(to: landing, control: control)
                strokeObserved(manualArc.trimmedPath(from: 0, to: manualProgress), in: &context)
            }

            if isEditing || isManual || observedPoints.count < 3 {
                let flightHead = quadraticPoint(from: launch, control: control, to: landing, progress: manualProgress)
                marker(at: flightHead, colour: .white, in: &context, size: manualProgress < 1 ? 10 : 6)
            }

            if isEditing {
                marker(at: launch, colour: RondeReviewDesign.fairwayBright, in: &context)
                marker(at: landing, colour: RondeReviewDesign.tracerPurple, in: &context)
            }
        }
        .allowsHitTesting(false)
    }

    private func makePath(from points: [NormalizedPoint], in size: CGSize) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: canvasPoint(first, in: size))
        for point in points.dropFirst() {
            path.addLine(to: canvasPoint(point, in: size))
        }
        return path
    }

    /// Draws one solid broadcast-style ribbon. Small overlapping trims vary width gradually along
    /// the complete path; provenance changes opacity only, so it cannot create a geometric seam
    /// or a second reveal order.
    private func strokeFlightRibbon(
        _ fullPath: Path,
        range: ClosedRange<Double>,
        provenanceOpacity: Double,
        in context: inout GraphicsContext
    ) {
        let length = max(0, range.upperBound - range.lowerBound)
        let sliceCount = max(1, Int(ceil(length * 40)))
        let visiblePath = fullPath.trimmedPath(
            from: CGFloat(range.lowerBound),
            to: CGFloat(range.upperBound)
        )
        let rangeMidpoint = (range.lowerBound + range.upperBound) / 2
        let averageWidth = 6.4 - (3.2 * pow(rangeMidpoint, 1.08))

        context.drawLayer { layer in
            layer.addFilter(.shadow(
                color: RondeReviewDesign.tracerPurple.opacity(0.70 * provenanceOpacity),
                radius: 9
            ))
            layer.stroke(
                visiblePath,
                with: .color(RondeReviewDesign.tracerPurple.opacity(0.42 * provenanceOpacity)),
                style: StrokeStyle(
                    lineWidth: averageWidth * 1.9,
                    lineCap: .round,
                    lineJoin: .round
                )
            )
        }

        for index in 0..<sliceCount {
            let start = range.lowerBound + (length * Double(index) / Double(sliceCount))
            let end = range.lowerBound + (length * Double(index + 1) / Double(sliceCount))
            let midpoint = (start + end) / 2
            let lineWidth = 6.4 - (3.2 * pow(midpoint, 1.08))
            let segment = fullPath.trimmedPath(from: CGFloat(start), to: CGFloat(end))

            context.stroke(
                segment,
                with: .color(.black.opacity(0.34 * provenanceOpacity)),
                style: StrokeStyle(
                    lineWidth: lineWidth + 2.4,
                    lineCap: .butt,
                    lineJoin: .round
                )
            )
            context.stroke(
                segment,
                with: .color(RondeReviewDesign.tracerPurple.opacity(provenanceOpacity)),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt, lineJoin: .round)
            )
        }
        context.stroke(
            visiblePath,
            with: .color(.white.opacity(0.64 * provenanceOpacity)),
            style: StrokeStyle(lineWidth: 0.9, lineCap: .round, lineJoin: .round)
        )
    }

    private func strokeObserved(_ path: Path, in context: inout GraphicsContext) {
        context.drawLayer { layer in
            layer.addFilter(.shadow(color: RondeReviewDesign.tracerPurple.opacity(0.78), radius: 10))
            layer.stroke(
                path,
                with: .color(RondeReviewDesign.tracerPurple.opacity(0.66)),
                style: StrokeStyle(lineWidth: 10, lineCap: .round, lineJoin: .round)
            )
        }
        context.stroke(path, with: .color(.black.opacity(0.42)), style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
        context.stroke(path, with: .color(RondeReviewDesign.tracerPurple), style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
        context.stroke(path, with: .color(.white.opacity(0.82)), style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
    }

    private func handle(_ handle: AssistedTracerHandle, point: Binding<CGPoint>, in size: CGSize) -> some View {
        let location = canvasPoint(point.wrappedValue, in: size)
        let isSelected = selectedHandle == nil || selectedHandle == handle
        return Button {
            onSelectHandle(handle)
        } label: {
            VStack(spacing: 3) {
                ZStack {
                    Circle()
                        .fill(.white)
                        .frame(width: isSelected ? 38 : 34, height: isSelected ? 38 : 34)
                        .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
                    Circle()
                        .stroke(RondeReviewDesign.tracerPurple.opacity(isSelected ? 0.9 : 0), lineWidth: 3)
                        .frame(width: 44, height: 44)
                    Image(systemName: handle.systemImage)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(handle == .landing ? RondeReviewDesign.tracerPurple : RondeReviewDesign.fairway)
                }
                Text(handle.rawValue)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 3)
                    .background(.black.opacity(0.66), in: Capsule())
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .position(location)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if activeDragHandle != handle {
                        activeDragHandle = handle
                        onBeginHandleAdjustment()
                        onSelectHandle(handle)
                    }
                    point.wrappedValue = normalised(value.location, in: size)
                }
                .onEnded { _ in
                    activeDragHandle = nil
                }
        )
        .accessibilityLabel("Tracer \(handle.rawValue) handle")
        .accessibilityHint("Drag to adjust the \(handle.rawValue.lowercased()) point")
    }

    private func canvasPoint(_ point: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: point.x * size.width, y: point.y * size.height)
    }

    private func canvasPoint(_ point: NormalizedPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: CGFloat(point.x) * size.width, y: CGFloat(point.y) * size.height)
    }

    private func normalised(_ point: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(
            x: min(0.96, max(0.04, point.x / max(1, size.width))),
            y: min(0.90, max(0.08, point.y / max(1, size.height)))
        )
    }

    private func quadraticPoint(from start: CGPoint, control: CGPoint, to end: CGPoint, progress: CGFloat) -> CGPoint {
        let inverse = 1 - progress
        return CGPoint(
            x: (inverse * inverse * start.x) + (2 * inverse * progress * control.x) + (progress * progress * end.x),
            y: (inverse * inverse * start.y) + (2 * inverse * progress * control.y) + (progress * progress * end.y)
        )
    }

    private func marker(at point: CGPoint, colour: Color, in context: inout GraphicsContext, size: CGFloat = 14) {
        let outer = CGRect(x: point.x - (size / 2), y: point.y - (size / 2), width: size, height: size)
        let innerSize = max(3, size * 0.43)
        let inner = CGRect(x: point.x - (innerSize / 2), y: point.y - (innerSize / 2), width: innerSize, height: innerSize)
        context.fill(Circle().path(in: outer), with: .color(.white))
        context.fill(Circle().path(in: inner), with: .color(colour))
    }
}

/// Keeps the overlay correct when the system video's scrubber seeks while
/// paused. The periodic player observer drives normal playback; this native
/// SwiftUI timeline also reads the AVPlayer item's presentation time directly
/// while the review surface is visible.
struct PlayerSynchronizedTracer: View {
    let player: AVPlayer?
    @Binding var points: AssistedTracerPoints
    let inferredLaunchPoints: [NormalizedPoint]
    let observedPoints: [NormalizedPoint]
    let observedPresentationTimes: [TimeInterval]
    let inferredPoints: [NormalizedPoint]
    let automaticApex: NormalizedPoint?
    let estimatedCarry: EstimatedCarryDistance?
    let fallbackPlaybackTime: TimeInterval
    let impactTime: TimeInterval
    let modelFlightDuration: TimeInterval?
    let flightDuration: TimeInterval
    let isEditing: Bool
    let isManual: Bool
    let onFinishEditing: () -> Void
    var showsEvidenceChrome = true

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { _ in
            AssistedTracerEditor(
                points: $points,
                inferredLaunchPoints: inferredLaunchPoints,
                observedPoints: observedPoints,
                observedPresentationTimes: observedPresentationTimes,
                inferredPoints: inferredPoints,
                automaticApex: automaticApex,
                estimatedCarry: estimatedCarry,
                playbackTime: player.map { max(0, $0.currentTime().seconds) } ?? fallbackPlaybackTime,
                impactTime: impactTime,
                modelFlightDuration: modelFlightDuration,
                flightDuration: flightDuration,
                isEditing: isEditing,
                isManual: isManual,
                onFinishEditing: onFinishEditing,
                showsEvidenceChrome: showsEvidenceChrome
            )
        }
    }
}
