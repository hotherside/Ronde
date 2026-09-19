import AVFoundation
import CoreTransferable
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Entry point for adding a longer source recording to a Clubhouse session.
///
/// The view deliberately owns only the picker and import lifecycle. Recording analysis,
/// account ownership checks and durable local storage remain in `ReviewerStore`.
struct RecordingImportView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: ReviewerStore
    var groupID: UUID? = nil
    var groupTitle: String? = nil
    let onImported: (ReviewSession) -> Void

    @State private var selectedSource: PhotosPickerItem?
    @State private var showsPhotosPicker = false
    @State private var showsFileImporter = false
    @State private var showsCamera = false
    @State private var isPreparing = false
    @State private var importError: String?
    @State private var ownership: ReviewImportOwnership?
    @State private var importTask: Task<Void, Never>?
    @State private var didPrepare = false
    @State private var sessionTitle: String

    private static var defaultSessionTitle: String {
        let weekday = Date.now.formatted(.dateTime.weekday(.wide))
        return weekday.isEmpty ? "New session" : "\(weekday) at the range"
    }

    private var isCreatingGroup: Bool {
        groupID == nil && groupTitle?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false
    }

    private var resolvedGroupTitle: String? {
        if let groupTitle {
            let cleaned = groupTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty { return String(cleaned.prefix(160)) }
        }
        guard isCreatingGroup else { return nil }
        let cleaned = sessionTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return String((cleaned.isEmpty ? Self.defaultSessionTitle : cleaned).prefix(160))
    }

    private var displayedGroupTitle: String {
        guard let groupTitle else { return "Existing session" }
        let cleaned = groupTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Existing session" : cleaned
    }

    private var canChooseSource: Bool {
        !isPreparing && store.canModifyLibrary
    }

    private var cameraAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    init(
        store: ReviewerStore,
        groupID: UUID? = nil,
        groupTitle: String? = nil,
        onImported: @escaping (ReviewSession) -> Void
    ) {
        self.store = store
        self.groupID = groupID
        self.groupTitle = groupTitle
        self.onImported = onImported
        _selectedSource = State(initialValue: nil)
        _sessionTitle = State(initialValue: Self.defaultSessionTitle)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    sessionDetails
                    sourceActions

                    if isPreparing {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Preparing your recording…")
                                .font(.body.weight(.medium))
                                .foregroundStyle(RondeReviewDesign.graphite)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(RondeReviewDesign.surfaceInset, in: RoundedRectangle(cornerRadius: RondeReviewDesign.controlRadius, style: .continuous))
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Preparing your recording")
                    }

                    if let importError {
                        errorCard(importError)
                    }

                    Text("The original stays untouched. Ronde keeps the local copy on this device for review.")
                        .font(.footnote)
                        .foregroundStyle(RondeReviewDesign.graphiteMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: 620, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .scrollIndicators(.hidden)
            .reviewCanvasBackground()
            .navigationTitle(isCreatingGroup ? "New session" : "Add recording")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        importTask?.cancel()
                        dismiss()
                    }
                }
            }
            .photosPicker(isPresented: $showsPhotosPicker, selection: $selectedSource, matching: .videos)
            .fileImporter(
                isPresented: $showsFileImporter,
                allowedContentTypes: [.movie, .mpeg4Movie, .quickTimeMovie]
            ) { result in
                switch result {
                case .success(let url):
                    guard let owner = ownership else { return }
                    beginImport(
                        url,
                        sourceName: url.lastPathComponent,
                        ownership: owner,
                        removeSourceAfterImport: false
                    )
                case .failure(let error):
                    guard !(error is CancellationError),
                          (error as? CocoaError)?.code != .userCancelled else { return }
                    importError = error.localizedDescription
                }
            }
            .onChange(of: selectedSource) { _, item in
                guard let item, let owner = ownership else { return }
                beginPhotosImport(item, ownership: owner)
            }
            .fullScreenCover(isPresented: $showsCamera) {
                RecordingCameraPicker(
                    onFinished: { url in
                        showsCamera = false
                        guard let owner = ownership else { return }
                        beginImport(
                            url,
                            sourceName: url.lastPathComponent.isEmpty ? "Camera recording" : url.lastPathComponent,
                            ownership: owner,
                            removeSourceAfterImport: true
                        )
                    },
                    onCancelled: {
                        showsCamera = false
                    }
                )
                .ignoresSafeArea()
            }
        }
        .preferredColorScheme(.light)
        .interactiveDismissDisabled(isPreparing)
        .onDisappear {
            if !didPrepare {
                importTask?.cancel()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label("RECORDING STUDIO", systemImage: "film.stack")
                .font(.reviewerSection)
                .tracking(1.5)
                .foregroundStyle(RondeReviewDesign.fairway)

            Text("Bring the whole session in.")
                .font(.reviewerDisplay)
                .foregroundStyle(RondeReviewDesign.graphite)
                .fixedSize(horizontal: false, vertical: true)

            Text("Add a recording up to 20 minutes, then bookmark the moments worth keeping.")
                .font(.body)
                .foregroundStyle(RondeReviewDesign.graphiteMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var sessionDetails: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(isCreatingGroup ? "SESSION TITLE" : "SESSION")
                .font(.reviewerSection)
                .tracking(1.3)
                .foregroundStyle(RondeReviewDesign.graphiteFaint)

            if isCreatingGroup {
                TextField("Session title", text: $sessionTitle)
                    .font(.body)
                    .textInputAutocapitalization(.sentences)
                    .submitLabel(.done)
                    .padding(.horizontal, 14)
                    .frame(minHeight: RondeReviewDesign.minimumTouchTarget)
                    .background(RondeReviewDesign.surface, in: RoundedRectangle(cornerRadius: RondeReviewDesign.controlRadius, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: RondeReviewDesign.controlRadius, style: .continuous)
                            .strokeBorder(RondeReviewDesign.borderStrong, lineWidth: 0.8)
                    }
                    .accessibilityIdentifier("recording-session-title")
            } else {
                HStack(spacing: 11) {
                    Image(systemName: "rectangle.stack")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(RondeReviewDesign.fairway)
                        .accessibilityHidden(true)
                    Text(displayedGroupTitle)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(RondeReviewDesign.graphite)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                }
                .frame(minHeight: RondeReviewDesign.minimumTouchTarget, alignment: .leading)
                .padding(.horizontal, 14)
                .background(RondeReviewDesign.surfaceInset, in: RoundedRectangle(cornerRadius: RondeReviewDesign.controlRadius, style: .continuous))
                .accessibilityElement(children: .combine)
            }
        }
        .padding(16)
        .background(RondeReviewDesign.surface, in: RoundedRectangle(cornerRadius: RondeReviewDesign.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: RondeReviewDesign.cardRadius, style: .continuous)
                .strokeBorder(RondeReviewDesign.border, lineWidth: 0.8)
        }
    }

    private var sourceActions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ADD RECORDING")
                .font(.reviewerSection)
                .tracking(1.3)
                .foregroundStyle(RondeReviewDesign.graphiteFaint)

            RondeGlassGroup(spacing: 10) {
                VStack(spacing: 10) {
                    VStack(spacing: 10) {
                        Button(action: openPhotos) {
                            Label("Choose from Photos", systemImage: "photo.on.rectangle")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .frame(minHeight: RondeReviewDesign.minimumTouchTarget, alignment: .leading)
                        }
                        .rondePrimaryAction(tint: RondeReviewDesign.fairway)
                        .disabled(!canChooseSource)
                        .accessibilityIdentifier("add-recording-photos")

                        Button(action: openFiles) {
                            Label("Browse Files", systemImage: "folder")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .frame(minHeight: RondeReviewDesign.minimumTouchTarget, alignment: .leading)
                        }
                        .rondeSecondaryAction(tint: RondeReviewDesign.graphite)
                        .disabled(!canChooseSource)
                        .accessibilityIdentifier("add-recording-files")
                    }

                    Button(action: openCamera) {
                        Label("Record with Camera", systemImage: "camera")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(minHeight: RondeReviewDesign.minimumTouchTarget, alignment: .leading)
                    }
                    .rondeSecondaryAction(tint: RondeReviewDesign.graphite)
                    .disabled(!canChooseSource || !cameraAvailable)
                    .accessibilityIdentifier("add-recording-camera")
                }
            }

            Label(
                cameraAvailable ? "The native camera can record up to 20 minutes." : "Camera recording is unavailable on this device.",
                systemImage: cameraAvailable ? "camera.badge.ellipsis" : "camera.slash"
            )
            .font(.footnote)
            .foregroundStyle(RondeReviewDesign.graphiteMuted)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func errorCard(_ message: String) -> some View {
        Label {
            Text(message)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.triangle")
        }
        .font(.body)
        .foregroundStyle(RondeReviewDesign.red)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RondeReviewDesign.redWash, in: RoundedRectangle(cornerRadius: RondeReviewDesign.controlRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: RondeReviewDesign.controlRadius, style: .continuous)
                .strokeBorder(RondeReviewDesign.red.opacity(0.28), lineWidth: 0.8)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Import error: \(message)")
    }

    private func openPhotos() {
        guard let owner = store.captureImportOwnership() else {
            importError = "Open your local library before adding a recording."
            return
        }
        importError = nil
        ownership = owner
        selectedSource = nil
        showsPhotosPicker = true
    }

    private func openFiles() {
        guard let owner = store.captureImportOwnership() else {
            importError = "Open your local library before adding a recording."
            return
        }
        importError = nil
        ownership = owner
        showsFileImporter = true
    }

    private func openCamera() {
        guard cameraAvailable else {
            importError = "Camera recording is unavailable on this device."
            return
        }
        guard let owner = store.captureImportOwnership() else {
            importError = "Open your local library before adding a recording."
            return
        }
        importError = nil
        ownership = owner
        showsCamera = true
    }

    private func beginPhotosImport(_ item: PhotosPickerItem, ownership owner: ReviewImportOwnership) {
        importTask?.cancel()
        importTask = Task { @MainActor in
            isPreparing = true
            importError = nil
            defer { isPreparing = false }

            do {
                guard let transferred = try await item.loadTransferable(type: VideoFileTransferable.self) else {
                    importError = "Could not read that video. Choose another recording."
                    return
                }
                defer { try? FileManager.default.removeItem(at: transferred.url) }
                try Task.checkCancellation()
                let result = await store.importVideo(
                    at: transferred.url,
                    sourceName: "Photos recording",
                    importKind: .recording,
                    groupID: groupID,
                    groupTitle: resolvedGroupTitle,
                    ownership: owner,
                    onPrepared: prepared
                )
                handle(result)
            } catch is CancellationError {
                return
            } catch {
                importError = error.localizedDescription
            }
        }
    }

    private func beginImport(
        _ url: URL,
        sourceName: String,
        ownership owner: ReviewImportOwnership,
        removeSourceAfterImport: Bool
    ) {
        importTask?.cancel()
        importTask = Task { @MainActor in
            isPreparing = true
            importError = nil
            defer {
                if removeSourceAfterImport {
                    try? FileManager.default.removeItem(at: url)
                }
                isPreparing = false
            }

            let result = await store.importVideo(
                at: url,
                sourceName: sourceName,
                importKind: .recording,
                groupID: groupID,
                groupTitle: resolvedGroupTitle,
                ownership: owner,
                onPrepared: prepared
            )
            handle(result)
        }
    }

    private func prepared(_ session: ReviewSession) {
        guard !didPrepare else { return }
        didPrepare = true
        onImported(session)
        dismiss()
    }

    private func handle(_ result: ReviewImportResult) {
        switch result {
        case .imported(let session):
            if !didPrepare { prepared(session) }
        case .cancelled:
            break
        case .failed(let message):
            importError = message
        }
    }
}

private struct RecordingCameraPicker: UIViewControllerRepresentable {
    let onFinished: (URL) -> Void
    let onCancelled: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinished: onFinished, onCancelled: onCancelled)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = [UTType.movie.identifier]
        picker.cameraCaptureMode = .video
        picker.cameraDevice = .rear
        picker.videoQuality = .typeHigh
        picker.videoMaximumDuration = RecordingImportPolicy.maximumDuration
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let onFinished: (URL) -> Void
        let onCancelled: () -> Void

        init(onFinished: @escaping (URL) -> Void, onCancelled: @escaping () -> Void) {
            self.onFinished = onFinished
            self.onCancelled = onCancelled
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCancelled()
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            guard let url = info[.mediaURL] as? URL else {
                onCancelled()
                return
            }
            onFinished(url)
        }
    }
}
