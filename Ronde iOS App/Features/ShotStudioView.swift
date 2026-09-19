import AVFoundation
import Combine
import SwiftUI
import UIKit

/// One local workspace for watching, cutting and sharing a shot. Rendering choices are a
/// reversible edit; the source movie and automatic evidence remain independent records.
struct ShotStudioView: View {
    @ObservedObject var store: ReviewerStore
    let sessionID: UUID
    var onEditDetails: (() -> Void)? = nil
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @StateObject private var playback = ShotStudioPlaybackController()
    @State private var edit = ShotVideoEdit(trimStart: 0, trimEnd: 0)
    @State private var thumbnails: [ShotVideoThumbnail] = []
    @State private var frameTimes: [TimeInterval] = []
    @State private var loadingFrames = false
    @State private var isExportPresented = false
    @State private var isManualEditorPresented = false
    @State private var loadError: String?
    @State private var inspector = StudioInspector.trim

    private enum StudioInspector: String, CaseIterable, Identifiable {
        case trim, trace, format
        var id: Self { self }
        var title: String { rawValue.capitalized }
        var image: String {
            switch self {
            case .trim: "crop"
            case .trace: "hand.draw"
            case .format: "rectangle.on.rectangle"
            }
        }
    }

    private var session: ReviewSession? { store.sessions.first { $0.id == sessionID } }
    private var candidate: ReviewCandidate? { session?.defaultCandidate }
    private var hasAutomaticTrace: Bool { candidate.flatMap { ShotVideoTrace(candidate: $0, mode: .automatic) } != nil }
    private var trace: ShotVideoTrace? { candidate.flatMap { ShotVideoTrace(candidate: $0, mode: edit.overlay) } }
    private var duration: TimeInterval { session?.duration ?? 0 }
    /// Child shots retain source-time edits. The UI can offer a small handle either side of the
    /// bookmarked extraction, but never the rest of a long recording.
    private var editableSourceRange: ReviewTimeRange {
        guard let clip = session?.sourceClipRange?.clipped(to: duration) else {
            return ReviewTimeRange(start: 0, duration: duration)
        }
        let start = max(0, clip.start - 5)
        let end = min(duration, clip.end + 5)
        return ReviewTimeRange(start: start, duration: max(0, end - start))
    }
    private var resetSourceRange: ReviewTimeRange { session?.studioSourceRange ?? ReviewTimeRange(start: 0, duration: duration) }
    private var sourceAspectRatio: Double { session?.sourceAspectRatio ?? 16.0 / 9 }
    private var inspectorTabsUseVerticalLayout: Bool {
        dynamicTypeSize.isAccessibilitySize || dynamicTypeSize >= .xxxLarge
    }
    private var modes: [ShotVideoOverlayMode] {
        [.original] + (hasAutomaticTrace ? [.automatic] : []) + (candidate?.hasManualTracer == true ? [.manual] : [])
    }

    var body: some View {
        Group {
            if let session {
                GeometryReader { geometry in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 22) {
                            if let error = store.libraryError { LibrarySaveNotice(store: store, message: error) }
                            if session.sourceURL != nil {
                                studioWorkspace(availableSize: geometry.size)
                                if let loadError { errorLabel(loadError) }
                                if let error = playback.error { errorLabel(error) }
                            } else {
                                ContentUnavailableView("Original video unavailable", systemImage: "video.slash", description: Text("Import the original from Photos or Files to make a new review."))
                            }
                            if session.status == .analysing {
                                analysisStatus(session)
                            } else if let error = session.errorMessage {
                                errorLabel(error)
                            }
                            if session.status != .analysing, session.sourceURL != nil, !hasAutomaticTrace, !session.isDerivedShot, !session.isRecording {
                                Button {
                                    playback.pause()
                                    Task { _ = await store.retryAnalysis(for: session) }
                                } label: { Label("Retry analysis", systemImage: "arrow.clockwise").frame(minHeight: 44) }
                                .disabled(!store.canModifyLibrary)
                            }
                            if !session.note.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Notes").font(.headline)
                                    Text(session.note).font(.body).foregroundStyle(.secondary).textSelection(.enabled)
                                }
                            }
                        }
                        .frame(maxWidth: 1100)
                        .padding(.horizontal, geometry.size.width > 700 ? 28 : 16)
                        .padding(.top, 10)
                        .padding(.bottom, 28)
                        .frame(maxWidth: .infinity)
                    }
                    .reviewCanvasBackground()
                }
                .navigationTitle(session.title)
                .navigationBarTitleDisplayMode(.inline)
            } else {
                ContentUnavailableView("Review unavailable", systemImage: "film", description: Text("This review is no longer in your local library."))
            }
        }
        .tint(RondeReviewDesign.fairway)
        .task(id: sourceTaskID) { await prepareSource() }
        .onDisappear { playback.detach() }
        .onChange(of: duration) { old, new in
            if old <= 0, new > 0 { restoreEdit(); playback.setRange(edit) }
        }
        .onChange(of: hasAutomaticTrace) { _, hasTrace in
            if hasTrace, edit.overlay == .original, session?.videoEdit == nil { edit.overlay = .automatic }
            if !hasTrace, edit.overlay == .automatic { edit.overlay = .original }
        }
        .sheet(isPresented: $isExportPresented) {
            if let session, let sourceURL = session.sourceURL {
                ShotStudioExportSheet(sourceURL: sourceURL, sourceAspectRatio: sourceAspectRatio, candidate: candidate, edit: $edit, previewTime: playback.currentTime, onEditChanged: persistEdit)
            }
        }
        .fullScreenCover(isPresented: $isManualEditorPresented, onDismiss: {
            if candidate?.hasManualTracer == true { edit.overlay = .manual; persistEdit() }
        }) {
            if let session, let candidate { FullScreenTracerEditor(store: store, session: session, candidate: candidate) }
        }
    }

    private var sourceTaskID: String { "\(sessionID)-\(session?.sourceURL?.absoluteString ?? "missing")-\(duration)-\(editableSourceRange.start)-\(editableSourceRange.duration)" }

    @ViewBuilder private func studioWorkspace(availableSize: CGSize) -> some View {
        let isWide = availableSize.width >= 900 && !dynamicTypeSize.isAccessibilitySize
        if isWide {
            HStack(alignment: .top, spacing: 22) {
                mainStudioWorkspace(availableSize: availableSize, inspectorVisible: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                studioInspector
                    .frame(width: RondeReviewDesign.inspectorWidth)
            }
        } else {
            VStack(alignment: .leading, spacing: 18) {
                mainStudioWorkspace(availableSize: availableSize, inspectorVisible: false)
                studioInspector
            }
        }
    }

    private func mainStudioWorkspace(availableSize: CGSize, inspectorVisible: Bool) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            videoWorkspace(availableSize: availableSize, inspectorVisible: inspectorVisible)
            if duration > 0 { trimTimelineWorkspace.disabled(!store.canModifyLibrary) }
        }
    }

    private func videoWorkspace(availableSize: CGSize, inspectorVisible: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            let ratio = edit.format.aspectRatio(sourceAspectRatio: sourceAspectRatio)
            let reservedInspectorWidth = inspectorVisible ? RondeReviewDesign.inspectorWidth + 22 : 0
            let width = min(1100, max(0, availableSize.width - reservedInspectorWidth - (availableSize.width > 700 ? 56 : 32)))
            let height = min(width / ratio, max(220, min(660, availableSize.height * (dynamicTypeSize.isAccessibilitySize ? 0.38 : 0.56))))
            ShotStudioCanvas(player: playback.player, image: nil, trace: trace, sourceTime: playback.currentTime, sourceAspectRatio: sourceAspectRatio, canvasAspectRatio: ratio)
                .frame(height: height)
                .clipShape(RoundedRectangle(cornerRadius: RondeReviewDesign.cardRadius, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: RondeReviewDesign.cardRadius, style: .continuous).stroke(RondeReviewDesign.border, lineWidth: 1) }
            playbackControls
            if modes.count > 1 {
                Picker("Video overlay", selection: $edit.overlay) {
                    ForEach(modes) { mode in Text(mode.title).tag(mode) }
                }
                .pickerStyle(.menu)
                .font(.body)
                .disabled(!store.canModifyLibrary)
                .onChange(of: edit.overlay) { _, _ in persistEdit() }
            }
            Text(resultDescription)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var playbackControls: some View {
        VStack(spacing: 7) {
            ViewThatFits(in: .horizontal) {
                HStack {
                    playbackElapsedTime
                    Spacer(minLength: 16)
                    playbackTotalTime
                }
                VStack(alignment: .leading, spacing: 4) {
                    playbackElapsedTime
                    playbackTotalTime
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
            Slider(value: Binding(get: { min(max(editableSourceRange.start, playback.currentTime), max(editableSourceRange.start + 0.1, editableSourceRange.end)) }, set: { playback.seek(to: $0) }), in: editableSourceRange.start...max(editableSourceRange.start + 0.1, editableSourceRange.end))
                .accessibilityLabel("Video playback position")
                .accessibilityIdentifier("studio-position")
                .accessibilityValue("\(studioTime(playback.currentTime)) of \(studioTime(editableSourceRange.end))")
                .disabled(playback.player == nil)
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 10) { primaryTransport; secondaryTransport }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { primaryTransport; secondaryTransport }
                    VStack(spacing: 10) { primaryTransport; secondaryTransport }
                }
            }
        }
    }

    private var playbackElapsedTime: some View {
        Text(studioTime(playback.currentTime)).fixedSize()
            .accessibilityLabel("Elapsed time, \(studioTime(playback.currentTime))")
    }

    private var playbackTotalTime: some View {
        Text("/ \(studioTime(editableSourceRange.end))").fixedSize()
            .accessibilityLabel("Source position, \(studioTime(editableSourceRange.end))")
    }

    private var primaryTransport: some View {
        HStack(spacing: 4) {
            Button { stepFrame(-1) } label: { Image(systemName: "backward.frame").font(.system(size: 22)).frame(width: 44, height: 44) }
                .rondeSecondaryAction()
                .accessibilityLabel("Previous source frame")
                .disabled(frameTimes.isEmpty || playback.currentTime <= editableSourceRange.start)
            Button { playback.togglePlayback() } label: {
                HStack(spacing: 8) {
                    Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 22, weight: .semibold))
                    if !dynamicTypeSize.isAccessibilitySize { Text(playback.isPlaying ? "Pause" : "Play").fixedSize() }
                }
                    .frame(minWidth: 68, minHeight: 44)
            }
            .rondePrimaryAction()
            .accessibilityLabel(playback.isPlaying ? "Pause" : "Play")
            .accessibilityIdentifier("studio-play")
            .accessibilityHint("Resumes from the current position")
            .disabled(playback.player == nil)
            Button { stepFrame(1) } label: { Image(systemName: "forward.frame").font(.system(size: 22)).frame(width: 44, height: 44) }
                .rondeSecondaryAction()
                .accessibilityLabel("Next source frame")
                .disabled(frameTimes.isEmpty || playback.currentTime >= (frameTimes.last ?? editableSourceRange.end))
        }
    }

    private var secondaryTransport: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { replayButton; speedMenu }
            VStack(spacing: 8) { replayButton; speedMenu }
        }
        .font(.subheadline)
    }

    private var replayButton: some View {
        Button { playback.replay() } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.counterclockwise").font(.system(size: 22))
                Text("Replay cut").fixedSize()
            }
            .frame(minHeight: 44)
        }
        .rondeSecondaryAction()
        .disabled(playback.player == nil)
    }

    private var speedMenu: some View {
        Menu {
            ForEach([Float(0.25), 0.5, 1], id: \.self) { rate in
                Button(rate == 1 ? "Normal speed" : "\(rate.formatted())× speed") { playback.setSpeed(rate) }
            }
        } label: { Text("\(playback.speed.formatted())×").monospacedDigit().fixedSize().frame(minWidth: 44, minHeight: 44) }
        .rondeControlSurface(interactive: true)
        .accessibilityLabel("Playback speed, \(playback.speed.formatted()) times")
    }

    private var trimTimelineWorkspace: some View {
        VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack { trimHeading; Spacer(); resetCutButton }
                VStack(alignment: .leading, spacing: 8) { trimHeading; resetCutButton }
            }
            ShotStudioTrimTimeline(edit: $edit, sourceRange: editableSourceRange, playhead: playback.currentTime, thumbnails: thumbnails, frameTimes: frameTimes, onPreview: { playback.seek(to: $0) }, onCommit: {
                playback.setRange(edit); persistEdit()
            })
                .frame(height: 68)
            if loadingFrames { ProgressView("Preparing frame controls…").font(.subheadline) }
        }
        .padding(12)
        .background(RondeReviewDesign.surfaceInset, in: RoundedRectangle(cornerRadius: RondeReviewDesign.cardRadius, style: .continuous))
    }

    private var trimHeading: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Cut video").font(.headline)
            ShotStudioTimeRange(start: edit.trimStart, end: edit.trimEnd)
            Text("\(edit.duration.formatted(.number.precision(.fractionLength(1)))) s selected")
                .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var resetCutButton: some View {
        Button(session?.isDerivedShot == true ? "Reset to bookmarked clip" : "Use full video") { edit.trimStart = resetSourceRange.start; edit.trimEnd = resetSourceRange.end; playback.setRange(edit); persistEdit() }
            .font(.subheadline).frame(minHeight: 44)
            .disabled(abs(edit.trimStart - resetSourceRange.start) < 0.001 && abs(edit.trimEnd - resetSourceRange.end) < 0.001)
    }

    private func trimSlider(isStart: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ViewThatFits(in: .horizontal) {
                HStack { trimTimeLabel(isStart: isStart) }
                VStack(alignment: .leading, spacing: 4) { trimTimeLabel(isStart: isStart) }
            }
            .font(.subheadline.monospacedDigit())
            Slider(value: Binding(get: { isStart ? edit.trimStart : edit.trimEnd }, set: { value in
                let snapped = ShotVideoLayout.nearestFrame(to: value, presentationTimes: frameTimes)
                if isStart { edit.trimStart = min(snapped, edit.trimEnd - ShotVideoEdit.minimumDuration(for: duration)) }
                else { edit.trimEnd = max(snapped, edit.trimStart + ShotVideoEdit.minimumDuration(for: duration)) }
                edit = constrainedEdit(edit)
                playback.seek(to: isStart ? edit.trimStart : edit.trimEnd)
            }), in: editableSourceRange.start...max(editableSourceRange.start + 0.1, editableSourceRange.end), onEditingChanged: { editing in
                if !editing { playback.setRange(edit); persistEdit() }
            })
            .accessibilityLabel(isStart ? "Cut start" : "Cut end")
            .accessibilityIdentifier(isStart ? "studio-trim-start" : "studio-trim-end")
            .accessibilityValue(studioTime(isStart ? edit.trimStart : edit.trimEnd))
        }
    }

    @ViewBuilder private func trimTimeLabel(isStart: Bool) -> some View {
        Text(isStart ? "Start" : "End").fixedSize()
        Text(studioTime(isStart ? edit.trimStart : edit.trimEnd)).fixedSize()
    }

    private var studioInspector: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Make it yours.").font(.title3.weight(.semibold))
                Text("Your original recording stays untouched.")
                    .font(.subheadline).foregroundStyle(RondeReviewDesign.graphiteMuted)
            }
            inspectorTabs
            Group {
                switch inspector {
                case .trim: trimInspector
                case .trace: traceInspector
                case .format: formatInspector
                }
            }
            Divider()
            reviewActions
            Button {
                playback.pause()
                persistEdit()
                isExportPresented = true
            } label: {
                Label("Export video", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity, minHeight: RondeReviewDesign.minimumTouchTarget)
            }
            .rondePrimaryAction()
            .accessibilityIdentifier("studio-share")
            .disabled(session?.sourceURL == nil || duration <= 0 || playback.player == nil)
        }
        .padding(16)
        .reviewCard(cardPadding: 0)
    }

    private var inspectorTabs: some View {
        Group {
            if inspectorTabsUseVerticalLayout {
                VStack(spacing: 8) {
                    ForEach(StudioInspector.allCases) { inspectorTab($0) }
                }
            } else {
                HStack(spacing: 8) {
                    ForEach(StudioInspector.allCases) { inspectorTab($0) }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Studio tools")
    }

    private func inspectorTab(_ item: StudioInspector) -> some View {
        Button { inspector = item } label: {
            Label(item.title, systemImage: item.image)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: RondeReviewDesign.minimumTouchTarget)
        }
        .foregroundStyle(inspector == item ? RondeReviewDesign.graphite : RondeReviewDesign.graphiteMuted)
        .rondeSelectionSurface(isSelected: inspector == item, cornerRadius: RondeReviewDesign.smallRadius)
        .accessibilityAddTraits(inspector == item ? .isSelected : [])
    }

    private var trimInspector: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Trim").font(.headline)
            trimSlider(isStart: true)
            trimSlider(isStart: false)
            if let candidate {
                Button { playback.seek(to: candidate.impactTime) } label: {
                    Label("Go to impact", systemImage: "scope").frame(minHeight: RondeReviewDesign.minimumTouchTarget)
                }
                .rondeSecondaryAction()
            }
            Text(session?.isDerivedShot == true ? "You can refine this bookmarked clip with a little room before and after it." : "Keep the build-up and leave room for the finish. You can change this cut any time.")
                .font(.subheadline).foregroundStyle(RondeReviewDesign.graphiteMuted)
        }
    }

    private var traceInspector: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Trace").font(.headline)
            Text(resultDescription)
                .font(.body.weight(.medium)).foregroundStyle(RondeReviewDesign.graphite)
            Text(hasAutomaticTrace ? "Automatic lines show tracked source observations only." : "No automatic line is shown for this video. You can add a separately labelled manual annotation.")
                .font(.subheadline).foregroundStyle(RondeReviewDesign.graphiteMuted)
        }
    }

    private var formatInspector: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Format").font(.headline)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(ShotVideoExportFormat.allCases) { format in
                    Button { edit.format = format; persistEdit() } label: {
                        ShotStudioFormatTile(format: format, sourceAspectRatio: sourceAspectRatio, isSelected: edit.format == format)
                    }
                    .accessibilityIdentifier("studio-format-\(format.rawValue)")
                    .accessibilityLabel("\(format.title) canvas")
                    .accessibilityValue(edit.format == format ? "Selected" : "Not selected")
                    .accessibilityAddTraits(edit.format == format ? .isSelected : [])
                }
            }
            Text("Your whole video stays in frame.")
                .font(.subheadline).foregroundStyle(RondeReviewDesign.graphiteMuted)
        }
    }

    private var reviewActions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 18) { reviewActionButtons }
            VStack(alignment: .leading, spacing: 10) { reviewActionButtons }
        }
        .font(.body)
    }

    @ViewBuilder private var reviewActionButtons: some View {
        if let candidate {
            Menu {
                Button(candidate.hasManualTracer ? "Edit manual trace" : "Add manual trace") {
                    playback.pause(); isManualEditorPresented = true
                }
                if candidate.hasManualTracer, let session {
                    Button("Remove manual trace", role: .destructive) {
                        store.clearManualTracer(for: candidate, in: session)
                        edit.overlay = hasAutomaticTrace ? .automatic : .original
                        persistEdit()
                    }
                }
            } label: { Label("Manual trace", systemImage: "hand.draw").frame(minHeight: 44) }
                .rondeSecondaryAction()
                .accessibilityIdentifier("studio-manual-trace")
                .disabled(!store.canModifyLibrary || session?.status == .analysing)
        } else if let session {
            Button {
                playback.pause()
                store.playheadTime = playback.currentTime
                store.addManualMarker(in: session)
                isManualEditorPresented = true
            } label: { Label("Add manual trace", systemImage: "hand.draw").frame(minHeight: 44) }
            .rondeSecondaryAction()
            .accessibilityIdentifier("studio-manual-trace")
            .disabled(!store.canModifyLibrary || session.status == .analysing)
        }
        if let onEditDetails {
            Button { playback.pause(); onEditDetails() } label: { Label("Details & notes", systemImage: "text.alignleft").frame(minHeight: 44) }
                .rondeSecondaryAction()
                .accessibilityIdentifier("studio-details")
                .disabled(!store.canModifyLibrary)
        }
        if let session {
            Button { store.toggleFavourite(session) } label: { Label(session.isFavourite ? "Favourited" : "Favourite", systemImage: session.isFavourite ? "heart.fill" : "heart").frame(minHeight: 44) }
                .rondeSecondaryAction()
                .disabled(!store.canModifyLibrary)
        }
    }

    private var resultDescription: String {
        if edit.overlay == .manual { return "Manual annotation" }
        if hasAutomaticTrace { return edit.overlay == .original ? "Original video" : "Tracked portion only" }
        if session?.status == .analysing { return "Checking for a ball track…" }
        return "Ball flight not tracked"
    }

    private func analysisStatus(_ session: ReviewSession) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ProgressView("Checking ball movement…", value: min(max(0, session.progress), 1)).font(.subheadline)
            Button("Stop analysis") { store.cancelAnalysis(for: session) }.font(.subheadline).frame(minHeight: 44)
        }
    }

    private func errorLabel(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.circle").font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }

    private func restoreEdit() {
        guard let session else { return }
        let defaultEdit = ShotVideoEdit(
            trimStart: resetSourceRange.start,
            trimEnd: resetSourceRange.end,
            format: .original,
            overlay: candidate?.hasManualTracer == true ? .manual : hasAutomaticTrace ? .automatic : .original
        )
        edit = constrainedEdit(session.videoEdit ?? defaultEdit)
        if !modes.contains(edit.overlay) { edit.overlay = .original }
    }

    private func persistEdit() {
        guard let session, duration > 0, store.canModifyLibrary else { return }
        edit = constrainedEdit(edit)
        store.setVideoEdit(edit, for: session)
    }

    private func constrainedEdit(_ proposed: ShotVideoEdit) -> ShotVideoEdit {
        let source = proposed.normalised(sourceDuration: duration)
        let bounds = editableSourceRange
        let minimum = ShotVideoEdit.minimumDuration(for: bounds.duration)
        guard bounds.duration > 0 else { return source }
        var result = source
        result.trimStart = min(max(bounds.start, result.trimStart), max(bounds.start, bounds.end - minimum))
        result.trimEnd = min(bounds.end, max(result.trimStart + minimum, result.trimEnd))
        if result.trimEnd - result.trimStart < minimum {
            result.trimStart = max(bounds.start, bounds.end - minimum)
            result.trimEnd = bounds.end
        }
        return result
    }

    private func prepareSource() async {
        guard let session, let sourceURL = session.sourceURL, duration > 0 else { return }
        restoreEdit()
        playback.attach(url: sourceURL, edit: edit)
        loadError = nil; loadingFrames = true
        let inspector = ShotVideoSourceInspector()
        async let images = inspector.thumbnails(url: sourceURL, duration: duration, sourceRange: editableSourceRange)
        do { frameTimes = try await inspector.presentationTimes(url: sourceURL, sourceRange: editableSourceRange) }
        catch is CancellationError { loadingFrames = false; return }
        catch { loadError = "Frame controls could not load. Ordinary playback and cutting are still available." }
        thumbnails = await images
        loadingFrames = false
    }

    private func stepFrame(_ direction: Int) {
        guard let time = ShotVideoLayout.adjacentFrame(to: playback.currentTime, direction: direction, presentationTimes: frameTimes) else { return }
        playback.seek(to: time)
    }
}

@MainActor
private final class ShotStudioPlaybackController: ObservableObject {
    @Published private(set) var player: AVPlayer?
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var isPlaying = false
    @Published private(set) var speed: Float = 1
    @Published private(set) var error: String?
    private var observer: Any?
    private var endObserver: NSObjectProtocol?
    private var statusObserver: AnyCancellable?
    private var range = ShotVideoEdit(trimStart: 0, trimEnd: 0)
    private var url: URL?

    func attach(url: URL, edit: ShotVideoEdit) {
        if self.url == url, player != nil { setRange(edit); return }
        detach()
        self.url = url; range = edit; error = nil
        let player = AVPlayer(url: url)
        self.player = player
        statusObserver = player.currentItem?.publisher(for: \.status).sink { [weak self] status in
            guard status == .failed else { return }
            Task { @MainActor [weak self] in
                self?.error = self?.player?.currentItem?.error?.localizedDescription ?? "This video could not be played."
                self?.pause()
            }
        }
        observer = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 30), queue: .main) { [weak self] time in
            Task { @MainActor [weak self] in self?.currentTime = max(0, time.seconds.isFinite ? time.seconds : 0) }
        }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: player.currentItem, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.isPlaying = false }
        }
        seek(to: edit.trimStart)
    }

    func setRange(_ edit: ShotVideoEdit) { range = edit; player?.currentItem?.forwardPlaybackEndTime = CMTime(seconds: edit.trimEnd, preferredTimescale: 60_000) }
    func pause() { player?.pause(); isPlaying = false }
    func setSpeed(_ value: Float) { speed = value; if isPlaying { player?.rate = value } }
    func seek(to time: TimeInterval) {
        pause()
        let target = max(0, time)
        currentTime = target
        player?.seek(to: CMTime(seconds: target, preferredTimescale: 60_000), toleranceBefore: .zero, toleranceAfter: .zero)
    }
    func togglePlayback() {
        guard let player else { return }
        if isPlaying { pause(); return }
        player.currentItem?.forwardPlaybackEndTime = CMTime(seconds: range.trimEnd, preferredTimescale: 60_000)
        if currentTime >= range.trimEnd - 0.001 { seek(to: range.trimStart) }
        player.rate = speed; isPlaying = true
    }
    func replay() { seek(to: range.trimStart); togglePlayback() }
    func detach() {
        pause()
        if let observer, let player { player.removeTimeObserver(observer) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        observer = nil; endObserver = nil; statusObserver = nil; player = nil; url = nil
    }
}

private struct ShotStudioCanvas: View {
    let player: AVPlayer?
    let image: CGImage?
    let trace: ShotVideoTrace?
    let sourceTime: TimeInterval
    let sourceAspectRatio: Double
    let canvasAspectRatio: Double

    var body: some View {
        GeometryReader { geometry in
            let canvas = ShotVideoLayout.fittedRect(sourceAspectRatio: canvasAspectRatio, canvasSize: geometry.size)
            let fitted = ShotVideoLayout.fittedRect(sourceAspectRatio: sourceAspectRatio, canvasSize: canvas.size)
            ZStack {
                Color.black
                ZStack {
                    if let image { Image(decorative: image, scale: 1).resizable().aspectRatio(contentMode: .fit) }
                    else { ShotStudioPlayerSurface(player: player) }
                }
                .frame(width: fitted.width, height: fitted.height)
                .position(x: fitted.midX, y: fitted.midY)
                Canvas { context, _ in
                    guard let points = trace?.visiblePoints(at: sourceTime), points.count > 1 else { return }
                    var path = Path()
                    for (index, point) in points.enumerated() {
                        let position = ShotVideoLayout.point(point, in: fitted)
                        if index == 0 { path.move(to: position) } else { path.addLine(to: position) }
                    }
                    context.clip(to: Path(fitted))
                    let width = max(1.5, min(fitted.width, fitted.height) * 0.004)
                    context.stroke(path, with: .color(.black.opacity(0.5)), style: StrokeStyle(lineWidth: width + 1, lineCap: .round, lineJoin: .round))
                    context.stroke(path, with: .color(Color(red: 0.53, green: 0.27, blue: 0.91)), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
                }
                .allowsHitTesting(false)
            }
            .frame(width: canvas.width, height: canvas.height)
            .position(x: canvas.midX, y: canvas.midY)
        }
        .background(Color(uiColor: .secondarySystemBackground))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(trace.map { "Video with \($0.label.lowercased())" } ?? "Original video")
    }
}

private struct ShotStudioPlayerSurface: UIViewRepresentable {
    let player: AVPlayer?
    func makeUIView(context: Context) -> Surface { let view = Surface(); view.layerPlayer.videoGravity = .resizeAspect; return view }
    func updateUIView(_ view: Surface, context: Context) { view.layerPlayer.player = player }
    static func dismantleUIView(_ view: Surface, coordinator: ()) { view.layerPlayer.player = nil }
    final class Surface: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var layerPlayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}

private struct ShotStudioTrimTimeline: View {
    @Binding var edit: ShotVideoEdit
    let sourceRange: ReviewTimeRange
    let playhead: TimeInterval
    let thumbnails: [ShotVideoThumbnail]
    let frameTimes: [TimeInterval]
    let onPreview: (TimeInterval) -> Void
    let onCommit: () -> Void
    @State private var dragStart: TimeInterval?
    @State private var dragEnd: TimeInterval?

    var body: some View {
        GeometryReader { geometry in
            let width = max(1, geometry.size.width - 44)
            let safeDuration = max(0.1, sourceRange.duration)
            let start = 22 + width * (edit.trimStart - sourceRange.start) / safeDuration
            let end = 22 + width * (edit.trimEnd - sourceRange.start) / safeDuration
            ZStack(alignment: .leading) {
                HStack(spacing: 0) {
                    if thumbnails.isEmpty { Rectangle().fill(Color(uiColor: .secondarySystemFill)) }
                    else {
                        ForEach(thumbnails) { thumbnail in
                            Image(decorative: thumbnail.image, scale: 1).resizable().scaledToFill()
                                .frame(width: width / CGFloat(thumbnails.count), height: 54).clipped()
                        }
                    }
                }
                .frame(width: width, height: 54).clipShape(RoundedRectangle(cornerRadius: 7)).offset(x: 22)
                Rectangle().fill(.black.opacity(0.55)).frame(width: max(0, start - 22), height: 54).offset(x: 22)
                Rectangle().fill(.black.opacity(0.55)).frame(width: max(0, geometry.size.width - 22 - end), height: 54).offset(x: end)
                RoundedRectangle(cornerRadius: 7).stroke(RondeReviewDesign.fairway, lineWidth: 3).frame(width: max(0, end - start), height: 60).offset(x: start)
                Rectangle().fill(.white).frame(width: 2, height: 52).offset(x: 22 + width * (min(max(sourceRange.start, playhead), sourceRange.end) - sourceRange.start) / safeDuration)
                handle(isStart: true, width: width).position(x: start, y: geometry.size.height / 2)
                handle(isStart: false, width: width).position(x: end, y: geometry.size.height / 2)
            }
            .frame(maxHeight: .infinity)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Video cut timeline")
    }

    private func handle(isStart: Bool, width: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(RondeReviewDesign.fairway)
            .frame(width: 16, height: 62)
            .overlay { Capsule().fill(.white).frame(width: 3, height: 22) }
            .frame(width: 44, height: 68)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                if isStart, dragStart == nil { dragStart = edit.trimStart }
                if !isStart, dragEnd == nil { dragEnd = edit.trimEnd }
                let origin = (isStart ? dragStart : dragEnd) ?? sourceRange.start
                let time = ShotVideoLayout.nearestFrame(to: origin + value.translation.width / width * sourceRange.duration, presentationTimes: frameTimes)
                adjust(time, isStart: isStart)
            }.onEnded { _ in dragStart = nil; dragEnd = nil; onCommit() })
            .accessibilityElement()
            .accessibilityLabel(isStart ? "Cut start" : "Cut end")
            .accessibilityIdentifier(isStart ? "studio-trim-start-handle" : "studio-trim-end-handle")
            .accessibilityValue(studioTime(isStart ? edit.trimStart : edit.trimEnd))
            .accessibilityAdjustableAction { direction in
                let current = isStart ? edit.trimStart : edit.trimEnd
                let delta = direction == .increment ? 1 : -1
                let time = ShotVideoLayout.adjacentFrame(to: current, direction: delta, presentationTimes: frameTimes) ?? (current + Double(delta) * 0.1)
                adjust(time, isStart: isStart); onCommit()
            }
    }

    private func adjust(_ value: TimeInterval, isStart: Bool) {
        let minimum = ShotVideoEdit.minimumDuration(for: sourceRange.duration)
        if isStart { edit.trimStart = min(max(sourceRange.start, value), edit.trimEnd - minimum) }
        else { edit.trimEnd = max(min(sourceRange.end, value), edit.trimStart + minimum) }
        edit.trimStart = min(max(sourceRange.start, edit.trimStart), max(sourceRange.start, sourceRange.end - minimum))
        edit.trimEnd = min(sourceRange.end, max(edit.trimStart + minimum, edit.trimEnd))
        onPreview(isStart ? edit.trimStart : edit.trimEnd)
    }
}

/// A compact canvas silhouette makes each export choice recognisable before a person reads it.
private struct ShotStudioFormatTile: View {
    let format: ShotVideoExportFormat
    let sourceAspectRatio: Double
    let isSelected: Bool

    private var silhouetteSize: CGSize {
        let rawRatio = format.aspectRatio(sourceAspectRatio: sourceAspectRatio)
        let ratio = rawRatio.isFinite && rawRatio > 0 ? CGFloat(rawRatio) : 16 / 9
        if ratio >= 1 {
            return CGSize(width: 42, height: max(12, 42 / ratio))
        }
        return CGSize(width: max(12, 42 * ratio), height: 42)
    }

    private var label: String {
        switch format {
        case .original: "Original"
        case .portrait: "9:16"
        case .square: "1:1"
        case .landscape: "16:9"
        }
    }

    var body: some View {
        VStack(spacing: 7) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .strokeBorder(isSelected ? RondeReviewDesign.fairway : RondeReviewDesign.graphiteMuted, lineWidth: 2)
                    .frame(width: silhouetteSize.width, height: silhouetteSize.height)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption.weight(.bold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(RondeReviewDesign.fairway)
                        .offset(x: 7, y: -7)
                }
            }
            Text(label).font(.caption.weight(.semibold)).lineLimit(1)
        }
        .foregroundStyle(RondeReviewDesign.graphite)
        .frame(maxWidth: .infinity, minHeight: 78)
        .rondeSelectionSurface(isSelected: isSelected)
    }
}

private struct ShotStudioExportSheet: View {
    @Environment(\.dismiss) private var dismiss
    let sourceURL: URL
    let sourceAspectRatio: Double
    let candidate: ReviewCandidate?
    @Binding var edit: ShotVideoEdit
    let previewTime: TimeInterval
    let onEditChanged: () -> Void
    @StateObject private var exporter = ShotStudioExportController()
    @State private var preview: ShotVideoThumbnail?
    @State private var sharedFile: ShotStudioSharedFile?

    private var trace: ShotVideoTrace? { candidate.flatMap { ShotVideoTrace(candidate: $0, mode: edit.overlay) } }
    private var previewSourceTime: TimeInterval { min(max(previewTime, edit.trimStart), max(edit.trimStart, edit.trimEnd - 0.001)) }
    private var modes: [ShotVideoOverlayMode] { [.original] + (candidate.flatMap { ShotVideoTrace(candidate: $0, mode: .automatic) } != nil ? [.automatic] : []) + (candidate?.hasManualTracer == true ? [.manual] : []) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    ShotStudioCanvas(player: nil, image: preview?.image, trace: trace, sourceTime: previewSourceTime, sourceAspectRatio: sourceAspectRatio, canvasAspectRatio: edit.format.aspectRatio(sourceAspectRatio: sourceAspectRatio))
                        .frame(height: 300).clipShape(RoundedRectangle(cornerRadius: RondeReviewDesign.cardRadius, style: .continuous))
                        .accessibilityIdentifier("studio-export-preview")
                        .accessibilityValue(edit.format.title)
                        .overlay(alignment: .bottomLeading) {
                            if preview == nil { ProgressView("Preparing preview…").font(.subheadline).foregroundStyle(.white).padding() }
                        }
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Output canvas").font(.headline)
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                            ForEach(ShotVideoExportFormat.allCases) { format in
                                Button { edit.format = format } label: {
                                    ShotStudioFormatTile(format: format, sourceAspectRatio: sourceAspectRatio, isSelected: edit.format == format)
                                }
                                .accessibilityIdentifier("studio-export-format-\(format.rawValue)")
                                .accessibilityLabel("\(format.title) canvas")
                                .accessibilityValue(edit.format == format ? "Selected" : "Not selected")
                                .accessibilityAddTraits(edit.format == format ? .isSelected : [])
                            }
                        }
                        .accessibilityIdentifier("studio-export-format")
                        if modes.count > 1 {
                            Picker("Include", selection: $edit.overlay) { ForEach(modes) { mode in Text(mode.title).tag(mode) } }.pickerStyle(.menu)
                        }
                        Text("The full image fits inside the canvas. Black borders preserve your framing.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    .disabled(exporter.isExporting)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("MP4 · H.264 · up to 1080p").font(.body.weight(.medium))
                        ShotStudioTimeRange(start: edit.trimStart, end: edit.trimEnd)
                        Text("Audio included when available").font(.subheadline).foregroundStyle(.secondary)
                    }
                    if exporter.isExporting {
                        ProgressView("Exporting \(Int(exporter.progress * 100))%", value: exporter.progress).font(.body)
                        Button("Cancel export", role: .cancel) { exporter.cancel() }.frame(minHeight: 44)
                    } else if let output = exporter.outputURL {
                        Label("Your video is ready", systemImage: "checkmark.circle").font(.body)
                            .accessibilityIdentifier("studio-export-ready")
                        Button { sharedFile = ShotStudioSharedFile(url: output) } label: { Label("Share video", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity, minHeight: 44) }.rondePrimaryAction()
                            .accessibilityIdentifier("studio-export-share")
                    } else {
                        Button {
                            exporter.start(ShotVideoExportRequest(sourceURL: sourceURL, edit: edit, trace: trace))
                        } label: { Label("Export video", systemImage: "arrow.up.document").frame(maxWidth: .infinity, minHeight: 44) }.rondePrimaryAction()
                            .accessibilityIdentifier("studio-export-render")
                    }
                    if let error = exporter.error { Label(error, systemImage: "exclamationmark.circle").font(.subheadline).foregroundStyle(.red) }
                }
                .frame(maxWidth: 680).padding(20).frame(maxWidth: .infinity)
            }
            .reviewCanvasBackground()
            .navigationTitle("Export video").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() }.disabled(exporter.isExporting) } }
        }
        .tint(Color.primary)
        .interactiveDismissDisabled(exporter.isExporting)
        .task { preview = await ShotVideoSourceInspector().image(url: sourceURL, at: previewSourceTime) }
        .onChange(of: edit) { _, _ in exporter.clearOutput(); onEditChanged() }
        .onDisappear { exporter.cancelIfRunning() }
        .sheet(item: $sharedFile) { item in ActivityShareView(activityItems: [item.url]) }
    }
}

private struct ShotStudioSharedFile: Identifiable { let id = UUID(); let url: URL }

private struct ShotStudioTimeRange: View {
    let start: TimeInterval
    let end: TimeInterval
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { values }
            VStack(alignment: .leading, spacing: 4) { values }
        }
        .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Cut from \(studioTime(start)) to \(studioTime(end))")
    }
    @ViewBuilder private var values: some View {
        Text(studioTime(start)).fixedSize()
        Text("to").fixedSize()
        Text(studioTime(end)).fixedSize()
    }
}

@MainActor
private final class ShotStudioExportController: ObservableObject {
    @Published private(set) var progress = 0.0
    @Published private(set) var isExporting = false
    @Published private(set) var outputURL: URL?
    @Published private(set) var error: String?
    private var task: Task<Void, Never>?
    func start(_ request: ShotVideoExportRequest) {
        guard !isExporting else { return }
        clearOutput(); error = nil; progress = 0; isExporting = true
        task = Task { [weak self] in
            do {
                let output = try await ShotVideoExporter().export(request) { [weak self] value in await self?.updateProgress(value) }
                self?.outputURL = output
            } catch is CancellationError { self?.error = nil }
            catch { self?.error = error.localizedDescription }
            self?.isExporting = false; self?.task = nil
        }
    }
    private func updateProgress(_ value: Double) { progress = value }
    func clearOutput() {
        if let outputURL { try? FileManager.default.removeItem(at: outputURL) }
        outputURL = nil
    }
    func cancel() { task?.cancel() }
    func cancelIfRunning() { if isExporting { cancel() } }
}

private func studioTime(_ seconds: TimeInterval) -> String {
    let safe = seconds.isFinite ? max(0, seconds) : 0
    return String(format: "%d:%05.2f", Int(safe) / 60, safe.truncatingRemainder(dividingBy: 60))
}
