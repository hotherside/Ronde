import AVFoundation
import Combine
import SwiftUI
import UIKit

/// Review the original once, then take source-linked shots into the finishing Studio.
/// A bookmark is a source timestamp, not a rendered copy or a favourite.
struct RecordingStudioView: View {
    @ObservedObject var store: ReviewerStore
    @ObservedObject var accountStore: RondeAccountStore
    let recordingID: UUID
    let onOpenShot: (UUID) -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var playback = RecordingPlaybackController()
    @State private var selectedBookmarkID: UUID?
    @State private var showsShots = false
    @State private var thumbnails: [ShotVideoThumbnail] = []
    @State private var removedBookmark: RecordingBookmark?
    @State private var showsDeleteConfirmation = false
    @State private var didRouteDirectShot = false
    @Environment(\.dismiss) private var dismiss

    private var recording: ReviewSession? { store.sessions.first { $0.id == recordingID } }
    private var shots: [ReviewSession] { store.sessions.filter { $0.sourceRecordingID == recordingID }.sorted { $0.displayRange.start < $1.displayRange.start } }
    private var pendingBookmarks: [RecordingBookmark] {
        let extracted = Set(shots.compactMap(\.sourceBookmarkID))
        return (recording?.bookmarks ?? []).filter { !extracted.contains($0.id) && $0.clipRange(sourceDuration: recording?.duration ?? 0).duration > 0 }
    }

    var body: some View {
        Group {
            if let recording {
                GeometryReader { geometry in
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 12) {
                                if let error = store.libraryError { LibrarySaveNotice(store: store, message: error) }
                                if recording.sourceURL != nil {
                                    if geometry.size.width >= 800, !typeSize.isAccessibilitySize {
                                        HStack(alignment: .top, spacing: 20) {
                                            mediaWorkspace(recording)
                                                .frame(maxWidth: .infinity)
                                            inspector(recording).frame(width: RondeReviewDesign.inspectorWidth).id("moments")
                                        }
                                    } else {
                                        mediaWorkspace(recording)
                                        inspector(recording).id("moments")
                                    }
                                } else {
                                    ContentUnavailableView("Original recording unavailable", systemImage: "video.slash", description: Text("Add the original from Photos or Files to start a new recording."))
                                }
                            }
                            .padding(geometry.size.width >= 800 ? 28 : 16)
                            .frame(maxWidth: 1280, alignment: .leading).frame(maxWidth: .infinity)
                        }
                        .safeAreaInset(edge: .bottom) {
                            if !pendingBookmarks.isEmpty, recording.sourceURL != nil {
                                extractionAction(recording) {
                                    let created = store.createShots(from: recording)
                                    if !created.isEmpty {
                                        playback.pause()
                                        showsShots = true
                                        proxy.scrollTo("moments", anchor: .top)
                                    }
                                }
                            }
                        }
                    }
                }
                .reviewCanvasBackground()
                .navigationTitle("Choose shots")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar(.hidden, for: .tabBar)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Button(role: .destructive) { showsDeleteConfirmation = true } label: { Label("Delete recording", systemImage: "trash") }
                                .disabled(!store.canModifyLibrary || !shots.isEmpty)
                            if !shots.isEmpty { Text("Remove its shots before deleting the original.") }
                        } label: { Label("Recording options", systemImage: "ellipsis") }
                    }
                }
                .confirmationDialog("Delete this recording and its bookmarks?", isPresented: $showsDeleteConfirmation, titleVisibility: .visible) {
                    Button("Delete recording", role: .destructive) {
                        Task {
                            guard await store.delete(recording) else { return }
                            await accountStore.deleteRemoteLibraryItem(id: recording.id)
                            dismiss()
                        }
                    }
                } message: { Text("This removes Ronde’s local recording. Any original you kept in Photos or Files remains unchanged.") }
            } else {
                ContentUnavailableView("Recording unavailable", systemImage: "video.slash")
            }
        }
        .foregroundStyle(RondeReviewDesign.graphite)
        .task(id: recording?.sourceURL) {
            guard let recording, let url = recording.sourceURL else { return }
            playback.attach(url: url, duration: recording.duration)
            if recording.isDirectShotImport, !didRouteDirectShot {
                didRouteDirectShot = true
                await Task.yield()
                onOpenShot(recording.id)
                return
            }
            thumbnails = await ShotVideoSourceInspector().thumbnails(url: url, duration: recording.duration, count: 10)
        }
        .onDisappear { playback.detach() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { playback.pause() } }
    }

    private func mediaWorkspace(_ recording: ReviewSession) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            RecordingPlayerSurface(player: playback.player)
                .aspectRatio(3 / 2, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .background(RondeReviewDesign.mediaStage)
                .clipShape(RoundedRectangle(cornerRadius: RondeReviewDesign.controlRadius, style: .continuous))
                .accessibilityLabel("Original recording preview")
            transport(recording)
            timeline(recording)
            if let error = playback.error {
                Label(error, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(RondeReviewDesign.red)
            }
        }
    }

    private func transport(_ recording: ReviewSession) -> some View {
        RondeGlassGroup {
            ViewThatFits(in: .horizontal) {
                if !typeSize.isAccessibilitySize {
                    HStack(spacing: 8) {
                        playbackIsland
                        Spacer(minLength: 0)
                        bookmarkAction(recording)
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    playbackIsland
                    recordingTime(recording)
                    bookmarkAction(recording)
                }
            }
        }
    }

    private func recordingTime(_ recording: ReviewSession) -> some View {
        Text("\(rondeMediaTime(playback.currentTime)) / \(rondeMediaTime(recording.duration))")
            .font(.reviewerTimestamp).fixedSize()
            .padding(.horizontal, 10)
            .frame(minHeight: 44)
            .rondeControlSurface(cornerRadius: 22)
    }

    private var playbackIsland: some View {
        HStack(spacing: 4) {
            Button { playback.seek(to: playback.currentTime - 5) } label: {
                Image(systemName: "gobackward.5").frame(width: 44, height: 44)
            }.accessibilityLabel("Back 5 seconds")
            Button { playback.togglePlayback() } label: {
                Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill").frame(width: 44, height: 44)
            }.accessibilityLabel(playback.isPlaying ? "Pause" : "Play").accessibilityIdentifier("recording-play")
            Button { playback.seek(to: playback.currentTime + 5) } label: {
                Image(systemName: "goforward.5").frame(width: 44, height: 44)
            }.accessibilityLabel("Forward 5 seconds")
        }
        .font(.system(size: 18, weight: .medium))
        .buttonStyle(.plain)
        .padding(.horizontal, 2)
        .rondeControlSurface(cornerRadius: 22)
    }

    private func bookmarkAction(_ recording: ReviewSession) -> some View {
        Button {
            if let bookmark = store.addBookmark(at: playback.currentTime, to: recording) {
                selectedBookmarkID = bookmark.id
                showsShots = false
                removedBookmark = nil
            }
        } label: {
            Label("Bookmark", systemImage: "bookmark.fill")
                .font(.rondeLabel)
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .foregroundStyle(RondeReviewDesign.fairway)
        .rondeControlSurface(interactive: true, tint: RondeReviewDesign.fairwayWash, cornerRadius: 22)
        .disabled(!store.canModifyLibrary)
        .accessibilityIdentifier("recording-add-bookmark")
    }

    private func timeline(_ recording: ReviewSession) -> some View {
        VStack(spacing: 4) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    HStack(spacing: 1) {
                        ForEach(thumbnails) { frame in
                            Image(decorative: frame.image, scale: 1).resizable().scaledToFill()
                                .frame(width: max(1, (geometry.size.width - CGFloat(max(0, thumbnails.count - 1))) / CGFloat(max(1, thumbnails.count))), height: 48).clipped()
                        }
                    }.clipShape(RoundedRectangle(cornerRadius: 8))
                    ForEach(recording.bookmarks) { bookmark in
                        Rectangle().fill(RondeReviewDesign.fairwayWash).frame(width: 3, height: 48)
                            .offset(x: max(0, min(geometry.size.width - 3, geometry.size.width * bookmark.sourceTime / max(0.1, recording.duration))))
                    }
                    Rectangle().fill(.white).frame(width: 2, height: 48)
                        .offset(x: max(0, min(geometry.size.width - 2, geometry.size.width * playback.currentTime / max(0.1, recording.duration))))
                }
            }.frame(height: 48).accessibilityHidden(true)
            Slider(value: Binding(get: { min(recording.duration, playback.currentTime) }, set: playback.seek), in: 0...max(0.01, recording.duration))
                .accessibilityLabel("Recording position").accessibilityValue(String(format: "%.1f seconds", playback.currentTime))
                .accessibilityIdentifier("recording-position")
            HStack {
                Text(rondeMediaTime(playback.currentTime))
                Spacer()
                Text(rondeMediaTime(recording.duration))
            }.font(.system(.caption, design: .monospaced).weight(.medium)).foregroundStyle(RondeReviewDesign.graphiteMuted)
        }
    }

    private func inspector(_ recording: ReviewSession) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if typeSize.isAccessibilitySize {
                collectionPicker(recording).pickerStyle(.menu)
            } else {
                collectionPicker(recording).pickerStyle(.segmented)
            }
            if showsShots {
                if shots.isEmpty {
                    emptyState("No shots yet", detail: "Create shots from your bookmarks to start editing.", image: "scissors")
                } else {
                    ForEach(shots) { shot in
                        Button { playback.pause(); onOpenShot(shot.id) } label: {
                            HStack(spacing: 10) {
                                ShotPoster(sourceURL: shot.sourceURL, time: shot.displayRange.start)
                                    .frame(width: 56, height: 44).clipShape(RoundedRectangle(cornerRadius: 6))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(shot.title).font(.rondeLabel).lineLimit(2)
                                    Text("\(rondeMediaTime(shot.displayRange.start)) – \(rondeMediaTime(shot.displayRange.end))")
                                        .font(.rondeCaption.monospacedDigit()).foregroundStyle(RondeReviewDesign.graphiteMuted)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "arrow.up.right").font(.rondeCaption)
                            }
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityIdentifier("recording-open-shot")
                        if shot.id != shots.last?.id { Divider() }
                    }
                }
            } else {
                bookmarkWindowControl(recording)
                if recording.bookmarks.isEmpty {
                    emptyState("That one. Keep it.", detail: "Choose the default window above, then tap Bookmark at each moment you like.", image: "bookmark")
                } else {
                    ForEach(recording.bookmarks.sorted { $0.sourceTime < $1.sourceTime }) { bookmark in
                        bookmarkRow(bookmark, in: recording)
                    }
                }
                if let removedBookmark {
                    Button("Undo removed bookmark") {
                        selectedBookmarkID = store.addBookmark(at: removedBookmark.sourceTime, before: removedBookmark.beforeDuration, after: removedBookmark.afterDuration, to: recording)?.id
                        self.removedBookmark = nil
                    }.font(.rondeBody).frame(minHeight: 44).disabled(!store.canModifyLibrary)
                }
            }
        }
    }

    private func collectionPicker(_ recording: ReviewSession) -> some View {
        Picker("Choose shots", selection: $showsShots) {
            Text("Bookmarks · \(recording.bookmarks.count)").tag(false)
            Text("Shots · \(shots.count)").tag(true)
        }.accessibilityIdentifier("recording-collection")
    }

    private func bookmarkWindowControl(_ recording: ReviewSession) -> some View {
        let window = recording.bookmarkWindow
        return VStack(alignment: .leading, spacing: 12) {
            Text("DEFAULT CLIP WINDOW")
                .font(.reviewerSection)
                .tracking(1.2)
                .foregroundStyle(RondeReviewDesign.graphiteFaint)
            Text("New bookmarks use this window. Existing bookmarks keep their own settings.")
                .font(.subheadline)
                .foregroundStyle(RondeReviewDesign.graphiteMuted)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                ForEach([5.0, 10.0], id: \.self) { seconds in
                    let selected = window.beforeDuration == seconds && window.afterDuration == seconds
                    Button {
                        _ = store.updateBookmarkWindow(before: seconds, after: seconds, in: recording)
                    } label: {
                        Text("±\(Int(seconds))s")
                            .frame(minWidth: 58, minHeight: 36)
                    }
                    .buttonStyle(.bordered)
                    .tint(selected ? RondeReviewDesign.fairway : RondeReviewDesign.graphiteMuted)
                    .accessibilityLabel("Set default clip window to \(Int(seconds)) seconds each side")
                }
                Spacer(minLength: 0)
            }
            bufferControl("Before", value: window.beforeDuration, id: "default-before") { value in
                _ = store.updateBookmarkWindow(before: value, after: window.afterDuration, in: recording)
            }
            bufferControl("After", value: window.afterDuration, id: "default-after") { value in
                _ = store.updateBookmarkWindow(before: window.beforeDuration, after: value, in: recording)
            }
            Text("New bookmarks: \(Int(window.beforeDuration))s before + \(Int(window.afterDuration))s after")
                .font(.caption.monospacedDigit())
                .foregroundStyle(RondeReviewDesign.graphiteMuted)
        }
        .padding(14)
        .background(RondeReviewDesign.surfaceInset, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    private func bookmarkRow(_ bookmark: RecordingBookmark, in recording: ReviewSession) -> some View {
        let range = bookmark.clipRange(sourceDuration: recording.duration)
        let shot = shots.first { $0.sourceBookmarkID == bookmark.id }
        let selected = selectedBookmarkID == bookmark.id
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    selectedBookmarkID = selected ? nil : bookmark.id
                    playback.seek(to: bookmark.sourceTime)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: shot == nil ? "bookmark.fill" : "checkmark.circle.fill")
                        VStack(alignment: .leading, spacing: 4) {
                            Text(rondeMediaTime(bookmark.sourceTime)).font(.reviewerTimestamp)
                            Text("\(rondeMediaTime(range.start)) – \(rondeMediaTime(range.end)) · \(rondeMediaTime(range.duration))")
                                .font(.rondeCaption.monospacedDigit()).foregroundStyle(RondeReviewDesign.graphiteMuted)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: selected ? "chevron.up" : "chevron.down").font(.caption.weight(.semibold))
                    }.frame(minHeight: 44).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel("Bookmark at \(rondeMediaTime(bookmark.sourceTime))")
                if shot == nil {
                    Button {
                        if store.removeBookmark(bookmark.id, from: recording) {
                            removedBookmark = bookmark
                            if selected { selectedBookmarkID = nil }
                        }
                    } label: { Image(systemName: "xmark").font(.caption.weight(.semibold)).frame(width: 44, height: 44) }
                        .buttonStyle(.plain).accessibilityLabel("Remove bookmark at \(rondeMediaTime(bookmark.sourceTime))")
                        .disabled(!store.canModifyLibrary)
                }
            }
            if selected {
                if let shot {
                    Button { onOpenShot(shot.id) } label: { Label("Edit shot", systemImage: "arrow.up.right").frame(minHeight: 44) }
                        .rondeSecondaryAction()
                } else {
                    let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 12))
                    layout {
                        bufferControl("Before", value: bookmark.beforeDuration, id: "before") { value in
                            _ = store.updateBookmark(bookmark.id, sourceTime: bookmark.sourceTime, before: value, after: bookmark.afterDuration, in: recording)
                        }
                        bufferControl("After", value: bookmark.afterDuration, id: "after") { value in
                            _ = store.updateBookmark(bookmark.id, sourceTime: bookmark.sourceTime, before: bookmark.beforeDuration, after: value, in: recording)
                        }
                    }
                    if bookmark.sourceTime - bookmark.beforeDuration < 0 || bookmark.sourceTime + bookmark.afterDuration > recording.duration {
                        Text("Clamped to the recording.").font(.rondeCaption).foregroundStyle(RondeReviewDesign.graphiteMuted)
                    }
                    if range.duration == 0 {
                        Text("Add time before or after this moment to make a shot.").font(.rondeCaption).foregroundStyle(RondeReviewDesign.amber)
                    }
                }
            }
        }
        .padding(.horizontal, selected ? 10 : 0)
        .padding(.vertical, selected ? 8 : 0)
        .background(selected ? RondeReviewDesign.fairwayWash : .clear, in: RoundedRectangle(cornerRadius: RondeReviewDesign.smallRadius, style: .continuous))
        .overlay(alignment: .bottom) { Divider() }
    }

    private func bufferControl(_ title: String, value: TimeInterval, id: String, change: @escaping (TimeInterval) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.rondeCaption).foregroundStyle(RondeReviewDesign.graphiteMuted)
            bufferButtons(title, value: value, id: id, change: change)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func bufferButtons(_ title: String, value: TimeInterval, id: String, change: @escaping (TimeInterval) -> Void) -> some View {
        HStack(spacing: 4) {
            Button { change(max(0, value - 5)) } label: { Image(systemName: "minus").frame(width: 44, height: 44) }
                .accessibilityLabel("5 seconds less \(title.lowercased())").accessibilityIdentifier("recording-\(id)-decrease")
                .disabled(value <= 0 || !store.canModifyLibrary)
            Text("\(Int(value))s").font(.subheadline.monospacedDigit()).frame(minWidth: 28)
            Button { change(min(60, value + 5)) } label: { Image(systemName: "plus").frame(width: 44, height: 44) }
                .accessibilityLabel("5 seconds more \(title.lowercased())").accessibilityIdentifier("recording-\(id)-increase")
                .disabled(value >= 60 || !store.canModifyLibrary)
        }.font(.system(size: 16, weight: .medium)).buttonStyle(.borderless).rondeControlSurface(cornerRadius: 18)
    }

    private func extractionAction(_ recording: ReviewSession, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: "scissors")
                Text("Create \(pendingBookmarks.count) \(pendingBookmarks.count == 1 ? "shot" : "shots")").fontWeight(.semibold)
                Spacer()
                Image(systemName: "arrow.right")
            }.font(.rondeLabel).padding(.horizontal, 16).frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.white)
        .rondeControlSurface(interactive: true, tint: RondeReviewDesign.fairway, cornerRadius: 22).disabled(!store.canModifyLibrary)
        .accessibilityIdentifier("recording-create-shots")
        .padding(.horizontal, 16).padding(.vertical, 8)
        .frame(maxWidth: RondeReviewDesign.inspectorWidth)
        .frame(maxWidth: .infinity)
    }

    private func emptyState(_ title: String, detail: String, image: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: image).font(.rondeLabel)
            Text(detail).font(.rondeBody).foregroundStyle(RondeReviewDesign.graphiteMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 16)
    }
}

@MainActor
private final class RecordingPlaybackController: ObservableObject {
    @Published private(set) var player: AVPlayer?
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var isPlaying = false
    @Published private(set) var error: String?
    private var duration: TimeInterval = 0
    private var observer: Any?
    private var endObserver: NSObjectProtocol?
    private var statusObserver: AnyCancellable?

    func attach(url: URL, duration: TimeInterval) {
        detach()
        self.duration = max(0, duration)
        error = nil
        let player = AVPlayer(url: url)
        self.player = player
        observer = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 10), queue: .main) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self, time.seconds.isFinite else { return }
                self.currentTime = min(self.duration, max(0, time.seconds))
            }
        }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: player.currentItem, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.isPlaying = false }
        }
        statusObserver = player.currentItem?.publisher(for: \.status).sink { [weak self] status in
            guard status == .failed else { return }
            Task { @MainActor [weak self] in
                self?.error = self?.player?.currentItem?.error?.localizedDescription ?? "This recording could not be played."
                self?.pause()
            }
        }
        seek(to: currentTime)
    }

    func pause() { player?.pause(); isPlaying = false }
    func seek(to time: TimeInterval) {
        pause()
        let target = min(duration, max(0, time.isFinite ? time : 0))
        currentTime = target
        player?.currentItem?.cancelPendingSeeks()
        player?.seek(to: CMTime(seconds: target, preferredTimescale: 60_000), toleranceBefore: .zero, toleranceAfter: .zero)
    }
    func togglePlayback() {
        guard let player else { return }
        if isPlaying { pause(); return }
        if currentTime >= duration - 0.01 { seek(to: 0) }
        player.play()
        isPlaying = true
    }
    func detach() {
        pause()
        if let observer, let player { player.removeTimeObserver(observer) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        observer = nil; endObserver = nil; statusObserver = nil; player = nil
    }
}

private struct RecordingPlayerSurface: UIViewRepresentable {
    let player: AVPlayer?
    func makeUIView(context: Context) -> RecordingPlayerUIView { RecordingPlayerUIView() }
    func updateUIView(_ view: RecordingPlayerUIView, context: Context) { view.playerLayer.player = player }
    static func dismantleUIView(_ view: RecordingPlayerUIView, coordinator: Void) { view.playerLayer.player = nil }
}

private final class RecordingPlayerUIView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    override init(frame: CGRect) {
        super.init(frame: frame)
        playerLayer.videoGravity = .resizeAspect
        backgroundColor = .clear
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
