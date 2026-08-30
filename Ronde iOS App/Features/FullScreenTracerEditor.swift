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

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            GeometryReader { geometry in
                let ratio = CGFloat(session?.sourceAspectRatio ?? (16.0 / 9.0))
                let fitted = AVMakeRect(
                    aspectRatio: CGSize(width: ratio, height: 1),
                    insideRect: CGRect(origin: .zero, size: geometry.size)
                )

                ZStack {
                    RondePlayerSurface(player: playback.player)
                    AssistedTracerEditor(
                        points: $draft,
                        inferredLaunchPoints: [],
                        observedPoints: [],
                        observedPresentationTimes: [],
                        inferredPoints: [],
                        automaticApex: nil,
                        estimatedCarry: nil,
                        playbackTime: candidate?.impactTime ?? 0,
                        impactTime: candidate?.impactTime ?? 0,
                        modelFlightDuration: nil,
                        flightDuration: TracerRevealTimeline.defaultFlightDuration,
                        isEditing: true,
                        isManual: true,
                        onFinishEditing: save,
                        selectedHandle: selectedHandle,
                        showsEditingBanner: false,
                        onSelectHandle: { selectedHandle = $0 },
                        onBeginHandleAdjustment: rememberDraft
                    )
                }
                .frame(width: fitted.width, height: fitted.height)
                .position(x: fitted.midX, y: fitted.midY)
            }
            .ignoresSafeArea()

            LinearGradient(
                colors: [.black.opacity(0.42), .clear, .black.opacity(0.62)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
        .overlay(alignment: .top) { topChrome }
        .overlay(alignment: .bottom) { controlDock }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .onAppear { prepareFrame() }
        .onDisappear { playback.detach() }
        .accessibilityAction(named: "Save manual trace", save)
    }

    @ViewBuilder
    private var topChrome: some View {
        HStack(spacing: 12) {
            if #available(iOS 26.0, *) {
                Button("Cancel", action: dismiss.callAsFunction)
                    .buttonStyle(.glass)
                    .foregroundStyle(.white)
            } else {
                Button("Cancel", action: dismiss.callAsFunction)
                    .buttonStyle(TracerFallbackGlassButtonStyle())
            }

            Spacer()

            VStack(spacing: 1) {
                Text("MANUAL TRACE")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.4)
                Text("Place the flight path")
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.42), radius: 5, y: 2)
            .accessibilityElement(children: .combine)

            Spacer()

            if #available(iOS 26.0, *) {
                Button("Save", action: save)
                    .buttonStyle(.glassProminent)
                    .tint(RondeReviewDesign.fairway)
            } else {
                Button("Save", action: save)
                    .buttonStyle(TracerFallbackGlassButtonStyle(prominent: true))
            }
        }
        .font(.subheadline.weight(.semibold))
        .padding(.horizontal, horizontalSizeClass == .regular ? 28 : 16)
        .padding(.top, 12)
    }

    private var controlDock: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("SELECTED POINT")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.2)
                        .foregroundStyle(.white.opacity(0.64))
                    Text(selectedHandle.rawValue)
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text(selectedHandle.instruction)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.72))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 10)
                frameStepper
            }

            HStack(spacing: 8) {
                ForEach(AssistedTracerHandle.allCases) { handle in
                    Button {
                        selectedHandle = handle
                    } label: {
                        Label(handle.rawValue, systemImage: handle.systemImage)
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 40)
                            .foregroundStyle(selectedHandle == handle ? RondeReviewDesign.graphite : .white.opacity(0.78))
                            .background(
                                selectedHandle == handle ? Color.white.opacity(0.90) : Color.white.opacity(0.08),
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 14) {
                Button {
                    guard let previous = history.popLast() else { return }
                    draft = previous
                } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                }
                .disabled(history.isEmpty)

                Button {
                    rememberDraft()
                    draft = startingPoints
                } label: {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                }

                Spacer()

                Label("User-authored", systemImage: "person.crop.circle.badge.checkmark")
                    .foregroundStyle(.white.opacity(0.70))
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)

            Text("Saving creates a manual visual aid. Ronde keeps the original observed evidence unchanged and never presents this path as automatic tracking or measured distance.")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.62))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(horizontalSizeClass == .regular ? 20 : 16)
        .frame(maxWidth: horizontalSizeClass == .regular ? 720 : .infinity)
        .rondeDarkGlassSurface(cornerRadius: 26)
        .padding(.horizontal, horizontalSizeClass == .regular ? 28 : 12)
        .padding(.bottom, 10)
    }

    private var frameStepper: some View {
        HStack(spacing: 0) {
            Button { stepFrame(by: -1) } label: {
                Image(systemName: "backward.frame.fill")
                    .frame(width: 40, height: 36)
            }
            Text(frameTimeLabel)
                .font(.system(.caption2, design: .monospaced).weight(.semibold))
                .frame(minWidth: 58)
            Button { stepFrame(by: 1) } label: {
                Image(systemName: "forward.frame.fill")
                    .frame(width: 40, height: 36)
            }
        }
        .foregroundStyle(.white)
        .background(.black.opacity(0.22), in: Capsule())
        .accessibilityElement(children: .contain)
    }

    private var frameTimeLabel: String {
        let time = max(0, playback.currentTime)
        return String(format: "%05.2f s", time)
    }

    private func prepareFrame() {
        guard let session, let candidate, let url = session.sourceURL else { return }
        playback.attach(player: AVPlayer(url: url))
        playback.seek(to: candidate.impactTime)
    }

    private func stepFrame(by offset: Int) {
        guard let candidate else { return }
        let target = min(
            candidate.endTime,
            max(candidate.startTime, playback.currentTime + (Double(offset) / 30.0))
        )
        playback.seek(to: target)
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
        dismiss()
    }

    private static func initialPoints(for candidate: ReviewCandidate) -> AssistedTracerPoints {
        if let manual = candidate.assistedTracer {
            return AssistedTracerPoints(path: manual)
        }
        if let automatic = candidate.evidenceAnchoredPath,
           let impact = automatic.inferredLaunchConnector.first ?? automatic.observedPoints.first,
           let landing = automatic.inferredContinuation.last ?? automatic.observedPoints.last {
            let apex = automatic.apexPoint ?? impact
            return AssistedTracerPoints(
                launch: CGPoint(x: impact.x, y: impact.y),
                apex: CGPoint(x: apex.x, y: apex.y),
                landing: CGPoint(x: landing.x, y: landing.y)
            )
        }
        return .default
    }
}

private extension View {
    @ViewBuilder
    func rondeDarkGlassSurface(cornerRadius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(iOS 26.0, *) {
            self
                .background(Color.black.opacity(0.22), in: shape)
                .glassEffect(.regular.tint(.black.opacity(0.62)), in: .rect(cornerRadius: cornerRadius))
        } else {
            self
                .background(.ultraThinMaterial, in: shape)
                .background(Color.black.opacity(0.48), in: shape)
                .overlay { shape.stroke(.white.opacity(0.22), lineWidth: 0.8) }
        }
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

private struct TracerFallbackGlassButtonStyle: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 15)
            .frame(minHeight: 42)
            .background(
                prominent ? RondeReviewDesign.fairway.opacity(0.92) : Color.black.opacity(0.34),
                in: Capsule()
            )
            .background(.ultraThinMaterial, in: Capsule())
            .opacity(configuration.isPressed ? 0.72 : 1)
    }
}
