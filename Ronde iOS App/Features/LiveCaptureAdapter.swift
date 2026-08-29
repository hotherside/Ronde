import AVFoundation
import Combine
import Foundation

enum LiveCaptureState: Equatable {
    case unavailable
    case ready
    case armed
    case collectingPostRoll
    case replaying
    case paused(String)
    case failed(String)

    var title: String {
        switch self {
        case .unavailable: return "Capture unavailable"
        case .ready: return "Ready"
        case .armed: return "Armed"
        case .collectingPostRoll: return "Collecting post-roll"
        case .replaying: return "Replaying"
        case .paused: return "Paused"
        case .failed: return "Capture failed"
        }
    }
}

/// Narrow UI-facing seam for Terra's camera/capture implementation. The UI
/// does not invent detection events while the analysis coordinator is absent.
@MainActor
protocol LiveReviewCaptureControlling: AnyObject {
    var state: LiveCaptureState { get }
    var statePublisher: AnyPublisher<LiveCaptureState, Never> { get }
    var previewLayer: AVCaptureVideoPreviewLayer? { get }
    func start() async throws
    func stop()
}

enum LiveCaptureAdapterError: LocalizedError {
    case controllerUnavailable
    case captureFailed(String)

    var errorDescription: String? {
        switch self {
        case .controllerUnavailable:
            return "Live capture is not connected to the analysis service yet."
        case .captureFailed(let message):
            return message
        }
    }
}

@MainActor
final class UnavailableLiveReviewCaptureController: LiveReviewCaptureControlling {
    private let subject = CurrentValueSubject<LiveCaptureState, Never>(.unavailable)

    var state: LiveCaptureState { .unavailable }
    var statePublisher: AnyPublisher<LiveCaptureState, Never> { subject.eraseToAnyPublisher() }
    var previewLayer: AVCaptureVideoPreviewLayer? { nil }

    func start() async throws { throw LiveCaptureAdapterError.controllerUnavailable }
    func stop() {}
}

/// Adapter for Terra's concrete LiveReviewCaptureController. The adapter keeps
/// the reviewer views independent from camera state-machine implementation.
@MainActor
final class TerraLiveReviewCaptureAdapter: LiveReviewCaptureControlling {
    private let terra: LiveReviewCaptureController
    private let subject: CurrentValueSubject<LiveCaptureState, Never>
    private var stateTask: AnyCancellable?

    init(controller: LiveReviewCaptureController? = nil) {
        let resolved = controller ?? LiveReviewCaptureController()
        terra = resolved
        subject = CurrentValueSubject(Self.map(resolved.state))
        stateTask = resolved.$state
            .map(Self.map)
            .sink { [weak subject] value in subject?.send(value) }
    }

    var state: LiveCaptureState { Self.map(terra.state) }
    var statePublisher: AnyPublisher<LiveCaptureState, Never> { subject.eraseToAnyPublisher() }
    var previewLayer: AVCaptureVideoPreviewLayer? { terra.previewLayer }

    func start() async throws {
        await terra.prepareAndArm()
        if case let .failed(message) = terra.state {
            throw LiveCaptureAdapterError.captureFailed(message)
        }
    }

    func stop() { terra.stop() }

    private static func map(_ state: LiveReviewState) -> LiveCaptureState {
        switch state {
        case .idle: return .ready
        case .requestingPermission: return .paused("Requesting camera access")
        case .preparing: return .paused("Preparing camera")
        case .armed: return .armed
        case .collectingPostRoll: return .collectingPostRoll
        case .finalising: return .paused("Finalising segment")
        case .paused(let reason): return .paused(Self.pauseReasonTitle(reason))
        case .failed(let message): return .failed(message)
        }
    }

    private static func pauseReasonTitle(_ reason: LiveReviewPauseReason) -> String {
        switch reason {
        case .interrupted: return "Camera interrupted"
        case .thermalPressure: return "Paused for device temperature"
        case .lowStorage: return "Paused for low storage"
        case .captureUnavailable: return "Camera unavailable"
        }
    }
}

@MainActor
final class LiveCaptureControllerAdapter: ObservableObject {
    @Published private(set) var state: LiveCaptureState = .ready
    private let controller: LiveReviewCaptureControlling
    private var stateTask: AnyCancellable?

    init(controller: LiveReviewCaptureControlling? = nil) {
        let resolved = controller ?? TerraLiveReviewCaptureAdapter()
        self.controller = resolved
        state = resolved.state
        stateTask = resolved.statePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in self?.state = value }
    }

    var isConnected: Bool {
        if case .unavailable = state { return false }
        return true
    }

    var previewLayer: AVCaptureVideoPreviewLayer? { controller.previewLayer }

    func start() async {
        do {
            try await controller.start()
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func stop() { controller.stop() }
}
