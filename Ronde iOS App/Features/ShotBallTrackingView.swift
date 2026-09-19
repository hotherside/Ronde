@preconcurrency import AVFoundation
import CoreGraphics
import Foundation
import SwiftUI
import UIKit

/// A bounded, local-only point selection sheet for a source-timed ball trace.
///
/// The caller owns the tracker and persistence. This view only presents an exact source frame,
/// collects one user-selected point, and invokes the supplied operation.
struct ShotBallTrackingView: View {
    let sourceURL: URL
    let sourceRange: ReviewTimeRange
    let initialSourceTime: TimeInterval
    let automaticOperation: (@MainActor (_ progress: @escaping @Sendable (Double) -> Void) async throws -> Void)?
    var onDrawTrace: (() -> Void)?
    let operation: @MainActor (
        _ sourceTime: TimeInterval,
        _ point: NormalizedPoint,
        _ progress: @escaping @Sendable (Double) -> Void
    ) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var runtime = ShotBallTrackingRuntime()
    @State private var frameTimes: [TimeInterval] = []
    @State private var frameIndex = 0
    @State private var currentFrame: ShotBallTrackingLoadedFrame?
    @State private var selectedPoint: NormalizedPoint?
    @State private var isLoadingTimeline = true
    @State private var isLoadingFrame = false
    @State private var errorMessage: String?
    @State private var showingPointSelection: Bool
    @State private var didStartAutomatically = false

    init(
        sourceURL: URL,
        sourceRange: ReviewTimeRange,
        initialSourceTime: TimeInterval,
        automaticOperation: (@MainActor (_ progress: @escaping @Sendable (Double) -> Void) async throws -> Void)? = nil,
        onDrawTrace: (() -> Void)? = nil,
        operation: @escaping @MainActor (
            _ sourceTime: TimeInterval,
            _ point: NormalizedPoint,
            _ progress: @escaping @Sendable (Double) -> Void
        ) async throws -> Void
    ) {
        self.sourceURL = sourceURL
        self.sourceRange = sourceRange
        self.initialSourceTime = initialSourceTime
        self.automaticOperation = automaticOperation
        self.onDrawTrace = onDrawTrace
        _showingPointSelection = State(initialValue: automaticOperation == nil)
        self.operation = operation
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if showingPointSelection {
                        instructions
                        mediaFrame
                        timelineControl
                    } else {
                        Text("Follow the ball, frame by frame")
                            .font(.reviewerTitle)
                        Text("We’ll find the ball and trace the visible flight on this device. You can correct the result before sharing.")
                            .font(.body).foregroundStyle(.secondary)
                    }
                    trackingStatus
                    actionBar
                }
                .padding(.horizontal, RondeReviewDesign.compactPageInset)
                .padding(.vertical, 18)
            }
            .reviewCanvasBackground()
            .navigationTitle(showingPointSelection ? "Select the ball" : "Trace shot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        runtime.cancel()
                        dismiss()
                    }
                }
            }
            .task {
                if let automaticOperation, !didStartAutomatically {
                    didStartAutomatically = true
                    runtime.start(operation: automaticOperation)
                }
            }
            .task(id: showingPointSelection) {
                if showingPointSelection { await prepareTimeline() }
            }
            .task(id: frameLoadKey) {
                await loadCurrentFrame()
            }
            .onDisappear {
                runtime.cancel()
            }
        }
    }

    private var instructions: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Zoom in and tap the ball on a clear frame")
                .font(.reviewerTitle)
                .foregroundStyle(RondeReviewDesign.graphite)
            Text("Choose a frame just after contact with the ball clearly in flight. We’ll follow it forwards and backwards.")
                .font(.subheadline)
                .foregroundStyle(RondeReviewDesign.graphiteMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var mediaFrame: some View {
        Group {
            if let currentFrame {
                ZoomableSeedImageView(
                    image: currentFrame.image,
                    selectedPoint: $selectedPoint,
                    isEnabled: !runtime.isRunning,
                    onSelect: { point in
                        selectedPoint = point
                        errorMessage = nil
                    }
                )
                .frame(minHeight: 220, maxHeight: 520)
                .background(RondeReviewDesign.mediaStage)
                .clipShape(RoundedRectangle(cornerRadius: RondeReviewDesign.largeRadius, style: .continuous))
                .overlay(alignment: .bottomLeading) {
                    Text("Frame at \(formatSourceTime(currentFrame.actualTime))")
                        .font(.caption.monospacedDigit().weight(.medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(.black.opacity(0.62), in: Capsule())
                        .padding(10)
                        .accessibilityLabel("Frame at \(formatSourceTime(currentFrame.actualTime))")
                }
                .accessibilityElement(children: .contain)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: RondeReviewDesign.largeRadius, style: .continuous)
                        .fill(RondeReviewDesign.mediaStage)
                    if isLoadingTimeline || isLoadingFrame {
                        ProgressView()
                            .tint(.white)
                            .accessibilityLabel("Loading source frame")
                    } else {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.largeTitle)
                            .foregroundStyle(.white.opacity(0.75))
                    }
                }
                .frame(minHeight: 220, maxHeight: 520)
            }
        }
    }

    private var timelineControl: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                Text("FRAME")
                    .font(.reviewerSection)
                    .tracking(1.2)
                    .foregroundStyle(RondeReviewDesign.graphiteFaint)
                Spacer()
                if let currentFrame {
                    Text(formatSourceTime(currentFrame.actualTime))
                        .font(.reviewerTimestamp)
                        .foregroundStyle(RondeReviewDesign.graphiteMuted)
                }
            }

            if frameTimes.isEmpty {
                Text("Finding frames…")
                    .font(.subheadline)
                    .foregroundStyle(RondeReviewDesign.graphiteMuted)
            } else {
                Slider(
                    value: Binding(
                        get: { Double(frameIndex) },
                        set: { moveToFrame(min(max(Int($0.rounded()), 0), max(frameTimes.count - 1, 0))) }
                    ),
                    in: 0...Double(max(frameTimes.count - 1, 0)),
                    step: 1
                )
                .tint(RondeReviewDesign.fairway)
                .disabled(runtime.isRunning || frameTimes.count < 2)
                .accessibilityLabel("Frame")
                .accessibilityValue("Frame \(frameIndex + 1) of \(frameTimes.count)")

                HStack {
                    Button {
                        moveToFrame(max(0, frameIndex - 1))
                    } label: {
                        Label("Previous frame", systemImage: "backward.frame")
                    }
                    .disabled(runtime.isRunning || frameIndex == 0)
                    .frame(minWidth: RondeReviewDesign.minimumTouchTarget, minHeight: RondeReviewDesign.minimumTouchTarget)
                    Spacer()
                    Text("Frame \(frameIndex + 1) of \(frameTimes.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(RondeReviewDesign.graphiteFaint)
                    Spacer()
                    Button {
                        moveToFrame(min(frameTimes.count - 1, frameIndex + 1))
                    } label: {
                        Label("Next frame", systemImage: "forward.frame")
                    }
                    .accessibilityIdentifier("ball-tracking-next-frame")
                    .disabled(runtime.isRunning || frameIndex >= frameTimes.count - 1)
                    .frame(minWidth: RondeReviewDesign.minimumTouchTarget, minHeight: RondeReviewDesign.minimumTouchTarget)
                }
                .font(.subheadline.weight(.semibold))
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .foregroundStyle(RondeReviewDesign.fairway)
            }
        }
        .reviewCard(cardPadding: 13)
    }

    @ViewBuilder
    private var trackingStatus: some View {
        if let errorMessage {
            NeedsAttentionBanner(message: errorMessage)
        } else if runtime.isRunning {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    ProgressView()
                        Text(trackingStage)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(RondeReviewDesign.graphite)
                    Spacer()
                }
                if runtime.progress > (showingPointSelection ? 0.10 : 0.325) {
                    ProgressView(value: runtime.progress).tint(RondeReviewDesign.fairway)
                }
            }
            .reviewCard(cardPadding: 13)
        } else if let statusMessage = runtime.statusMessage {
            Text(statusMessage)
                .font(.subheadline)
                .foregroundStyle(RondeReviewDesign.graphiteMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var actionBar: some View {
        VStack(spacing: 10) {
            if runtime.isRunning {
                Button(role: .cancel) {
                    runtime.cancel()
                } label: {
                    Label("Cancel trace", systemImage: "xmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(ReviewSecondaryButtonStyle(tint: RondeReviewDesign.red))
            } else if showingPointSelection {
                Button {
                    guard let currentFrame, let selectedPoint else { return }
                    runtime.start(
                        sourceTime: currentFrame.actualTime,
                        point: selectedPoint,
                        operation: operation
                    )
                } label: {
                    Label("Trace from this ball", systemImage: "scope")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(ReviewPrimaryButtonStyle(tint: RondeReviewDesign.fairway))
                .accessibilityIdentifier("ball-tracking-run")
                .disabled(!canTrack)
            } else if didStartAutomatically {
                Button {
                    showingPointSelection = true
                } label: {
                    Label("Select the ball", systemImage: "scope").frame(maxWidth: .infinity)
                }
                .buttonStyle(ReviewPrimaryButtonStyle(tint: RondeReviewDesign.fairway))
                .accessibilityIdentifier("ball-tracking-select-fallback")
            }
            if !runtime.isRunning, let onDrawTrace {
                Button("Draw the path", action: onDrawTrace)
                    .buttonStyle(ReviewSecondaryButtonStyle())
            }
        }
    }

    private var trackingStage: String {
        if !showingPointSelection, runtime.progress < 0.25 { return "Finding the ball…" }
        let trackingProgress = showingPointSelection ? runtime.progress : (runtime.progress - 0.25) / 0.75
        return trackingProgress <= 0.10 ? "Preparing the on-device tracker…" : "Tracing the ball…"
    }

    private func prepareTimeline() async {
        guard isLoadingTimeline else { return }
        do {
            let times = try await ShotBallTrackingMediaLoader.shared.timeline(
                url: sourceURL,
                sourceRange: sourceRange
            )
            guard !times.isEmpty else {
                throw ShotBallTrackingViewError.noFrames
            }
            frameTimes = times
            frameIndex = nearestFrameIndex(to: initialSourceTime, in: times)
            currentFrame = nil
            selectedPoint = nil
            isLoadingFrame = true
            isLoadingTimeline = false
        } catch is CancellationError {
            return
        } catch {
            isLoadingTimeline = false
            errorMessage = error.localizedDescription
        }
    }

    private func moveToFrame(_ index: Int) {
        guard frameTimes.indices.contains(index), index != frameIndex else { return }
        frameIndex = index
        currentFrame = nil
        selectedPoint = nil
        isLoadingFrame = true
        errorMessage = nil
    }

    private func loadCurrentFrame() async {
        guard !frameTimes.isEmpty, frameIndex < frameTimes.count else { return }
        let index = frameIndex
        let requestedTime = frameTimes[index]
        isLoadingFrame = true
        do {
            let frame = try await ShotBallTrackingMediaLoader.shared.frame(
                url: sourceURL,
                requestedTime: requestedTime
            )
            try Task.checkCancellation()
            guard frameIndex == index,
                  frameTimes.indices.contains(index),
                  abs(frame.actualTime - frameTimes[index]) <= 0.001 else { return }
            currentFrame = frame
            isLoadingFrame = false
        } catch is CancellationError {
            return
        } catch {
            guard frameIndex == index else { return }
            isLoadingFrame = false
            errorMessage = error.localizedDescription
        }
    }

    private var frameLoadKey: TimeInterval? {
        guard frameTimes.indices.contains(frameIndex) else { return nil }
        return frameTimes[frameIndex]
    }

    private var canTrack: Bool {
        guard !isLoadingTimeline, !isLoadingFrame,
              let currentFrame, selectedPoint != nil,
              frameTimes.indices.contains(frameIndex) else { return false }
        return abs(currentFrame.actualTime - frameTimes[frameIndex]) <= 0.001
    }

    private func nearestFrameIndex(to time: TimeInterval, in times: [TimeInterval]) -> Int {
        guard let first = times.first else { return 0 }
        return times.indices.min {
            abs(times[$0] - time) < abs(times[$1] - time)
        } ?? (time <= first ? 0 : times.count - 1)
    }

    private func formatSourceTime(_ time: TimeInterval) -> String {
        String(format: "%.2fs", time)
    }
}

@MainActor
private final class ShotBallTrackingRuntime: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var progress = 0.0
    @Published private(set) var statusMessage: String?

    private var task: Task<Void, Never>?
    private var generation = UUID()

    func start(
        sourceTime: TimeInterval,
        point: NormalizedPoint,
        operation: @escaping @MainActor (
            _ sourceTime: TimeInterval,
            _ point: NormalizedPoint,
            _ progress: @escaping @Sendable (Double) -> Void
        ) async throws -> Void
    ) {
        start { progress in try await operation(sourceTime, point, progress) }
    }

    func start(operation: @escaping @MainActor (_ progress: @escaping @Sendable (Double) -> Void) async throws -> Void) {
        cancel()
        let runID = UUID()
        generation = runID
        isRunning = true
        progress = 0
        statusMessage = nil
        task = Task { @MainActor [weak self] in
            guard let self, self.generation == runID else { return }
            let progressHandler: @Sendable (Double) -> Void = { [weak self] value in
                Task { @MainActor [weak self] in
                    guard let self, self.generation == runID else { return }
                    self.progress = min(max(value, 0), 1)
                }
            }
            do {
                try await operation(progressHandler)
                guard !Task.isCancelled, self.generation == runID else { return }
                isRunning = false
                progress = 1
                statusMessage = "Trace complete. Review the result before exporting."
                task = nil
            } catch is CancellationError {
                guard self.generation == runID else { return }
                isRunning = false
                statusMessage = "Trace cancelled."
                task = nil
            } catch {
                guard self.generation == runID else { return }
                isRunning = false
                statusMessage = "\(error.localizedDescription) Select the ball on a clear frame or draw its path."
                task = nil
            }
        }
    }

    func cancel() {
        generation = UUID()
        task?.cancel()
        task = nil
        if isRunning {
            isRunning = false
            statusMessage = "Trace cancelled."
        }
    }
}

private struct ShotBallTrackingLoadedFrame: @unchecked Sendable {
    let image: CGImage
    let requestedTime: TimeInterval
    let actualTime: TimeInterval
}

private enum ShotBallTrackingViewError: LocalizedError {
    case noVideoTrack
    case rangeTooLong
    case noFrames
    case imageUnavailable
    case sourcePTSOutsideTolerance(requested: TimeInterval, actual: TimeInterval)
    case cannotRead

    var errorDescription: String? {
        switch self {
        case .noVideoTrack:
            return "The selected source has no video track."
        case .rangeTooLong:
            return "Choose a clip of 20 seconds or less for this trace."
        case .noFrames:
            return "No source frames were found in this clip."
        case .imageUnavailable:
            return "The selected source frame could not be decoded."
        case let .sourcePTSOutsideTolerance(requested, actual):
            return String(format: "The frame at %.6fs could not be confirmed precisely (read %.6fs). Choose another frame.", requested, actual)
        case .cannotRead:
            return "The source could not be read."
        }
    }
}

private actor ShotBallTrackingMediaLoader {
    static let shared = ShotBallTrackingMediaLoader()

    func timeline(url: URL, sourceRange: ReviewTimeRange) async throws -> [TimeInterval] {
        guard sourceRange.duration > 0 else { throw ShotBallTrackingViewError.noFrames }
        guard sourceRange.duration <= 20 else { throw ShotBallTrackingViewError.rangeTooLong }

        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard let track = tracks.first else { throw ShotBallTrackingViewError.noVideoTrack }
        let reader = try AVAssetReader(asset: asset)
        defer { reader.cancelReading() }
        reader.timeRange = CMTimeRange(
            start: CMTime(seconds: sourceRange.start, preferredTimescale: 60_000),
            duration: CMTime(seconds: sourceRange.duration, preferredTimescale: 60_000)
        )
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw ShotBallTrackingViewError.cannotRead }
        reader.add(output)
        guard reader.startReading() else { throw ShotBallTrackingViewError.cannotRead }

        var times: [TimeInterval] = []
        while let sample = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            let timestamp = CMSampleBufferGetPresentationTimeStamp(sample).seconds
            guard timestamp.isFinite,
                  timestamp >= sourceRange.start - 0.001,
                  timestamp <= sourceRange.end + 0.001 else { continue }
            times.append(timestamp)
        }
        if reader.status == .failed { throw ShotBallTrackingViewError.cannotRead }
        return Array(Set(times)).sorted()
    }

    func frame(url: URL, requestedTime: TimeInterval) async throws -> ShotBallTrackingLoadedFrame {
        try Task.checkCancellation()
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = .zero
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let requested = CMTime(seconds: requestedTime, preferredTimescale: 60_000)

        let loaded: ShotBallTrackingLoadedFrame = try await withCheckedThrowingContinuation { continuation in
            generator.generateCGImagesAsynchronously(forTimes: [NSValue(time: requested)]) {
                _, image, actualTime, result, error in
                switch result {
                case .succeeded:
                    guard let image else {
                        continuation.resume(throwing: ShotBallTrackingViewError.imageUnavailable)
                        return
                    }
                    continuation.resume(returning: ShotBallTrackingLoadedFrame(
                        image: image,
                        requestedTime: requestedTime,
                        actualTime: actualTime.seconds
                    ))
                case .cancelled:
                    continuation.resume(throwing: CancellationError())
                case .failed:
                    continuation.resume(throwing: error ?? ShotBallTrackingViewError.imageUnavailable)
                @unknown default:
                    continuation.resume(throwing: ShotBallTrackingViewError.imageUnavailable)
                }
            }
        }
        guard loaded.actualTime.isFinite,
              abs(loaded.actualTime - loaded.requestedTime) <= 0.001 else {
            throw ShotBallTrackingViewError.sourcePTSOutsideTolerance(
                requested: loaded.requestedTime,
                actual: loaded.actualTime
            )
        }
        return loaded
    }
}

private struct ZoomableSeedImageView: UIViewRepresentable {
    let image: CGImage
    @Binding var selectedPoint: NormalizedPoint?
    let isEnabled: Bool
    let onSelect: (NormalizedPoint) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> ZoomableSeedImageContainer {
        let view = ZoomableSeedImageContainer()
        view.accessibilityIdentifier = "ball-tracking-seed-frame"
        view.onSelect = { point in
            context.coordinator.onSelect?(point)
        }
        context.coordinator.onSelect = onSelect
        view.update(image: image, selectedPoint: selectedPoint, isEnabled: isEnabled)
        return view
    }

    func updateUIView(_ uiView: ZoomableSeedImageContainer, context: Context) {
        context.coordinator.onSelect = onSelect
        uiView.onSelect = { point in
            context.coordinator.onSelect?(point)
        }
        uiView.update(image: image, selectedPoint: selectedPoint, isEnabled: isEnabled)
    }

    final class Coordinator: NSObject {
        var onSelect: ((NormalizedPoint) -> Void)?
    }
}

private final class ZoomableSeedImageContainer: UIScrollView, UIScrollViewDelegate {
    private let imageView = SeedPointImageView()
    private var imageSize = CGSize.zero
    private var hasInitialZoom = false
    var onSelect: ((NormalizedPoint) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        delegate = self
        backgroundColor = .clear
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        bouncesZoom = true
        imageView.contentMode = .scaleToFill
        imageView.isUserInteractionEnabled = true
        imageView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap(_:))))
        addSubview(imageView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(image: CGImage, selectedPoint: NormalizedPoint?, isEnabled: Bool) {
        let size = CGSize(width: image.width, height: image.height)
        if imageSize != size {
            imageSize = size
            hasInitialZoom = false
            imageView.frame = CGRect(origin: .zero, size: size)
            contentSize = size
        }
        imageView.image = UIImage(cgImage: image)
        imageView.selectedPoint = selectedPoint
        imageView.isUserInteractionEnabled = isEnabled
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard imageSize.width > 0, imageSize.height > 0, bounds.width > 0, bounds.height > 0 else { return }
        let fitScale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
        minimumZoomScale = min(1, fitScale)
        // A distant golf ball can occupy only a few source pixels. Allow
        // enlargement beyond native pixels so a finger can place the point.
        maximumZoomScale = max(minimumZoomScale * 8, 8)
        if !hasInitialZoom {
            hasInitialZoom = true
            zoomScale = minimumZoomScale
        }
        let scaledSize = CGSize(width: imageSize.width * zoomScale, height: imageSize.height * zoomScale)
        contentInset = UIEdgeInsets(
            top: max(0, (bounds.height - scaledSize.height) / 2),
            left: max(0, (bounds.width - scaledSize.width) / 2),
            bottom: 0,
            right: 0
        )
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

    @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
        guard imageView.isUserInteractionEnabled else { return }
        let location = recognizer.location(in: imageView)
        guard imageView.bounds.contains(location), imageSize.width > 0, imageSize.height > 0 else { return }
        onSelect?(NormalizedPoint(
            x: Double(min(max(location.x / imageSize.width, 0), 1)),
            y: Double(min(max(location.y / imageSize.height, 0), 1))
        ))
    }
}

private final class SeedPointImageView: UIImageView {
    var selectedPoint: NormalizedPoint? {
        didSet { setNeedsDisplay() }
    }

    override func draw(_ rect: CGRect) {
        super.draw(rect)
        guard let selectedPoint, let context = UIGraphicsGetCurrentContext() else { return }
        let point = CGPoint(
            x: CGFloat(selectedPoint.x) * bounds.width,
            y: CGFloat(selectedPoint.y) * bounds.height
        )
        let radius = max(12, min(bounds.width, bounds.height) * 0.018)
        context.setStrokeColor(UIColor.systemYellow.cgColor)
        context.setLineWidth(max(3, radius * 0.16))
        context.addEllipse(in: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
        context.strokePath()
        context.setFillColor(UIColor.systemYellow.cgColor)
        context.fillEllipse(in: CGRect(x: point.x - 2.5, y: point.y - 2.5, width: 5, height: 5))
    }
}
