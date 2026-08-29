import Foundation

/// Coordinates metadata probing and exact local derivative export for a candidate clip.
actor ReviewClipService {
    private let store: LocalMediaStore
    private let metadataProbe: VideoMetadataProbe
    private let exporter: ExactClipExporter

    init(
        store: LocalMediaStore,
        metadataProbe: VideoMetadataProbe = VideoMetadataProbe(),
        exporter: ExactClipExporter = ExactClipExporter()
    ) {
        self.store = store
        self.metadataProbe = metadataProbe
        self.exporter = exporter
    }

    func exportClip(for candidate: SwingCandidate, from source: LocalMediaReference) async throws -> LocalMediaReference {
        let sourceURL = try await store.url(for: source)
        let metadata = try await metadataProbe.probe(url: sourceURL)
        let range = candidate.clipWindow.clipped(to: metadata.duration)
        let destination = try await store.makeClipDestination()
        do {
            try await exporter.export(sourceURL: sourceURL, range: range, destinationURL: destination.url)
            return destination.reference
        } catch {
            try? await store.delete(destination.url)
            throw error
        }
    }

    /// Automatic export is intentionally narrower than the legacy manual-candidate export path.
    /// Uncertain and rejected moments have no clip plan and cannot reach this method.
    func exportAutomaticallyAcceptedClip(
        for shot: AcceptedShot,
        from source: LocalMediaReference
    ) async throws -> LocalMediaReference {
        guard shot.decision.kind == .accepted, shot.tracerEligibility == .eligible else {
            throw ExactClipExportError.invalidRange
        }
        let sourceURL = try await store.url(for: source)
        let metadata = try await metadataProbe.probe(url: sourceURL)
        let plannedRange = shot.clipPlan.sourceRange
        let range = ReviewTimeRange(
            start: min(max(0, plannedRange.start), max(0, metadata.duration)),
            duration: min(plannedRange.duration, max(0, metadata.duration - plannedRange.start))
        )
        let destination = try await store.makeClipDestination()
        do {
            try await exporter.export(sourceURL: sourceURL, range: range, destinationURL: destination.url)
            return destination.reference
        } catch {
            try? await store.delete(destination.url)
            throw error
        }
    }
}
