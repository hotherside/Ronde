@preconcurrency import AVFoundation
import Combine
import Foundation

/// Camera session and state-machine foundation for hands-free Live Review.
/// Segment encoding is intentionally separate: retaining raw video frames in memory is prohibited.
@MainActor
final class LiveReviewCaptureController: NSObject, ObservableObject {
    @Published private(set) var state: LiveReviewState = .idle
    @Published private(set) var replaySchedule: LiveReviewReplaySchedule?
    @Published private(set) var latestFinalizedSegments: [FinalizedCaptureSegment] = []
    @Published private(set) var captureQuality: LiveReviewCaptureQuality = .preparing

    let captureSession = AVCaptureSession()
    let previewLayer: AVCaptureVideoPreviewLayer

    private let sessionQueue = DispatchQueue(label: "com.ronde.live-review.capture")
    private let stabilityMonitor = LiveReviewStabilityMonitor()
    private var videoOutput: AVCaptureVideoDataOutput?
    private var activeCamera: AVCaptureDevice?
    private var ledger = RollingSegmentLedger()
    private var postRollTask: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []

    override init() {
        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.videoGravity = .resizeAspectFill
        super.init()
        stabilityMonitor.onChange = { [weak self] stability in
            self?.captureQuality.stability = stability
        }
        observeCaptureInterruptions()
    }

    deinit {
        postRollTask?.cancel()
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    func prepareAndArm() async {
        state = .requestingPermission
        let granted = await requestCameraPermissionIfNeeded()
        guard granted else {
            state = .failed(message: "Camera access is required for Live Review.")
            return
        }

        state = .preparing
        do {
            try await configureAndStartSessionIfNeeded()
            stabilityMonitor.start()
            try? await Task.sleep(for: .milliseconds(650))
            lockFocusAndExposureIfSupported()
            state = .armed
        } catch {
            state = .failed(message: error.localizedDescription)
        }
    }

    func stop() {
        postRollTask?.cancel()
        postRollTask = nil
        stabilityMonitor.stop()
        sessionQueue.async { [captureSession] in
            if captureSession.isRunning { captureSession.stopRunning() }
        }
        replaySchedule = nil
        captureQuality = .preparing
        state = .idle
    }

    /// Called only after an encoder has atomically finalised a short app-owned segment file.
    func registerFinalizedSegment(_ segment: FinalizedCaptureSegment) {
        let evictable = ledger.append(segment)
        ledger.remove(ids: Set(evictable.map(\.id)))
        latestFinalizedSegments = ledger.segments
        // The writer/storage owner must delete `evictable` files after this call. Keeping that I/O separate
        // prevents camera callbacks from blocking on filesystem work.
    }

    /// Accepts already-fused evidence. This controller does not infer a real shot from camera motion alone.
    func handleAutomaticCandidate(_ candidate: SwingCandidate, now: Date = .now) {
        guard case .armed = state else { return }
        guard candidate.classification.kind == .uncertainCandidate else { return }

        let completion = now.addingTimeInterval(candidate.clipWindow.postRoll)
        state = .collectingPostRoll(candidate: candidate, completesAt: completion)
        replaySchedule = LiveReviewReplaySchedule(candidate: candidate, fireDate: now.addingTimeInterval(10))

        postRollTask?.cancel()
        postRollTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(candidate.clipWindow.postRoll))
            guard !Task.isCancelled else { return }
            self?.postRollDidComplete(for: candidate)
        }
    }

    /// The segment writer should call this after it has supplied all bytes through `impact + 5 seconds`.
    func postRollDidComplete(for candidate: SwingCandidate) {
        guard case let .collectingPostRoll(activeCandidate, _) = state, activeCandidate.id == candidate.id else { return }
        state = .finalising(candidate: candidate)
        // Composition/export is intentionally delegated to ExactClipExporter by the coordinator/UI layer.
        // Capture returns to armed immediately, while the export continues off the capture path.
        state = .armed
    }

    func pauseForThermalPressure() {
        postRollTask?.cancel()
        state = .paused(reason: .thermalPressure)
    }

    func pauseForLowStorage() {
        postRollTask?.cancel()
        state = .paused(reason: .lowStorage)
    }

    func resumeAfterPause() async {
        guard case .paused = state else { return }
        await prepareAndArm()
    }

    func protectedSegments(for candidate: SwingCandidate) -> [FinalizedCaptureSegment] {
        ledger.protectedSegments(for: candidate.clipWindow)
    }

    private func requestCameraPermissionIfNeeded() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: true
        case .notDetermined: await AVCaptureDevice.requestAccess(for: .video)
        default: false
        }
    }

    private func configureAndStartSessionIfNeeded() async throws {
        guard !captureSession.isRunning else { return }
        let session = captureSession
        if session.inputs.isEmpty {
            try configure(session)
        }
        try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async {
                if !session.isRunning {
                    session.startRunning()
                }
                continuation.resume()
            }
        }
    }

    private func configure(_ session: AVCaptureSession) throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        if session.canSetSessionPreset(.hd1920x1080) {
            session.sessionPreset = .hd1920x1080
        }
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            throw LiveReviewCaptureError.noCamera
        }
        try configureCameraForReview(camera)
        let cameraInput = try AVCaptureDeviceInput(device: camera)
        guard session.canAddInput(cameraInput) else { throw LiveReviewCaptureError.cannotAddInput }
        session.addInput(cameraInput)

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        guard session.canAddOutput(output) else { throw LiveReviewCaptureError.cannotAddOutput }
        session.addOutput(output)
        videoOutput = output
        activeCamera = camera
    }

    /// Live capture intentionally targets 60 Hz. Higher source rates remain supported for imports,
    /// but 60 Hz is the balanced default for exposure, thermals and a useful motion baseline.
    private func configureCameraForReview(_ camera: AVCaptureDevice) throws {
        try camera.lockForConfiguration()
        defer { camera.unlockForConfiguration() }

        let targetFPS = 60.0
        let compatible = camera.formats.filter { format in
            let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            let isUsefulResolution = dimensions.width >= 1_920 && dimensions.height >= 1_080
            let supportsRate = format.videoSupportedFrameRateRanges.contains { range in
                range.minFrameRate <= targetFPS && range.maxFrameRate >= targetFPS
            }
            return isUsefulResolution && supportsRate
        }

        if let format = compatible.min(by: { lhs, rhs in
            let left = CMVideoFormatDescriptionGetDimensions(lhs.formatDescription)
            let right = CMVideoFormatDescriptionGetDimensions(rhs.formatDescription)
            return Int(left.width) * Int(left.height) < Int(right.width) * Int(right.height)
        }) {
            camera.activeFormat = format
            let duration = CMTime(value: 1, timescale: CMTimeScale(targetFPS))
            camera.activeVideoMinFrameDuration = duration
            camera.activeVideoMaxFrameDuration = duration
        }

        if camera.isSmoothAutoFocusSupported {
            camera.isSmoothAutoFocusEnabled = true
        }
        if camera.isFocusModeSupported(.continuousAutoFocus) {
            camera.focusMode = .continuousAutoFocus
        }
        if camera.isExposureModeSupported(.continuousAutoExposure) {
            camera.exposureMode = .continuousAutoExposure
        }
        if camera.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
            camera.whiteBalanceMode = .continuousAutoWhiteBalance
        }

        let configuredFPS = camera.activeVideoMinFrameDuration.seconds > 0
            ? 1 / camera.activeVideoMinFrameDuration.seconds
            : 0
        captureQuality = LiveReviewCaptureQuality(
            framesPerSecond: configuredFPS,
            focusExposureState: .settling,
            stability: .checking,
            framingGuidance: "Keep the ball, golfer and expected flight corridor inside the guide."
        )
    }

    private func lockFocusAndExposureIfSupported() {
        guard let camera = activeCamera else {
            captureQuality.focusExposureState = .unavailable
            return
        }

        do {
            try camera.lockForConfiguration()
            defer { camera.unlockForConfiguration() }
            var didLock = false
            if camera.isFocusModeSupported(.locked) {
                camera.focusMode = .locked
                didLock = true
            }
            if camera.isExposureModeSupported(.locked) {
                camera.exposureMode = .locked
                didLock = true
            }
            if camera.isWhiteBalanceModeSupported(.locked) {
                camera.whiteBalanceMode = .locked
            }
            captureQuality.focusExposureState = didLock ? .locked : .unavailable
        } catch {
            captureQuality.focusExposureState = .unavailable
        }
    }

    private func observeCaptureInterruptions() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: AVCaptureSession.wasInterruptedNotification,
            object: captureSession,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.state = .paused(reason: .interrupted)
            }
        })
        observers.append(center.addObserver(
            forName: AVCaptureSession.runtimeErrorNotification,
            object: captureSession,
            queue: .main
        ) { [weak self] notification in
            let message = (notification.userInfo?[AVCaptureSessionErrorKey] as? NSError)?.localizedDescription ?? "Camera capture became unavailable."
            Task { @MainActor in
                self?.state = .failed(message: message)
            }
        })
    }
}

private enum LiveReviewCaptureError: LocalizedError {
    case noCamera
    case cannotAddInput
    case cannotAddOutput

    var errorDescription: String? {
        switch self {
        case .noCamera: "No compatible rear camera is available."
        case .cannotAddInput: "Ronde could not configure the rear camera."
        case .cannotAddOutput: "Ronde could not configure video capture."
        }
    }
}
