import AVFoundation
import SwiftUI

/// A deliberately honest, screen-space tracer for the review MVP.
///
/// It is never presented as observed ball tracking.
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
    let observedPoints: [NormalizedPoint]
    let playbackTime: TimeInterval
    let impactTime: TimeInterval
    let flightDuration: TimeInterval
    let isEditing: Bool
    let onFinishEditing: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reducesMotion

    private var revealTimeline: TracerRevealTimeline {
        TracerRevealTimeline(impactTime: impactTime, flightDuration: flightDuration)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                tracerPath(
                    in: geometry.size,
                    progress: isEditing
                        ? 1
                        : revealTimeline.progress(at: playbackTime, reducesMotion: reducesMotion)
                )

                if isEditing {
                    handle(for: "Launch", systemImage: "circle.fill", point: $points.launch, in: geometry.size)
                    handle(for: "Apex", systemImage: "triangle.fill", point: $points.apex, in: geometry.size)
                    handle(for: "Landing", systemImage: "flag.fill", point: $points.landing, in: geometry.size)
                }

                if isEditing {
                    HStack(spacing: 7) {
                        Image(systemName: "hand.draw.fill")
                        Text("Adjust flight path")
                        Button("Done", action: onFinishEditing)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(RondeReviewDesign.tracerGold)
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
            }
            .allowsHitTesting(isEditing)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(isEditing ? "Tracer editor. Drag the launch, apex and landing handles to place the arc." : "Tracer overlay")
            .accessibilityValue(revealTimeline.accessibilityValue(at: playbackTime, reducesMotion: reducesMotion))
        }
    }

    private func tracerPath(in size: CGSize, progress: CGFloat) -> some View {
        Canvas { context, canvasSize in
            guard progress > 0 else { return }

            let launch = canvasPoint(points.launch, in: canvasSize)
            let apex = canvasPoint(points.apex, in: canvasSize)
            let landing = canvasPoint(points.landing, in: canvasSize)
            // The control point of a quadratic curve is not on the curve.
            // Derive it so the labelled apex handle is the actual midpoint.
            let control = CGPoint(
                x: (2 * apex.x) - ((launch.x + landing.x) / 2),
                y: (2 * apex.y) - ((launch.y + landing.y) / 2)
            )

            var arc = Path()
            if observedPoints.count >= 3 {
                let observed = observedPoints.map {
                    CGPoint(x: CGFloat($0.x) * canvasSize.width, y: CGFloat($0.y) * canvasSize.height)
                }
                arc.move(to: observed[0])
                for point in observed.dropFirst() { arc.addLine(to: point) }
            } else {
                arc.move(to: launch)
                arc.addQuadCurve(to: landing, control: control)
            }
            let revealedArc = arc.trimmedPath(from: 0, to: progress)
            context.drawLayer { layer in
                layer.addFilter(.shadow(color: RondeReviewDesign.tracerGold.opacity(0.72), radius: 10))
                layer.stroke(
                    revealedArc,
                    with: .color(RondeReviewDesign.tracerGold.opacity(0.62)),
                    style: StrokeStyle(lineWidth: 10, lineCap: .round, lineJoin: .round)
                )
            }
            context.stroke(revealedArc, with: .color(.black.opacity(0.42)), style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
            context.stroke(revealedArc, with: .color(RondeReviewDesign.tracerGold), style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
            context.stroke(revealedArc, with: .color(.white.opacity(0.82)), style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))

            let flightHead = observedPoints.count >= 3
                ? observedPoint(at: progress, in: canvasSize)
                : quadraticPoint(from: launch, control: control, to: landing, progress: progress)
            marker(at: flightHead, colour: .white, in: &context, size: progress < 1 ? 10 : 6)

            if isEditing {
                marker(at: launch, colour: RondeReviewDesign.fairwayBright, in: &context)
                marker(at: landing, colour: RondeReviewDesign.tracerGold, in: &context)
            }
        }
        .allowsHitTesting(false)
    }

    private func handle(for label: String, systemImage: String, point: Binding<CGPoint>, in size: CGSize) -> some View {
        let location = canvasPoint(point.wrappedValue, in: size)
        return Button {} label: {
            VStack(spacing: 3) {
                ZStack {
                    Circle()
                        .fill(.white)
                        .frame(width: 34, height: 34)
                        .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
                    Image(systemName: systemImage)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(label == "Landing" ? RondeReviewDesign.tracerGold : RondeReviewDesign.fairway)
                }
                Text(label)
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
                    point.wrappedValue = normalised(value.location, in: size)
                }
        )
        .accessibilityLabel("Tracer \(label) handle")
        .accessibilityHint("Drag to adjust the \(label.lowercased()) point")
    }

    private func canvasPoint(_ point: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: point.x * size.width, y: point.y * size.height)
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

    private func observedPoint(at progress: CGFloat, in size: CGSize) -> CGPoint {
        let points = observedPoints.map {
            CGPoint(x: CGFloat($0.x) * size.width, y: CGFloat($0.y) * size.height)
        }
        guard let first = points.first else { return .zero }
        guard points.count > 1 else { return first }
        let position = min(1, max(0, progress)) * CGFloat(points.count - 1)
        let lowerIndex = min(points.count - 1, Int(position.rounded(.down)))
        let upperIndex = min(points.count - 1, lowerIndex + 1)
        let fraction = position - CGFloat(lowerIndex)
        return CGPoint(
            x: points[lowerIndex].x + ((points[upperIndex].x - points[lowerIndex].x) * fraction),
            y: points[lowerIndex].y + ((points[upperIndex].y - points[lowerIndex].y) * fraction)
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
    let observedPoints: [NormalizedPoint]
    let fallbackPlaybackTime: TimeInterval
    let impactTime: TimeInterval
    let flightDuration: TimeInterval
    let isEditing: Bool
    let onFinishEditing: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { _ in
            AssistedTracerEditor(
                points: $points,
                observedPoints: observedPoints,
                playbackTime: player.map { max(0, $0.currentTime().seconds) } ?? fallbackPlaybackTime,
                impactTime: impactTime,
                flightDuration: flightDuration,
                isEditing: isEditing,
                onFinishEditing: onFinishEditing
            )
        }
    }
}
