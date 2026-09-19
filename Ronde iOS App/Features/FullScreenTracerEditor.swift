import AVFoundation
import SwiftUI
import UIKit

struct FullScreenTracerEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @ObservedObject var store: ReviewerStore

    let sessionID: UUID
    let candidateID: UUID
    private let startingPoints: AssistedTracerPoints

    @State private var draft: AssistedTracerPoints
    @State private var selectedHandle: AssistedTracerHandle = .impact
    @State private var history: [AssistedTracerPoints] = []
    @State private var frameTimes: [TimeInterval] = []
    @State private var isLoadingFrameIndex = false
    @StateObject private var playback = ClipPlaybackController()

    init(store: ReviewerStore, session: ReviewSession, candidate: ReviewCandidate) {
        self.store = store
        sessionID = session.id
        candidateID = candidate.id
        let points = Self.initialPoints(for: candidate)
        startingPoints = points
        _draft = State(initialValue: points)
    }

    private var session: ReviewSession? {
        store.sessions.first { $0.id == sessionID }
    }

    private var candidate: ReviewCandidate? {
        session?.candidates.first { $0.id == candidateID }
    }

    /// A linked shot retains absolute source time but should only decode the short editable
    /// window around its bookmarked extraction. Legacy single-video sessions retain full range.
    private var editableSourceRange: ReviewTimeRange {
        guard let clip = session?.sourceClipRange?.clipped(to: session?.duration ?? 0) else {
            return ReviewTimeRange(start: 0, duration: session?.duration ?? 0)
        }
        let start = max(0, clip.start - 5)
        let end = min(session?.duration ?? 0, clip.end + 5)
        return ReviewTimeRange(start: start, duration: max(0, end - start))
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 0) {
                        videoCanvas
                            .frame(height: max(240, min(600, geometry.size.height * 0.57)))
                        controlDock
                            .frame(maxWidth: 720)
                            .padding(20)
                    }
                    .frame(maxWidth: .infinity)
                }
                .background(RondeReviewDesign.canvas)
            }
            .navigationTitle("Manual trace")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: dismiss.callAsFunction) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).fontWeight(.semibold)
                        .disabled(!store.canModifyLibrary)
                }
            }
        }
        .onAppear {
            prepareFrame()
        }
        .task(id: sourceIndexTaskID) { await prepareFrameIndex() }
        .onDisappear { playback.detach() }
        .accessibilityAction(named: "Save manual trace", save)
    }

    private var videoCanvas: some View {
        GeometryReader { geometry in
            let ratio = CGFloat(session?.sourceAspectRatio ?? (16.0 / 9.0))
            let fitted = AVMakeRect(aspectRatio: CGSize(width: ratio, height: 1), insideRect: CGRect(origin: .zero, size: geometry.size))
            ZStack {
                Color.black
                ZStack {
                    RondePlayerSurface(player: playback.player)
                    AssistedTracerEditor(
                        points: $draft, inferredLaunchPoints: [], observedPoints: [],
                        observedPresentationTimes: [], inferredPoints: [], automaticApex: nil,
                        estimatedCarry: nil, playbackTime: candidate?.impactTime ?? 0,
                        impactTime: candidate?.impactTime ?? 0, modelFlightDuration: nil,
                        flightDuration: TracerRevealTimeline.defaultFlightDuration,
                        isEditing: true, isManual: true, onFinishEditing: save,
                        selectedHandle: selectedHandle, showsEditingBanner: false,
                        onSelectHandle: { selectedHandle = $0 }, onBeginHandleAdjustment: rememberDraft
                    )
                }
                .frame(width: fitted.width, height: fitted.height)
                .position(x: fitted.midX, y: fitted.midY)
            }
        }
    }

    private var controlDock: some View {
        VStack(alignment: .leading, spacing: 20) {
            Picker("Trace point", selection: $selectedHandle) {
                ForEach(AssistedTracerHandle.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            Text(selectedHandle.instruction)
                .font(.body).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 16) {
                Button { stepFrame(by: -1) } label: {
                    Image(systemName: "backward.frame").frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("Previous source frame")
                .disabled(frameTimes.isEmpty || playback.currentTime <= editableSourceRange.start)
                Spacer(minLength: 0)
                Text(frameTimeLabel).font(.body.monospacedDigit()).fixedSize()
                Spacer(minLength: 0)
                Button { stepFrame(by: 1) } label: {
                    Image(systemName: "forward.frame").frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("Next source frame")
                .disabled(frameTimes.isEmpty || playback.currentTime >= (frameTimes.last ?? editableSourceRange.end))
            }
            if isLoadingFrameIndex { ProgressView("Preparing source frames…").font(.subheadline) }
            DisclosureGroup("Fine adjustment") {
                VStack(alignment: .leading, spacing: 12) {
                    Slider(value: pointCoordinate(horizontal: true), in: 0...1) { Text("Horizontal position") }
                        .accessibilityLabel("\(selectedHandle.rawValue) horizontal position")
                    Slider(value: pointCoordinate(horizontal: false), in: 0...1) { Text("Vertical position") }
                        .accessibilityLabel("\(selectedHandle.rawValue) vertical position")
                }.padding(.top, 12)
            }
            HStack {
                Button {
                    guard let previous = history.popLast() else { return }
                    draft = previous
                } label: { Label("Undo", systemImage: "arrow.uturn.backward") }
                .disabled(history.isEmpty)
                Spacer()
                Button {
                    rememberDraft()
                    draft = startingPoints
                } label: { Label("Reset", systemImage: "arrow.counterclockwise") }
            }
            .labelStyle(.titleOnly)
            .buttonStyle(ReviewSecondaryButtonStyle())
            Text("A manual trace is your visual annotation, not tracked ball flight.")
                .font(.subheadline).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let error = store.libraryError { LibrarySaveNotice(store: store, message: error) }
        }
    }

    private func pointCoordinate(horizontal: Bool) -> Binding<Double> {
        Binding {
            let point: CGPoint
            switch selectedHandle {
            case .impact: point = draft.launch
            case .apex: point = draft.apex
            case .landing: point = draft.landing
            }
            return horizontal ? point.x : point.y
        } set: { value in
            rememberDraft()
            switch selectedHandle {
            case .impact: if horizontal { draft.launch.x = value } else { draft.launch.y = value }
            case .apex: if horizontal { draft.apex.x = value } else { draft.apex.y = value }
            case .landing: if horizontal { draft.landing.x = value } else { draft.landing.y = value }
            }
        }
    }

    private var frameTimeLabel: String {
        let time = max(0, playback.currentTime)
        return String(format: "%05.2f s", time)
    }

    private var sourceIndexTaskID: String {
        "\(sessionID)-\(editableSourceRange.start)-\(editableSourceRange.duration)"
    }

    private func prepareFrame() {
        guard let session, let candidate, let url = session.sourceURL else { return }
        playback.attach(player: AVPlayer(url: url))
        playback.seek(to: clampedSourceTime(candidate.impactTime))
    }

    private func prepareFrameIndex() async {
        guard let session, let url = session.sourceURL, editableSourceRange.duration > 0 else { return }
        isLoadingFrameIndex = true
        defer { isLoadingFrameIndex = false }
        do {
            frameTimes = try await ShotVideoSourceInspector().presentationTimes(url: url, sourceRange: editableSourceRange)
        } catch is CancellationError {
            return
        } catch {
            frameTimes = []
        }
    }

    private func stepFrame(by offset: Int) {
        guard let time = ShotVideoLayout.adjacentFrame(to: playback.currentTime, direction: offset, presentationTimes: frameTimes) else { return }
        playback.seek(to: clampedSourceTime(time))
    }

    private func clampedSourceTime(_ time: TimeInterval) -> TimeInterval {
        min(max(editableSourceRange.start, time), editableSourceRange.end)
    }

    private func rememberDraft() {
        guard history.last != draft else { return }
        history.append(draft)
        if history.count > 20 {
            history.removeFirst(history.count - 20)
        }
    }

    private func save() {
        guard let session, let candidate else {
            dismiss()
            return
        }
        store.updateAssistedTracer(draft.path, for: candidate, in: session)
        if store.libraryError == nil { dismiss() }
    }

    private static func initialPoints(for candidate: ReviewCandidate) -> AssistedTracerPoints {
        if let manual = candidate.assistedTracer {
            return AssistedTracerPoints(path: manual)
        }
        if let automatic = candidate.evidenceAnchoredPath,
           let impact = automatic.observedPoints.first,
           let landing = automatic.observedPoints.last {
            let apex = automatic.observedPoints.min(by: { $0.y < $1.y }) ?? impact
            return AssistedTracerPoints(
                launch: CGPoint(x: impact.x, y: impact.y),
                apex: CGPoint(x: apex.x, y: apex.y),
                landing: CGPoint(x: landing.x, y: landing.y)
            )
        }
        return .default
    }
}

private extension AssistedTracerHandle {
    var instruction: String {
        switch self {
        case .impact: return "Drag the handle onto the ball at contact."
        case .apex: return "Place the highest point of the visible flight."
        case .landing: return "Place the intended end of the visual path."
        }
    }
}

private struct RondePlayerSurface: UIViewRepresentable {
    let player: AVPlayer?

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ uiView: PlayerView, context: Context) {
        uiView.playerLayer.player = player
    }

    final class PlayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

        override init(frame: CGRect) {
            super.init(frame: frame)
            playerLayer.videoGravity = .resizeAspect
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
            playerLayer.videoGravity = .resizeAspect
        }
    }
}
