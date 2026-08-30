import AVFoundation
import AVKit
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

enum ReviewLaunchIntent: String, CaseIterable, Identifiable {
    case oneShot
    case range
    case live

    var id: String { rawValue }

    var title: String {
        switch self {
        case .oneShot: return "Shot Video"
        case .range: return "Range Session"
        case .live: return "Hands-free Review"
        }
    }

    var subtitle: String {
        switch self {
        case .oneShot: return "Import one shot video up to 1 minute for automatic tracer review."
        case .range: return "Review potential moments in a longer recording."
        case .live: return "Keep the phone fixed and review moments as you hit."
        }
    }

    var icon: String {
        switch self {
        case .oneShot: return "play.rectangle.fill"
        case .range: return "film.stack"
        case .live: return "waveform.badge.mic"
        }
    }
}

struct RondeLibraryView: View {
    @ObservedObject var store: ReviewerStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selectedSection: LibrarySection? = .sessions
    @State private var presentedIntent: ReviewLaunchIntent?
    @State private var phonePath: [UUID] = []

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                iPadLayout
            } else {
                NavigationStack(path: $phonePath) { phoneLayout }
            }
        }
        .reviewCanvasBackground()
        .preferredColorScheme(.light)
        .sheet(item: $presentedIntent) { intent in
            switch intent {
            case .oneShot, .range:
                RangeSessionEntryView(store: store, intent: intent) { session in
                    store.select(session)
                    selectedSection = .sessions
                    if horizontalSizeClass != .regular {
                        phonePath = [session.id]
                    }
                }
            case .live:
                LiveReviewView(store: store)
            }
        }
    }

    private var phoneLayout: some View {
        SessionLibraryHome(
            store: store,
            onChooseMode: { presentedIntent = $0 }
        )
        .navigationTitle("Ronde")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: UUID.self) { sessionID in
            if let session = store.sessions.first(where: { $0.id == sessionID }) {
                SessionWorkspaceView(store: store, session: session)
            } else {
                ContentUnavailableView("Review unavailable", systemImage: "film", description: Text("This local session is no longer available."))
            }
        }
    }

    private var iPadLayout: some View {
        NavigationSplitView {
            List(selection: $selectedSection) {
                Section("Workspace") {
                    Label("Sessions", systemImage: LibrarySection.sessions.icon)
                        .tag(LibrarySection.sessions as LibrarySection?)
                    Label("Settings", systemImage: LibrarySection.settings.icon)
                        .tag(LibrarySection.settings as LibrarySection?)
                }

                if !store.sessions.isEmpty {
                    Section("Recent") {
                        ForEach(store.sessions) { session in
                            SessionListRow(session: session)
                                .tag(LibrarySection.sessions as LibrarySection?)
                                .contentShape(Rectangle())
                                .onTapGesture { store.select(session) }
                        }
                    }
                }
            }
            .navigationTitle("Ronde")
            .listStyle(.sidebar)
        } detail: {
            if let session = store.selectedSession, selectedSection == .sessions {
                SessionWorkspaceView(store: store, session: session)
            } else if selectedSection == .settings {
                SettingsPlaceholderView()
            } else {
                SessionLibraryHome(store: store, onChooseMode: { presentedIntent = $0 })
            }
        }
    }
}

struct SessionLibraryHome: View {
    @ObservedObject var store: ReviewerStore
    let onChooseMode: (ReviewLaunchIntent) -> Void
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        ScrollView {
            Group {
                if horizontalSizeClass == .regular {
                    iPadHome
                } else {
                    VStack(alignment: .leading, spacing: 22) {
                        header
                        modeChooser

                        if store.sessions.isEmpty {
                            EmptySessionsView(onChooseMode: onChooseMode)
                        } else {
                            recentSessions
                        }
                    }
                }
            }
            .frame(maxWidth: 1080, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, horizontalSizeClass == .regular ? 30 : 24)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .scrollIndicators(.hidden)
    }

    private var iPadHome: some View {
        VStack(alignment: .leading, spacing: 24) {
            header

            HStack(alignment: .top, spacing: 22) {
                VStack(alignment: .leading, spacing: 12) {
                    modeChooser
                    if store.sessions.isEmpty {
                        EmptySessionsView(onChooseMode: onChooseMode)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)

                if !store.sessions.isEmpty {
                    recentSessions
                        .frame(maxWidth: 430, alignment: .topLeading)
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Image(systemName: "scope")
                    .font(.caption.weight(.bold))
                Text("RONDE REVIEW")
            }
                .font(.reviewerSection)
                .tracking(1.7)
                .foregroundStyle(RondeReviewDesign.fairway)
            Text("Trace the shot.")
                .font(.reviewerDisplay)
                .foregroundStyle(RondeReviewDesign.graphite)
                .fixedSize(horizontal: false, vertical: true)
            Text("Import one short shot video. Ronde finds the launch and builds the flight path locally.")
                .font(.body)
                .foregroundStyle(RondeReviewDesign.graphiteMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var modeChooser: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("START WITH FOOTAGE")
                .font(.reviewerSection)
                .tracking(1.4)
                .foregroundStyle(RondeReviewDesign.graphiteFaint)

            // Live capture is intentionally not offered as a peer action until
            // the end-to-end capture and association loop is ready.
            ForEach([ReviewLaunchIntent.oneShot]) { intent in
                Button { onChooseMode(intent) } label: {
                    ModeLaunchRow(intent: intent)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 7) {
                Image(systemName: "camera.metering.unknown")
                    .font(.caption.weight(.semibold))
                Text("MVP scope: one shot per video, up to 1 minute. Session slicing comes later.")
                    .font(.caption)
            }
            .foregroundStyle(RondeReviewDesign.graphiteFaint)
            .accessibilityElement(children: .combine)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var recentSessions: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("RECENT SESSIONS")
                    .font(.reviewerSection)
                    .tracking(1.4)
                    .foregroundStyle(RondeReviewDesign.graphiteFaint)
                Spacer()
                Text("\(store.sessions.count)")
                    .font(.reviewerTimestamp)
                    .foregroundStyle(RondeReviewDesign.graphiteMuted)
            }

            LazyVStack(spacing: 8) {
                ForEach(store.sessions) { session in
                    NavigationLink {
                        SessionWorkspaceView(store: store, session: session)
                    } label: {
                        SessionListRow(session: session)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ModeLaunchRow: View {
    let intent: ReviewLaunchIntent

    var body: some View {
        HStack(spacing: 13) {
            ModeMedallion(intent: intent)

            VStack(alignment: .leading, spacing: 4) {
                Text(intent == .oneShot ? "SHOT VIDEO · UP TO 1 MINUTE" : "FOR A SESSION")
                    .font(.reviewerSection)
                    .tracking(1.1)
                    .foregroundStyle(intent == .oneShot ? RondeReviewDesign.amber : RondeReviewDesign.fairway)
                Text(intent.title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(RondeReviewDesign.graphite)
                Text(intent.subtitle)
                    .font(.footnote)
                    .foregroundStyle(RondeReviewDesign.graphiteMuted)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(RondeReviewDesign.graphiteFaint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, intent == .oneShot ? 14 : 12)
        .background(
            RoundedRectangle(cornerRadius: RondeReviewDesign.cardRadius, style: .continuous)
                .fill(intent == .oneShot ? RondeReviewDesign.surface : RondeReviewDesign.surfaceRaised)
        )
        .overlay {
            RoundedRectangle(cornerRadius: RondeReviewDesign.cardRadius, style: .continuous)
                .stroke(intent == .oneShot ? RondeReviewDesign.tracerPurple.opacity(0.62) : RondeReviewDesign.border, lineWidth: intent == .oneShot ? 1.1 : 0.8)
        }
        .shadow(color: intent == .oneShot ? RondeReviewDesign.tracerPurple.opacity(0.12) : .clear, radius: 12, y: 5)
        .contentShape(RoundedRectangle(cornerRadius: RondeReviewDesign.cardRadius, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens \(intent.title)")
    }
}

private struct ModeMedallion: View {
    let intent: ReviewLaunchIntent

    var body: some View {
        ZStack {
            Circle()
                .fill(intent == .oneShot ? RondeReviewDesign.amberWash : RondeReviewDesign.fairwayWash)
            Image(systemName: intent.icon)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(intent == .oneShot ? RondeReviewDesign.amber : RondeReviewDesign.fairway)
        }
        .frame(width: 42, height: 42)
        .accessibilityHidden(true)
    }
}

struct SessionListRow: View {
    let session: ReviewSession

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(RondeReviewDesign.statusColor(for: session.status))
                .frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 3) {
                Text(session.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(RondeReviewDesign.graphite)
                    .lineLimit(1)
                Text(metadata)
                    .font(.caption)
                    .foregroundStyle(RondeReviewDesign.graphiteMuted)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)
            Text(session.status.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(RondeReviewDesign.statusColor(for: session.status))
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(RondeReviewDesign.graphiteFaint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .reviewCard(cardPadding: 14)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(session.title), \(metadata), \(session.status.title)")
    }

    private var metadata: String {
        let duration = session.duration > 0 ? formatDuration(session.duration) : "No source"
        let count: String
        if session.isSingleShotImport {
            count = "One shot"
        } else {
            let shots = session.acceptedShots.count == 1 ? "1 likely shot" : "\(session.acceptedShots.count) likely shots"
            let queue = session.reviewQueue.count > 0 ? " · \(session.reviewQueue.count) to review" : ""
            count = shots + queue
        }
        return "\(session.mode.title) · \(duration) · \(count)"
    }
}

struct EmptySessionsView: View {
    let onChooseMode: (ReviewLaunchIntent) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "film")
                .font(.body.weight(.semibold))
                .foregroundStyle(RondeReviewDesign.fairway)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("NO REVIEWS YET")
                    .font(.reviewerSection)
                    .tracking(1.3)
                    .foregroundStyle(RondeReviewDesign.fairway)
                Text("Your imported clips will appear here.")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(RondeReviewDesign.graphite)
                Text("Import a shot video above to begin.")
                    .font(.caption)
                    .foregroundStyle(RondeReviewDesign.graphiteMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

private struct RangeFlightMotif: View {
    var body: some View {
        Canvas { context, size in
            let horizon = size.height * 0.66
            let ground = Path(CGRect(x: 0, y: horizon, width: size.width, height: size.height - horizon))
            context.fill(ground, with: .color(RondeReviewDesign.fairwayWash.opacity(0.7)))

            var horizonLine = Path()
            horizonLine.move(to: CGPoint(x: 0, y: horizon))
            horizonLine.addLine(to: CGPoint(x: size.width, y: horizon))
            context.stroke(horizonLine, with: .color(RondeReviewDesign.fairway.opacity(0.42)), lineWidth: 1)

            var fairway = Path()
            fairway.move(to: CGPoint(x: size.width * 0.43, y: horizon))
            fairway.addLine(to: CGPoint(x: size.width * 0.28, y: size.height))
            fairway.addLine(to: CGPoint(x: size.width * 0.82, y: size.height))
            fairway.addLine(to: CGPoint(x: size.width * 0.57, y: horizon))
            fairway.closeSubpath()
            context.fill(fairway, with: .color(RondeReviewDesign.fairway.opacity(0.13)))

            var arc = Path()
            arc.move(to: CGPoint(x: size.width * 0.20, y: size.height * 0.76))
            arc.addQuadCurve(
                to: CGPoint(x: size.width * 0.76, y: size.height * 0.28),
                control: CGPoint(x: size.width * 0.45, y: -size.height * 0.02)
            )
            context.stroke(
                arc,
                with: .color(RondeReviewDesign.tracerPurple),
                style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [5, 5])
            )

            let ball = CGPoint(x: size.width * 0.20, y: size.height * 0.76)
            context.fill(Circle().path(in: CGRect(x: ball.x - 4, y: ball.y - 4, width: 8, height: 8)), with: .color(RondeReviewDesign.surface))
            context.stroke(Circle().path(in: CGRect(x: ball.x - 4, y: ball.y - 4, width: 8, height: 8)), with: .color(RondeReviewDesign.fairway), lineWidth: 1)
        }
        .accessibilityHidden(true)
    }
}

struct SettingsPlaceholderView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Settings")
                    .font(.reviewerTitle)
                    .foregroundStyle(RondeReviewDesign.graphite)
                Text("Analysis stays on this device. Camera capture, detector confidence and export controls remain explicit about what is available on this device.")
                    .font(.body)
                    .foregroundStyle(RondeReviewDesign.graphiteMuted)
                    .reviewCard()
            }
            .frame(maxWidth: 680, alignment: .leading)
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}

private func formatDuration(_ seconds: TimeInterval) -> String {
    guard seconds.isFinite, seconds > 0 else { return "0:00" }
    let total = Int(seconds.rounded())
    return String(format: "%d:%02d", total / 60, total % 60)
}

struct RangeSessionEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: ReviewerStore
    let intent: ReviewLaunchIntent
    @State private var selectedSource: PhotosPickerItem?
    @State private var isImporterPresented = false
    @State private var entryTab: RangeEntryTab = .importVideo
    @State private var isLoading = false
    @State private var importError: String?
    @State private var fixedCameraConfirmed = false
    @State private var targetGolferConfirmed = false
    @State private var singleGolferConfirmed = false
    let onImported: (ReviewSession) -> Void

    enum RangeEntryTab: String, CaseIterable, Identifiable {
        case importVideo
        case record

        var id: String { rawValue }

        var title: String {
            switch self {
            case .importVideo: return "Import"
            case .record: return "Record"
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    entryHeader

                    if intent != .oneShot {
                        Text("IMPORT A SESSION")
                            .font(.reviewerSection)
                            .tracking(1.3)
                            .foregroundStyle(RondeReviewDesign.graphiteFaint)
                    }

                    importPanel

                    if let importError {
                        Label(importError, systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(RondeReviewDesign.red)
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RondeReviewDesign.redWash, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
                .frame(maxWidth: 700, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .reviewCanvasBackground()
            .navigationTitle(intent == .oneShot ? "Shot Video" : "Range Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .fileImporter(
                isPresented: $isImporterPresented,
                allowedContentTypes: [.movie, .mpeg4Movie, .quickTimeMovie],
                allowsMultipleSelection: false
            ) { result in
                handleFileImport(result)
            }
            .onChange(of: selectedSource) { _, item in
                guard let item else { return }
                Task { await loadPhotoSelection(item) }
            }
        }
        .preferredColorScheme(.light)
    }

    private var entryHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: intent == .oneShot ? "play.rectangle.fill" : "film.stack")
                    .foregroundStyle(RondeReviewDesign.tracerPurple)
                Text(intent == .oneShot ? "Shot video" : "Range session")
            }
            .font(.reviewerSection)
            .tracking(1.2)
            .foregroundStyle(RondeReviewDesign.fairway)
            Text(intent == .oneShot ? "One video. One shot." : "Review the session that matters.")
                .font(.reviewerTitle)
                .foregroundStyle(RondeReviewDesign.graphite)
            Text(intent == .oneShot
                 ? "Choose a shot video up to 1 minute. Ronde keeps the complete clip and finds impact timing automatically."
                 : "Potential moments are reviewed locally. Only supported shots earn a tracer; the rest stay in the queue.")
                .font(.subheadline)
                .foregroundStyle(RondeReviewDesign.graphiteMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var importPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Label("Choose a recording", systemImage: "video.badge.plus")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(RondeReviewDesign.graphite)
                Text("Photos or Files · H.264 and HEVC first")
                    .font(.footnote)
                    .foregroundStyle(RondeReviewDesign.graphiteMuted)
            }

            if intent == .range {
                rangeEvidenceChecklist
            }

            HStack(spacing: 10) {
                PhotosPicker(selection: $selectedSource, matching: .videos) {
                    Label("Photos", systemImage: "photo.on.rectangle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(ReviewPrimaryButtonStyle())
                .disabled(isLoading || !canImportRangeSession)

                Button {
                    isImporterPresented = true
                } label: {
                    Label("Files", systemImage: "folder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(ReviewSecondaryButtonStyle())
                .disabled(isLoading || !canImportRangeSession)
            }

            if intent == .range, !canImportRangeSession {
                Text("Confirm all three conditions before Ronde can assess a range session.")
                    .font(.caption)
                    .foregroundStyle(RondeReviewDesign.amber)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if isLoading {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        ProgressView()
                            .tint(RondeReviewDesign.fairway)
                        Text(analysisStage.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(RondeReviewDesign.graphite)
                    }
                    ProgressView(value: analysisProgress)
                        .tint(RondeReviewDesign.fairway)
                        .accessibilityLabel("Analysis progress")
                    Text(analysisStage.detail)
                        .font(.caption)
                        .foregroundStyle(RondeReviewDesign.graphiteMuted)
                }
            }
        }
        .reviewCard()
    }

    private var canImportRangeSession: Bool {
        intent != .range || (fixedCameraConfirmed && targetGolferConfirmed && singleGolferConfirmed)
    }

    private var rangeEvidenceChecklist: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SHOT ASSOCIATION")
                .font(.reviewerSection)
                .tracking(1.2)
                .foregroundStyle(RondeReviewDesign.fairway)
            Text("For automatic range review, confirm the footage setup.")
                .font(.caption)
                .foregroundStyle(RondeReviewDesign.graphiteMuted)

            RangeEvidenceToggle(
                title: "Camera is fixed or braced",
                isOn: $fixedCameraConfirmed,
                hint: "The phone stays still through the shot"
            )
            RangeEvidenceToggle(
                title: "I am the target golfer",
                isOn: $targetGolferConfirmed,
                hint: "The intended golfer remains in frame"
            )
            RangeEvidenceToggle(
                title: "No other golfer is in frame",
                isOn: $singleGolferConfirmed,
                hint: "Ronde will not infer which golfer launched the ball"
            )
        }
        .padding(11)
        .background(RondeReviewDesign.canvas, in: RoundedRectangle(cornerRadius: RondeReviewDesign.smallRadius, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    private var recordPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Record a range session", systemImage: "camera")
                .font(.body.weight(.bold))
                .foregroundStyle(RondeReviewDesign.graphite)
            Text("In-app range recording is not available in this build. Import footage from Photos or Files to begin a review.")
                .font(.body)
                .foregroundStyle(RondeReviewDesign.graphiteMuted)
            Button {
                entryTab = .importVideo
            } label: {
                Label("Back to Import", systemImage: "arrow.left.circle")
            }
            .buttonStyle(ReviewSecondaryButtonStyle(tint: RondeReviewDesign.blue))
        }
        .reviewCard()
    }

    private var analysisProgress: Double {
        min(max(store.selectedSession?.progress ?? 0, 0), 1)
    }

    private var analysisStage: (title: String, detail: String) {
        switch analysisProgress {
        case ..<0.2:
            return ("Preparing", "Keeping the original recording on this device.")
        case ..<0.72:
            return ("Finding launch", "Locating impact and the first visible ball movement.")
        case ..<0.99:
            return ("Tracking the ball", "Following the launch frame by frame on this device.")
        default:
            return ("Ready", "Opening the review surface now.")
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            Task { await importVideo(url: url, sourceName: url.lastPathComponent) }
        case .failure(let error):
            importError = error.localizedDescription
        }
    }

    private func loadPhotoSelection(_ item: PhotosPickerItem) async {
        isLoading = true
        defer { isLoading = false }
        do {
            guard let transferred = try await item.loadTransferable(type: VideoFileTransferable.self) else {
                importError = "Ronde could not read that video. Choose another recording."
                return
            }
            await importVideo(url: transferred.url, sourceName: "Photos recording")
            try? FileManager.default.removeItem(at: transferred.url)
        } catch {
            importError = error.localizedDescription
        }
    }

    private func importVideo(url: URL, sourceName: String) async {
        isLoading = true
        defer { isLoading = false }
        if intent == .range {
            let evidence = FixedCameraSingleGolferSessionEvidence(
                cameraWasFixedForSession: fixedCameraConfirmed,
                targetGolferWasExplicitlyConfirmed: targetGolferConfirmed,
                noOtherGolferWasConfirmedInFrame: singleGolferConfirmed,
                confirmationDescription: "Reviewer confirmed a fixed camera, named target golfer and no other golfer in frame before importing this range session."
            )
            guard store.configureFixedSingleGolferRangeAnalysis(with: evidence) else {
                importError = "Confirm the fixed-camera and single-golfer setup before importing a range session."
                return
            }
        }
        await store.importVideo(
            at: url,
            sourceName: sourceName,
            importKind: intent == .oneShot ? .oneShot : .rangeSession
        )
        if let session = store.selectedSession {
            onImported(session)
        }
        dismiss()
    }
}

struct LiveReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: ReviewerStore
    @StateObject private var capture = LiveCaptureControllerAdapter()
    @State private var hasStarted = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                livePreview
                liveStatusPanel
            }
            .reviewCanvasBackground()
            .navigationTitle("Live Review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        capture.stop()
                        dismiss()
                    }
                }
            }
        }
        .preferredColorScheme(.light)
        .task(id: hasStarted) {
            guard hasStarted else { return }
            await capture.start()
        }
    }

    private var livePreview: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color.black)
                .overlay {
                    VStack(spacing: 10) {
                        Image(systemName: hasStarted ? "camera.viewfinder" : "camera")
                            .font(.system(size: 34, weight: .medium))
                            .foregroundStyle(.white.opacity(0.82))
                        Text(hasStarted ? "Live preview will appear here" : "Set up your camera")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.white)
                        Text("One golfer · fixed camera · foreground only")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.72))
                    }
                    .multilineTextAlignment(.center)
                    .padding(24)
                }
                .overlay {
                    if hasStarted, let previewLayer = capture.previewLayer {
                        CameraPreviewLayerView(previewLayer: previewLayer)
                    }
                }
                .aspectRatio(16 / 10, contentMode: .fit)

            HStack(spacing: 8) {
                Circle()
                    .fill(capture.state == .armed ? RondeReviewDesign.fairwayBright : RondeReviewDesign.amber)
                    .frame(width: 8, height: 8)
                Text(capture.state.title.uppercased())
                    .font(.caption.weight(.bold))
                    .tracking(1.1)
                    .foregroundStyle(.white)
            }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 8)
            .background(.black.opacity(0.52), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .padding(14)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Live status: \(capture.state.title)")
        }
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: RondeReviewDesign.largeRadius, style: .continuous))
        .padding(.horizontal, 14)
        .padding(.top, 12)
    }

    private var liveStatusPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 8) {
                        Text("Hands-free review")
                            .font(.reviewerTitle)
                        ReviewTag("Preview", tint: RondeReviewDesign.amber)
                    }
                    .foregroundStyle(RondeReviewDesign.graphite)
                    Text("Keep one golfer in view. Camera setup is available here; saving and reviewing live shots is still in progress.")
                        .font(.subheadline)
                        .foregroundStyle(RondeReviewDesign.graphiteMuted)
                }

                captureStatusCard

                HStack(spacing: 10) {
                    if !hasStarted {
                        Button {
                            hasStarted = true
                        } label: {
                            Label("Start camera", systemImage: "camera.viewfinder")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(ReviewPrimaryButtonStyle(tint: RondeReviewDesign.fairway))
                    } else {
                        Button {
                            capture.stop()
                            hasStarted = false
                        } label: {
                            Label("Stop and review", systemImage: "stop.circle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(ReviewSecondaryButtonStyle(tint: RondeReviewDesign.red))
                    }
                }

                Label("The app must stay in the foreground while the camera is active. Camera and microphone access are requested only when you start.", systemImage: "lock.shield")
                    .font(.caption)
                    .foregroundStyle(RondeReviewDesign.graphiteMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 700, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .scrollIndicators(.hidden)
    }

    private var captureStatusCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                ReviewTag(capture.state.title, systemImage: stateIcon, tint: RondeReviewDesign.statusColor(for: mappedReviewStatus))
                Spacer()
                if hasStarted {
                    Text("Camera active")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(RondeReviewDesign.graphiteMuted)
                }
            }

            if case .unavailable = capture.state {
                Text("Live camera preview is not available on this device yet. You can return here when camera access is ready.")
                    .font(.subheadline)
                    .foregroundStyle(RondeReviewDesign.graphiteMuted)
                    .fixedSize(horizontal: false, vertical: true)
            } else if case .failed(let message) = capture.state {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(RondeReviewDesign.red)
            } else {
                Text("Your camera is active. Saved live moments will appear here when live clip review is available.")
                    .font(.subheadline)
                    .foregroundStyle(RondeReviewDesign.graphiteMuted)
            }

            Divider().overlay(RondeReviewDesign.border)

            HStack(spacing: 10) {
                LiveQualityValue(title: "Capture", value: capture.captureQuality.framesPerSecond > 0 ? "\(Int(capture.captureQuality.framesPerSecond.rounded())) fps" : "Preparing")
                LiveQualityValue(title: "Stability", value: capture.captureQuality.stability.title)
                LiveQualityValue(title: "Focus", value: capture.captureQuality.focusExposureState.title)
            }

            Text(capture.captureQuality.framingGuidance)
                .font(.caption)
                .foregroundStyle(RondeReviewDesign.graphiteMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .reviewCard()
    }

    private var stateIcon: String {
        switch capture.state {
        case .armed: return "dot.radiowaves.left.and.right"
        case .collectingPostRoll: return "timer"
        case .replaying: return "play.circle"
        case .paused: return "pause.circle"
        case .failed: return "exclamationmark.triangle"
        case .ready: return "checkmark.circle"
        case .unavailable: return "link.badge.plus"
        }
    }

    private var mappedReviewStatus: ReviewStatus {
        switch capture.state {
        case .armed, .collectingPostRoll, .replaying: return .capturing
        case .paused: return .paused
        case .failed: return .failed
        case .unavailable: return .needsAttention
        case .ready: return .ready
        }
    }
}

private struct RangeEvidenceToggle: View {
    let title: String
    @Binding var isOn: Bool
    let hint: String

    var body: some View {
        Toggle(isOn: $isOn) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(RondeReviewDesign.graphite)
        }
        .tint(RondeReviewDesign.fairway)
        .accessibilityLabel(title)
        .accessibilityHint(hint)
    }
}

private struct LiveQualityValue: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.system(.caption2, design: .rounded).weight(.bold))
                .tracking(0.7)
                .foregroundStyle(RondeReviewDesign.graphiteFaint)
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(RondeReviewDesign.graphite)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(value)")
    }
}

private extension LiveReviewCaptureStability {
    var title: String {
        switch self {
        case .checking: return "Checking"
        case .steady: return "Steady"
        case .moving: return "Moving"
        case .unavailable: return "Unavailable"
        }
    }
}

private extension LiveReviewCaptureQuality.FocusExposureState {
    var title: String {
        switch self {
        case .settling: return "Settling"
        case .locked: return "Locked"
        case .unavailable: return "Unavailable"
        }
    }
}

struct CameraPreviewLayerView: UIViewRepresentable {
    let previewLayer: AVCaptureVideoPreviewLayer

    func makeUIView(context: Context) -> PreviewContainerView {
        let view = PreviewContainerView()
        view.previewLayer = previewLayer
        return view
    }

    func updateUIView(_ uiView: PreviewContainerView, context: Context) {
        uiView.previewLayer = previewLayer
    }
}

final class PreviewContainerView: UIView {
    var previewLayer: AVCaptureVideoPreviewLayer? {
        didSet {
            oldValue?.removeFromSuperlayer()
            guard let previewLayer else { return }
            layer.addSublayer(previewLayer)
            setNeedsLayout()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer?.frame = bounds
    }
}

struct SessionWorkspaceView: View {
    @ObservedObject var store: ReviewerStore
    let session: ReviewSession

    var body: some View {
        Group {
            switch session.mode {
            case .range:
                RangeReviewWorkspace(store: store, session: session)
            case .live:
                LiveSessionSummaryView(store: store, session: session)
            }
        }
        .reviewCanvasBackground()
    }
}

@MainActor
final class ClipPlaybackController: NSObject, ObservableObject {
    @Published private(set) var player: AVPlayer?
    @Published private(set) var isPlaying = false
    /// The current AVPlayer item time. This is the sole clock for tracer reveal.
    @Published private(set) var currentTime: TimeInterval = 0

    private var periodicTimeObserver: Any?

    func attach(player: AVPlayer) {
        if self.player === player { return }
        removePeriodicTimeObserver()
        NotificationCenter.default.removeObserver(self)
        self.player = player
        currentTime = max(0, player.currentTime().seconds)
        periodicTimeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 1.0 / 60.0, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            Task { @MainActor [weak self] in
                self?.currentTime = max(0, time.seconds)
            }
        }
        if let item = player.currentItem {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(playerItemDidFinish(_:)),
                name: .AVPlayerItemDidPlayToEndTime,
                object: item
            )
        }
    }

    func pause() {
        player?.pause()
        isPlaying = false
    }

    func detach() {
        pause()
        removePeriodicTimeObserver()
        NotificationCenter.default.removeObserver(self)
        player = nil
        currentTime = 0
    }

    func seek(to time: TimeInterval) {
        guard let player else { return }
        player.pause()
        isPlaying = false
        let targetTime = max(0, time)
        player.seek(
            to: CMTime(seconds: targetTime, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        ) { [weak self] finished in
            guard finished else { return }
            DispatchQueue.main.async {
                self?.currentTime = targetTime
            }
        }
    }

    func play(candidate: ReviewCandidate) {
        guard let player, let item = player.currentItem else { return }
        item.forwardPlaybackEndTime = CMTime(seconds: candidate.endTime, preferredTimescale: 600)
        player.seek(
            to: CMTime(seconds: candidate.startTime, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        ) { [weak self, weak player] _ in
            guard let self, let player else { return }
            DispatchQueue.main.async {
                player.play()
                self.isPlaying = true
                self.currentTime = candidate.startTime
            }
        }
    }

    func updateBounds(for candidate: ReviewCandidate) {
        player?.currentItem?.forwardPlaybackEndTime = CMTime(seconds: candidate.endTime, preferredTimescale: 600)
    }

    @objc private func playerItemDidFinish(_ notification: Notification) {
        isPlaying = false
        currentTime = max(0, player?.currentTime().seconds ?? currentTime)
    }

    private func removePeriodicTimeObserver() {
        guard let periodicTimeObserver, let player else { return }
        player.removeTimeObserver(periodicTimeObserver)
        self.periodicTimeObserver = nil
    }
}

struct RangeReviewWorkspace: View {
    @ObservedObject var store: ReviewerStore
    let session: ReviewSession
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isReviewQueueExpanded = false
    @State private var hasAutoPlayedSingleShot = false
    @State private var assistedTracerPoints = AssistedTracerPoints.default
    @State private var isTracerEditing = false
    @State private var isExportingTracer = false
    @State private var exportError: String?
    @State private var exportedTracerURL: URL?
    @StateObject private var playback = ClipPlaybackController()

    private var selectedCandidate: ReviewCandidate? { store.candidate(in: session) }
    private var isSingleShotReview: Bool { session.isSingleShotImport }

    var body: some View {
        ScrollView {
            Group {
                if horizontalSizeClass == .regular {
                    regularWorkspace
                } else {
                    compactWorkspace
                }
            }
            .frame(maxWidth: 1100, alignment: .leading)
            .padding(.horizontal, horizontalSizeClass == .regular ? 24 : 12)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .scrollIndicators(.hidden)
        .navigationTitle(isSingleShotReview ? "Shot review" : session.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            preparePlayer()
            restoreAssistedTracer()
            autoPlaySingleShotIfReady()
        }
        .onChange(of: store.selectedCandidateID) { _, _ in
            isTracerEditing = false
            seekToSelectedCandidate()
            restoreAssistedTracer()
            autoPlaySingleShotIfReady()
        }
        .onChange(of: assistedTracerPoints) { _, points in
            guard let selectedCandidate else { return }
            guard isTracerEditing || selectedCandidate.assistedTracer != nil else { return }
            store.updateAssistedTracer(points.path, for: selectedCandidate, in: session)
        }
        .onChange(of: store.playheadTime) { _, _ in
            if let selectedCandidate {
                playback.updateBounds(for: selectedCandidate)
            }
        }
        .onDisappear {
            playback.detach()
        }
        .sheet(isPresented: Binding(
            get: { exportedTracerURL != nil },
            set: { if !$0 { exportedTracerURL = nil } }
        )) {
            if let exportedTracerURL {
                ActivityShareView(activityItems: [exportedTracerURL])
                    .presentationDetents([.medium, .large])
            }
        }
    }

    private var compactWorkspace: some View {
        VStack(alignment: .leading, spacing: 14) {
            reviewMedia
            if !isSingleShotReview {
                workspaceHeader
            }
            detailColumn
        }
    }

    private var regularWorkspace: some View {
        HStack(alignment: .top, spacing: 22) {
            VStack(alignment: .leading, spacing: 14) {
                reviewMedia
                if !isSingleShotReview {
                    workspaceHeader
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)

            detailColumn
                .frame(width: 370, alignment: .topLeading)
        }
    }

    @ViewBuilder
    private var detailColumn: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let errorMessage = session.errorMessage {
                NeedsAttentionBanner(message: errorMessage)
            }

            candidateQueue

            if let selectedCandidate {
                if isSingleShotReview {
                    quickReviewPanel(for: selectedCandidate)
                } else if selectedCandidate.isAcceptedShot {
                    reviewInspector(for: selectedCandidate)
                } else {
                    reviewQueueInspector(for: selectedCandidate)
                }
            } else {
                EmptyCandidateReviewView(session: session, onAddMarker: { store.addManualMarker(in: session) })
            }
        }
    }

    private var workspaceHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(isSingleShotReview ? "SINGLE SHOT" : "RANGE SESSION")
                    .font(.reviewerSection)
                    .tracking(1.5)
                    .foregroundStyle(RondeReviewDesign.fairway)
                Text(session.sourceName ?? "Local recording")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(RondeReviewDesign.graphite)
                Text(headerMetadata)
                    .font(.subheadline)
                    .foregroundStyle(RondeReviewDesign.graphiteMuted)
            }
            Spacer()
            if !isSingleShotReview {
                ReviewTag(session.status.title, tint: RondeReviewDesign.statusColor(for: session.status))
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var reviewMedia: some View {
        VStack(alignment: .leading, spacing: 10) {
            GeometryReader { geometry in
                let sourceRatio = CGFloat(session.sourceAspectRatio ?? (16.0 / 9.0))
                let fitted = AVMakeRect(
                    aspectRatio: CGSize(width: sourceRatio, height: 1),
                    insideRect: CGRect(origin: .zero, size: geometry.size)
                )

                ZStack {
                    Color.black

                    ZStack {
                        if let player = playback.player {
                            VideoPlayer(player: player)
                                .background(Color.black)
                        } else {
                            VideoPlaceholderView(
                                title: "Video preview",
                                detail: session.sourceURL == nil ? "Connect a source video to scrub this session." : "Your local source is ready to review."
                            )
                        }

                        if let selectedCandidate,
                           tracerIsVisible(for: selectedCandidate),
                           (isSingleShotReview || selectedCandidate.isAcceptedShot || isTracerEditing) {
                            PlayerSynchronizedTracer(
                                player: playback.player,
                                points: $assistedTracerPoints,
                                inferredLaunchPoints: inferredLaunchTracerPoints(for: selectedCandidate),
                                observedPoints: observedTracerPoints(for: selectedCandidate),
                                observedPresentationTimes: selectedCandidate.evidenceAnchoredPath?.observedPresentationTimes
                                    ?? selectedCandidate.trajectory?.presentationTimes
                                    ?? [],
                                inferredPoints: inferredTracerPoints(for: selectedCandidate),
                                automaticApex: selectedCandidate.evidenceAnchoredPath?.apexPoint,
                                estimatedCarry: selectedCandidate.evidenceAnchoredPath?.estimatedCarry,
                                fallbackPlaybackTime: playback.player == nil && session.sourceURL == nil
                                    ? tracerRevealStartTime + tracerFlightDuration
                                    : playback.currentTime,
                                impactTime: tracerRevealStartTime,
                                flightDuration: tracerFlightDuration,
                                isEditing: isTracerEditing,
                                isManual: selectedCandidate.hasManualTracer,
                                onFinishEditing: finishTracerEditing
                            )
                        }
                    }
                    .frame(width: fitted.width, height: fitted.height)
                }
            }
            .frame(height: mediaStageHeight)
            .clipShape(RoundedRectangle(cornerRadius: RondeReviewDesign.largeRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: RondeReviewDesign.largeRadius, style: .continuous)
                    .stroke(.white.opacity(0.24), lineWidth: 0.8)
            }
            .shadow(color: RondeReviewDesign.graphite.opacity(0.12), radius: 18, y: 7)

            if let selectedCandidate {
                playbackRail(for: selectedCandidate)
            }

            if !isSingleShotReview {
                TimelineMarkerControl(
                    duration: max(session.duration, 1),
                    playhead: $store.playheadTime,
                    selectedCandidate: selectedCandidate,
                    allowsAddingMarker: true,
                    onAddMarker: { store.addManualMarker(in: session) }
                )
            }
        }
    }

    private var mediaStageHeight: CGFloat {
        let isPortrait = (session.sourceAspectRatio ?? (16.0 / 9.0)) < 1
        if horizontalSizeClass == .regular {
            return isPortrait ? 560 : 340
        }
        return isPortrait ? 470 : 238
    }

    private func playbackRail(for candidate: ReviewCandidate) -> some View {
        HStack(spacing: 11) {
            Button {
                if playback.isPlaying {
                    playback.pause()
                } else {
                    playback.play(candidate: candidate)
                }
            } label: {
                Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(RondeReviewDesign.graphite)
                    .frame(width: 30, height: 30)
                    .background(RondeReviewDesign.tracerPurple, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(playback.player == nil)
            .accessibilityLabel(playback.isPlaying ? "Pause shot" : "Play shot")
            .accessibilityHint(playback.player == nil ? "A source video is needed before playback is available" : "Plays the selected shot")

            Slider(
                value: Binding(
                    get: { min(max(playback.currentTime, candidate.startTime), candidate.endTime) },
                    set: { playback.seek(to: $0) }
                ),
                in: candidate.startTime...max(candidate.startTime + 0.1, candidate.endTime),
                step: 0.05
            )
            .tint(RondeReviewDesign.tracerPurple)
            .disabled(playback.player == nil)
            .accessibilityLabel("Shot playback position")

            Text(formatTimestamp(playback.currentTime))
                .font(.reviewerTimestamp)
                .foregroundStyle(RondeReviewDesign.graphiteMuted)
                .monospacedDigit()
                .frame(minWidth: 52, alignment: .trailing)
        }
        .padding(.horizontal, 3)
        .accessibilityElement(children: .contain)
    }

    private var tracerFlightDuration: TimeInterval {
        guard let selectedCandidate else { return TracerRevealTimeline.defaultFlightDuration }
        if let anchored = selectedCandidate.evidenceAnchoredPath {
            if let estimatedFlightDuration = anchored.estimatedFlightDuration {
                return max(0.18, estimatedFlightDuration)
            }
            let observedDuration: TimeInterval
            if let first = anchored.observedPresentationTimes.first,
               let last = anchored.observedPresentationTimes.last,
               last > first {
                observedDuration = last - first
            } else {
                observedDuration = 0
            }
            return max(0.18, observedDuration + (anchored.inferredContinuation.isEmpty ? 0 : anchored.inferredPresentationDuration))
        }
        if let first = selectedCandidate.trajectory?.presentationTimes.first,
           let last = selectedCandidate.trajectory?.presentationTimes.last,
           last > first {
            return max(0.18, last - first)
        }
        let availablePostImpact = max(0.25, selectedCandidate.endTime - selectedCandidate.impactTime)
        return min(TracerRevealTimeline.defaultFlightDuration, availablePostImpact)
    }

    private var tracerRevealStartTime: TimeInterval {
        guard let selectedCandidate else { return 0 }
        if let path = selectedCandidate.evidenceAnchoredPath,
           !path.inferredLaunchConnector.isEmpty {
            return selectedCandidate.impactTime
        }
        return selectedCandidate.evidenceAnchoredPath?.observedPresentationTimes.first
            ?? selectedCandidate.trajectory?.presentationTimes.first
            ?? selectedCandidate.impactTime
    }

    @ViewBuilder
    private var candidateQueue: some View {
        if !isSingleShotReview {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("LIKELY SHOTS")
                        .font(.reviewerSection)
                        .tracking(1.4)
                        .foregroundStyle(RondeReviewDesign.fairway)
                    Spacer()
                    Text(session.acceptedShots.isEmpty ? "None confirmed" : "\(session.acceptedShots.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(RondeReviewDesign.graphiteMuted)
                }

                if session.acceptedShots.isEmpty {
                    Text("No shots confirmed yet. Potential moments stay out of the tracer rail, and the original recording remains preserved on this device.")
                        .font(.subheadline)
                        .foregroundStyle(RondeReviewDesign.graphiteMuted)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 7) {
                            ForEach(session.acceptedShots) { candidate in
                                Button { selectCandidate(candidate) } label: {
                                    CandidateQueueCard(candidate: candidate, isSelected: candidate.id == selectedCandidate?.id)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .accessibilityLabel("Real shot filmstrip")
                }

                if !session.reviewQueue.isEmpty {
                    Button {
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
                            isReviewQueueExpanded.toggle()
                        }
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: "line.3.horizontal.decrease.circle")
                            Text("Review queue")
                            Text("\(session.reviewQueue.count)")
                                .font(.caption.weight(.bold))
                            Spacer()
                            Image(systemName: "chevron.down")
                                .rotationEffect(.degrees(isReviewQueueExpanded ? 180 : 0))
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(RondeReviewDesign.graphiteMuted)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Practice swings and uncertain moments are kept here without tracers")

                    if isReviewQueueExpanded {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 7) {
                                ForEach(session.reviewQueue) { candidate in
                                    Button { selectCandidate(candidate) } label: {
                                        CandidateQueueCard(candidate: candidate, isSelected: candidate.id == selectedCandidate?.id)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            }
        }
    }

    private func quickReviewPanel(for candidate: ReviewCandidate) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 12) {
                Label(tracerTitle(for: candidate), systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                    .font(.headline)
                    .foregroundStyle(RondeReviewDesign.graphite)
                Spacer(minLength: 12)
                ReviewTag(
                    tracerSourceTitle(for: candidate),
                    systemImage: tracerSourceIcon(for: candidate),
                    tint: tracerSourceTint(for: candidate)
                )
            }

            tracerActionRow(for: candidate)

            if candidate.hasAutomaticTracer || candidate.hasManualTracer {
                exportActions(for: candidate)
            }

            Text(tracerExplanation(for: candidate))
                .font(.caption)
                .foregroundStyle(RondeReviewDesign.graphiteMuted)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
    }

    private func tracerActionRow(for candidate: ReviewCandidate) -> some View {
        let actionTitle = candidate.hasManualTracer ? "Edit trace" : (candidate.hasAutomaticTracer ? "Adjust trace" : "Place trace")
        return HStack(spacing: 10) {
            Button {
                beginTracerEditing(for: candidate)
            } label: {
                Label(
                    isTracerEditing ? "Adjusting" : actionTitle,
                    systemImage: isTracerEditing ? "hand.draw.fill" : "pencil.and.outline"
                )
            }
            .buttonStyle(ReviewSecondaryButtonStyle(tint: RondeReviewDesign.fairway))
            .disabled(isTracerEditing)
            .accessibilityHint(candidate.hasManualTracer ? "Adjust your manual trace" : "Place a manual trace over the video")

            Spacer(minLength: 8)

            if candidate.hasManualTracer, candidate.hasAutomaticTracer {
                Button {
                    store.clearManualTracer(for: candidate, in: session)
                    restoreAssistedTracer()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(RondeReviewDesign.graphiteMuted)
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Use automatic trace")
                .accessibilityHint("Removes your manual adjustment and restores the observed path")
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .contain)
    }

    private func exportActions(for candidate: ReviewCandidate) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 10) {
                Button {
                    Task { await exportTracer(for: candidate) }
                } label: {
                    Label(isExportingTracer ? "Rendering…" : "Export trace", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(ReviewSecondaryButtonStyle(tint: RondeReviewDesign.graphite))
                .disabled(isExportingTracer || (!candidate.hasAutomaticTracer && !candidate.hasManualTracer))
                .accessibilityHint("Renders this same trace over the source video, then opens the share sheet")

                if isExportingTracer {
                    ProgressView()
                        .controlSize(.small)
                        .tint(RondeReviewDesign.fairway)
                        .accessibilityLabel("Rendering traced video")
                }
            }

            if let exportError {
                Label(exportError, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(RondeReviewDesign.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func exportTracer(for candidate: ReviewCandidate) async {
        guard !isExportingTracer else { return }
        isExportingTracer = true
        exportError = nil
        defer { isExportingTracer = false }

        do {
            exportedTracerURL = try await store.exportTracedVideo(for: candidate, in: session)
        } catch {
            exportError = error.localizedDescription
        }
    }

    private func reviewInspector(for candidate: ReviewCandidate) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Shot \(candidate.ordinal)")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(RondeReviewDesign.graphite)
                    Text("\(formatTimestamp(candidate.startTime)) – \(formatTimestamp(candidate.endTime))")
                        .font(.reviewerTimestamp)
                        .foregroundStyle(RondeReviewDesign.graphiteMuted)
                }
                Spacer()
                ReviewTag(candidate.classification.title, systemImage: candidate.classification.icon, tint: RondeReviewDesign.classificationColor(for: candidate.classification))
            }

            HStack(spacing: 8) {
                ReviewTag(candidate.confidence.title, systemImage: "gauge.with.dots.needle.67percent", tint: RondeReviewDesign.graphiteMuted)
                ReviewTag(
                    tracerSourceTitle(for: candidate),
                    systemImage: tracerSourceIcon(for: candidate),
                    tint: tracerSourceTint(for: candidate)
                )
            }

            tracerActionRow(for: candidate)

            if candidate.hasAutomaticTracer || candidate.hasManualTracer {
                exportActions(for: candidate)
            }

            if !candidate.evidence.isEmpty {
                FlowEvidenceView(evidence: candidate.evidence)
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 9) { decisionButtons(for: candidate) }
                VStack(alignment: .leading, spacing: 8) { decisionButtons(for: candidate) }
            }

            Divider().overlay(RondeReviewDesign.border)

            VStack(alignment: .leading, spacing: 10) {
                Text("TRIM WINDOW")
                    .font(.reviewerSection)
                    .tracking(1.3)
                    .foregroundStyle(RondeReviewDesign.graphiteFaint)
                Text("Ronde centres a 10-second clip on the estimated impact: 5 seconds before and 5 seconds after. The range is shortened at source boundaries.")
                    .font(.subheadline)
                    .foregroundStyle(RondeReviewDesign.graphiteMuted)
                Slider(
                    value: Binding(
                        get: { candidate.impactTime },
                        set: { store.updateImpactTime($0, for: candidate, in: session) }
                    ),
                    in: 0...max(session.duration, 1),
                    step: 0.1
                )
                .tint(RondeReviewDesign.fairway)
                .accessibilityLabel("Impact position")
                HStack {
                    Text("Impact \(formatTimestamp(candidate.impactTime))")
                    Spacer()
                    Text("Clip \(formatTimestamp(candidate.startTime)) – \(formatTimestamp(candidate.endTime))")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(RondeReviewDesign.graphiteMuted)
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 9) { reviewTools(for: candidate) }
                VStack(alignment: .leading, spacing: 8) { reviewTools(for: candidate) }
            }
            Text(tracerExplanation(for: candidate))
                .font(.caption.weight(.semibold))
                .foregroundStyle(RondeReviewDesign.graphiteMuted)
        }
        .reviewCard()
    }

    private func reviewQueueInspector(for candidate: ReviewCandidate) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: candidate.classification.icon)
                    .font(.title3)
                    .foregroundStyle(RondeReviewDesign.classificationColor(for: candidate.classification))
                VStack(alignment: .leading, spacing: 3) {
                    Text(candidate.classification == .practice ? "Practice swing" : "Uncertain moment")
                        .font(.headline)
                        .foregroundStyle(RondeReviewDesign.graphite)
                    Text("Around \(formatTimestamp(candidate.impactTime))")
                        .font(.caption)
                        .foregroundStyle(RondeReviewDesign.graphiteMuted)
                }
                Spacer()
            }

                Text("This potential moment stays out of the shot rail and has no tracer. Review it only if you want to correct the analysis.")
                .font(.subheadline)
                .foregroundStyle(RondeReviewDesign.graphiteMuted)

            HStack(spacing: 8) {
                Button {
                    store.setClassification(.likelyShot, for: candidate, in: session)
                    store.setDecision(.unreviewed, for: candidate, in: session)
                } label: {
                    Label("Mark as shot", systemImage: "checkmark")
                }
                .buttonStyle(ReviewSecondaryButtonStyle(tint: RondeReviewDesign.fairway))

                Button {
                    store.setDecision(.rejected, for: candidate, in: session)
                } label: {
                    Image(systemName: "xmark")
                        .accessibilityLabel("Dismiss moment")
                }
                .buttonStyle(ReviewSecondaryButtonStyle(tint: RondeReviewDesign.graphiteMuted))
            }
        }
        .reviewCard(cardPadding: 14)
    }

    @ViewBuilder
    private func decisionButtons(for candidate: ReviewCandidate) -> some View {
        Button {
            store.setDecision(.kept, for: candidate, in: session)
        } label: {
            Label("Keep shot", systemImage: "checkmark")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(ReviewPrimaryButtonStyle())

        Button {
            store.setDecision(.rejected, for: candidate, in: session)
        } label: {
            Label("Mark practice", systemImage: "figure.golf")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(ReviewSecondaryButtonStyle(tint: RondeReviewDesign.graphiteMuted))

        Button {
            store.setDecision(.unreviewed, for: candidate, in: session)
        } label: {
            Label("Review later", systemImage: "clock.arrow.circlepath")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(ReviewSecondaryButtonStyle(tint: RondeReviewDesign.amber))
    }

    @ViewBuilder
    private func reviewTools(for candidate: ReviewCandidate) -> some View {
        Button {
            if playback.isPlaying {
                playback.pause()
            } else {
                playback.play(candidate: candidate)
            }
        } label: {
            Label(playback.isPlaying ? "Pause clip" : "Play review clip", systemImage: playback.isPlaying ? "pause.circle" : "play.circle")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(ReviewSecondaryButtonStyle(tint: RondeReviewDesign.graphite))
        .disabled(playback.player == nil)
        .accessibilityHint(playback.player == nil ? "A source video is needed before playback is available" : playback.isPlaying ? "Pauses the clip without restarting it" : "Plays from 5 seconds before to 5 seconds after the estimated impact")

    }

    @ViewBuilder
    private func singleShotControls(for candidate: ReviewCandidate) -> some View {
        Button {
            if playback.isPlaying {
                playback.pause()
            } else {
                playback.play(candidate: candidate)
            }
        } label: {
            Label(playback.isPlaying ? "Pause" : "Replay shot", systemImage: playback.isPlaying ? "pause.fill" : "play.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(ReviewPrimaryButtonStyle())
        .disabled(playback.player == nil)

    }

    private func tracerTitle(for candidate: ReviewCandidate) -> String {
        if candidate.hasManualTracer {
            return "Manual flight path"
        }
        switch candidate.tracerSource {
        case .unavailable: return "Ball flight not tracked"
        case .observed: return "Tracked ball flight"
        case .observedAndInferred: return "Observed ball · estimated full flight"
        case .inferred: return "Estimated shot tracer"
        }
    }

    private func tracerSourceTitle(for candidate: ReviewCandidate) -> String {
        if candidate.hasManualTracer {
            return "Manual trace"
        }
        switch candidate.tracerSource {
        case .unavailable: return "No tracer"
        case .observed: return "Observed"
        case .observedAndInferred: return "Tracked + estimated"
        case .inferred: return "Estimated"
        }
    }

    private func tracerSourceIcon(for candidate: ReviewCandidate) -> String {
        if candidate.hasManualTracer {
            return "pencil.and.outline"
        }
        switch candidate.tracerSource {
        case .unavailable: return "eye.slash"
        case .observed: return "scope"
        case .observedAndInferred: return "scope"
        case .inferred: return "wand.and.stars"
        }
    }

    private func tracerSourceTint(for candidate: ReviewCandidate) -> Color {
        if candidate.hasManualTracer {
            return RondeReviewDesign.fairway
        }
        switch candidate.tracerSource {
        case .unavailable: return RondeReviewDesign.graphiteMuted
        case .observed: return RondeReviewDesign.tracerPurple
        case .observedAndInferred: return RondeReviewDesign.tracerPurple
        case .inferred: return RondeReviewDesign.tracerPurpleSoft
        }
    }

    private func tracerExplanation(for candidate: ReviewCandidate) -> String {
        if candidate.hasManualTracer {
            return "Manual trace placed by you. It is a visual aid, not observed ball flight or a distance estimate."
        }
        switch candidate.tracerSource {
        case .unavailable:
            return "Ronde could not verify enough ball points in these frames, so it has not drawn a misleading line."
        case .observed:
            return "Ball flight tracked from the uploaded frames."
        case .observedAndInferred:
            if let carry = candidate.evidenceAnchoredPath?.estimatedCarry {
                return "Purple solid points were tracked from the video. Dashed launch, apex and landing geometry is estimated. Carry \(carry.displayText) is a rough uncalibrated range, not launch-monitor measurement."
            }
            return "Purple solid points were tracked from the video. Dashed launch, apex and landing geometry is estimated."
        case .inferred:
            return "This is estimated presentation geometry, not observed ball flight or a distance measurement."
        }
    }

    private var headerMetadata: String {
        let duration = session.duration > 0 ? formatDuration(session.duration) : "duration pending"
        if isSingleShotReview {
            let tracer: String
            if let selectedCandidate, selectedCandidate.hasManualTracer {
                tracer = "manual trace"
            } else {
                tracer = selectedCandidate?.tracerAvailable == true ? "tracked tracer" : "no verified tracer"
            }
            return "\(duration) · shot video · \(tracer)"
        }
        let shots = session.acceptedShots.count == 1 ? "1 likely shot" : "\(session.acceptedShots.count) likely shots"
        return "\(duration) · \(shots)"
    }

    private func preparePlayer() {
        guard playback.player == nil, let url = session.sourceURL else {
            seekToSelectedCandidate()
            return
        }
        playback.attach(player: AVPlayer(url: url))
        seekToSelectedCandidate()
    }

    private func autoPlaySingleShotIfReady() {
        guard isSingleShotReview,
              !hasAutoPlayedSingleShot,
              playback.player != nil,
              let selectedCandidate else { return }
        hasAutoPlayedSingleShot = true
        playback.play(candidate: selectedCandidate)
    }

    private func selectCandidate(_ candidate: ReviewCandidate) {
        store.selectCandidate(candidate)
        playback.seek(to: candidate.startTime)
    }

    private func seekToSelectedCandidate() {
        guard let selectedCandidate else { return }
        playback.seek(to: selectedCandidate.startTime)
    }

    private func restoreAssistedTracer() {
        guard let selectedCandidate,
              let path = selectedCandidate.assistedTracer else {
            assistedTracerPoints = .default
            return
        }
        assistedTracerPoints = AssistedTracerPoints(path: path)
    }

    private func tracerIsVisible(for candidate: ReviewCandidate) -> Bool {
        isTracerEditing || candidate.hasAutomaticTracer || candidate.hasManualTracer
    }

    private func observedTracerPoints(for candidate: ReviewCandidate) -> [NormalizedPoint] {
        candidate.evidenceAnchoredPath?.observedPoints ?? candidate.trajectory?.detectedPoints ?? []
    }

    private func inferredLaunchTracerPoints(for candidate: ReviewCandidate) -> [NormalizedPoint] {
        candidate.evidenceAnchoredPath?.inferredLaunchConnector ?? []
    }

    private func inferredTracerPoints(for candidate: ReviewCandidate) -> [NormalizedPoint] {
        candidate.evidenceAnchoredPath?.inferredContinuation ?? candidate.trajectory?.projectedPoints ?? []
    }

    private func beginTracerEditing(for candidate: ReviewCandidate) {
        if store.selectedCandidateID != candidate.id {
            store.selectCandidate(candidate)
        }
        assistedTracerPoints = manualTracerPoints(for: candidate)
        isTracerEditing = true
        store.updateAssistedTracer(assistedTracerPoints.path, for: candidate, in: session)
        playback.pause()
    }

    private func manualTracerPoints(for candidate: ReviewCandidate) -> AssistedTracerPoints {
        if let path = candidate.assistedTracer {
            return AssistedTracerPoints(path: path)
        }
        guard let automatic = candidate.evidenceAnchoredPath,
              let launch = (automatic.inferredLaunchConnector.first ?? automatic.observedPoints.first),
              let endpoint = (automatic.inferredContinuation.last ?? automatic.observedPoints.last) else {
            return .default
        }
        let apex = automatic.apexPoint ?? launch
        return AssistedTracerPoints(
            launch: CGPoint(x: launch.x, y: launch.y),
            apex: CGPoint(x: apex.x, y: apex.y),
            landing: CGPoint(x: endpoint.x, y: endpoint.y)
        )
    }

    private func finishTracerEditing() {
        isTracerEditing = false
    }
}

struct LiveSessionSummaryView: View {
    @ObservedObject var store: ReviewerStore
    let session: ReviewSession

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Live Review")
                    .font(.reviewerTitle)
                    .foregroundStyle(RondeReviewDesign.graphite)
                Text("Saved live moments will appear here when live clip review is available.")
                    .font(.body)
                    .foregroundStyle(RondeReviewDesign.graphiteMuted)
                NeedsAttentionBanner(message: session.errorMessage ?? "No finalised segments have arrived yet.")
                Button("Start another Live Review") {
                    _ = store.addLivePlaceholder()
                }
                .buttonStyle(ReviewPrimaryButtonStyle())
            }
            .frame(maxWidth: 680, alignment: .leading)
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .navigationTitle("Live Review")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct VideoPlaceholderView: View {
    let title: String
    let detail: String

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.10, green: 0.16, blue: 0.14), Color(red: 0.23, green: 0.32, blue: 0.23)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            VStack(spacing: 9) {
                Image(systemName: "play.rectangle")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(.white.opacity(0.84))
                Text(title)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.72))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 240)
            }
            .padding(20)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Video preview. \(detail)")
    }
}

struct TrajectoryOverlay: View {
    let trajectory: DetectedTrajectory

    var body: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                let detected = trajectory.detectedPoints.map { map($0, in: size) }
                let projected = trajectory.projectedPoints.map { map($0, in: size) }

                drawPath(detected, in: &context, colour: .white, width: 8)
                drawPath(detected, in: &context, colour: RondeReviewDesign.fairwayBright, width: 4)
                drawPath(
                    projected,
                    in: &context,
                    colour: RondeReviewDesign.tracerPurpleSoft,
                    width: 3,
                    dash: [7, 6]
                )

                if let first = detected.first {
                    context.fill(Circle().path(in: CGRect(x: first.x - 5, y: first.y - 5, width: 10, height: 10)), with: .color(.white))
                    context.fill(Circle().path(in: CGRect(x: first.x - 3, y: first.y - 3, width: 6, height: 6)), with: .color(RondeReviewDesign.fairway))
                }
                if let end = projected.last ?? detected.last {
                    context.fill(Circle().path(in: CGRect(x: end.x - 5, y: end.y - 5, width: 10, height: 10)), with: .color(.white))
                    context.fill(Circle().path(in: CGRect(x: end.x - 3, y: end.y - 3, width: 6, height: 6)), with: .color(RondeReviewDesign.tracerPurple))
                }
            }
            .overlay(alignment: .topTrailing) {
                Text(trajectory.projectedPoints.isEmpty ? "OBSERVED" : "OBSERVED LAUNCH · ESTIMATED FLIGHT")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(0.8)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 7)
                    .background(.black.opacity(0.62), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .padding(12)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(trajectory.projectedPoints.isEmpty
                        ? "Observed ball flight from the uploaded frames."
                        : "Observed launch followed by an estimated flight continuation.")
            }
        }
    }

    private func map(_ point: NormalizedPoint, in size: CGSize) -> CGPoint {
        VisionVideoCoordinateMapper.swiftUIPoint(from: point, in: size)
    }

    private func drawPath(
        _ points: [CGPoint],
        in context: inout GraphicsContext,
        colour: Color,
        width: CGFloat,
        dash: [CGFloat] = []
    ) {
        guard points.count > 1 else { return }
        var path = Path()
        path.move(to: points[0])
        for point in points.dropFirst() { path.addLine(to: point) }
        context.stroke(
            path,
            with: .color(colour),
            style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round, dash: dash)
        )
    }
}

enum VisionVideoCoordinateMapper {
    static func swiftUIPoint(from point: NormalizedPoint, in size: CGSize) -> CGPoint {
        // Vision normalised points use a bottom-left origin; SwiftUI Canvas
        // uses a top-left origin, so invert Y for the video overlay.
        CGPoint(x: CGFloat(point.x) * size.width, y: (1 - CGFloat(point.y)) * size.height)
    }
}

struct CandidateQueueCard: View {
    let candidate: ReviewCandidate
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                Capsule()
                    .fill(isSelected ? RondeReviewDesign.tracerPurple : RondeReviewDesign.classificationColor(for: candidate.classification))
                    .frame(width: 24, height: 4)
                Spacer(minLength: 4)
                Image(systemName: candidate.classification.icon)
                    .foregroundStyle(RondeReviewDesign.classificationColor(for: candidate.classification))
            }
            Text("Shot \(candidate.ordinal)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(RondeReviewDesign.graphiteMuted)
            Text(formatTimestamp(candidate.impactTime))
                .font(.reviewerTimestamp)
                .foregroundStyle(RondeReviewDesign.graphite)
        }
        .frame(width: 104, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(isSelected ? RondeReviewDesign.fairwayWash.opacity(0.58) : RondeReviewDesign.surface.opacity(0.55), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isSelected ? RondeReviewDesign.fairway : RondeReviewDesign.border, lineWidth: isSelected ? 1.2 : 0.8)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Shot \(candidate.ordinal), \(formatTimestamp(candidate.impactTime)), \(candidate.classification.title)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct FlowEvidenceView: View {
    let evidence: [String]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(evidence, id: \.self) { item in
                    Text(item)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(RondeReviewDesign.graphiteMuted)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 7)
                        .background(RondeReviewDesign.canvas, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
            }
        }
    }
}

struct NeedsAttentionBanner: View {
    let message: String

    var body: some View {
        Label {
            Text(message)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(RondeReviewDesign.amber)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RondeReviewDesign.amberWash, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isStaticText)
    }
}

struct EmptyCandidateReviewView: View {
    let session: ReviewSession
    let onAddMarker: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("MANUAL REVIEW")
                .font(.reviewerSection)
                .tracking(1.3)
                .foregroundStyle(RondeReviewDesign.blue)
            Text("No shots confirmed yet")
                .font(.reviewerTitle)
                .foregroundStyle(RondeReviewDesign.graphite)
            Text("No shots were confirmed in this recording. The original video remains preserved on this device. Move the playhead to a moment you want to review and add a marker.")
                .font(.body)
                .foregroundStyle(RondeReviewDesign.graphiteMuted)
            Button("Add marker at playhead", action: onAddMarker)
                .buttonStyle(ReviewSecondaryButtonStyle(tint: RondeReviewDesign.blue))
        }
        .reviewCard()
    }
}

struct TimelineMarkerControl: View {
    let duration: TimeInterval
    @Binding var playhead: TimeInterval
    let selectedCandidate: ReviewCandidate?
    let allowsAddingMarker: Bool
    let onAddMarker: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("TIMELINE")
                    .font(.reviewerSection)
                    .tracking(1.3)
                    .foregroundStyle(RondeReviewDesign.graphiteFaint)
                Spacer()
                Text(formatTimestamp(playhead))
                    .font(.reviewerTimestamp)
                    .foregroundStyle(RondeReviewDesign.graphiteMuted)
            }
            Slider(value: $playhead, in: 0...max(duration, 1), step: 0.1)
                .tint(RondeReviewDesign.fairway)
                .accessibilityLabel("Video playhead")
            HStack {
                Text("0:00")
                Spacer()
                Text(formatDuration(duration))
            }
            .font(.caption)
            .foregroundStyle(RondeReviewDesign.graphiteFaint)
            if allowsAddingMarker {
                Button {
                    onAddMarker()
                } label: {
                    Label(selectedCandidate == nil ? "Add shot marker" : "Add another shot", systemImage: "plus")
                }
                .buttonStyle(ReviewSecondaryButtonStyle(tint: RondeReviewDesign.blue))
            }
        }
        .reviewCard(cardPadding: 13)
    }
}

private func formatTimestamp(_ seconds: TimeInterval) -> String {
    let safe = max(0, seconds.isFinite ? seconds : 0)
    let total = Int(safe.rounded())
    return String(format: "%02d:%02d", total / 60, total % 60)
}

/// Native share surface for traced videos. Rendering happens in the store so
/// the exported asset uses the same geometry the reviewer displays.
struct ActivityShareView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
        controller.modalPresentationStyle = .pageSheet
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
