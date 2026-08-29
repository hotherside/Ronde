import Foundation
import SwiftUI

enum ReviewMode: String, CaseIterable, Identifiable, Hashable {
    case range
    case live

    var id: String { rawValue }

    var title: String {
        switch self {
        case .range: return "Range Session"
        case .live: return "Live Review"
        }
    }

    var subtitle: String {
        switch self {
        case .range: return "Import one swing for instant tracer review, or a longer range session."
        case .live: return "Set up a fixed camera and check the frame for a future live review."
        }
    }

    var icon: String {
        switch self {
        case .range: return "film.stack"
        case .live: return "waveform.badge.mic"
        }
    }
}

enum ReviewImportKind: String, Hashable, Codable {
    case oneShot
    case rangeSession
}

enum ReviewStatus: String, Hashable {
    case ready
    case analysing
    case capturing
    case reviewing
    case paused
    case needsAttention
    case failed
    case complete

    var title: String {
        switch self {
        case .ready: return "Ready to review"
        case .analysing: return "Analysing"
        case .capturing: return "Live capture"
        case .reviewing: return "In review"
        case .paused: return "Paused"
        case .needsAttention: return "Needs attention"
        case .failed: return "Could not finish"
        case .complete: return "Complete"
        }
    }
}

enum ShotClassification: String, CaseIterable, Hashable, Codable {
    case likelyShot
    case practice
    case uncertain

    var title: String {
        switch self {
        case .likelyShot: return "Likely shot"
        case .practice: return "Practice swing"
        case .uncertain: return "Uncertain"
        }
    }

    var icon: String {
        switch self {
        case .likelyShot: return "checkmark.circle.fill"
        case .practice: return "figure.golf"
        case .uncertain: return "questionmark.circle.fill"
        }
    }
}

enum CandidateDecision: String, Hashable, Codable {
    case unreviewed
    case kept
    case rejected

    var title: String {
        switch self {
        case .unreviewed: return "Needs review"
        case .kept: return "Kept"
        case .rejected: return "Dismissed"
        }
    }
}

enum ConfidenceLevel: String, Hashable, Codable {
    case high
    case medium
    case low

    var title: String { rawValue.capitalized + " confidence" }
}

struct ReviewPoint: Codable, Hashable {
    var x: Double
    var y: Double

    init(_ point: CGPoint) {
        x = Double(point.x)
        y = Double(point.y)
    }

    var cgPoint: CGPoint { CGPoint(x: x, y: y) }
}

/// User-placed launch-to-landing geometry in normalised video coordinates.
/// It is an assisted overlay, not an observed or measured ball flight.
struct AssistedTracerPath: Codable, Hashable {
    var launch: ReviewPoint
    var apex: ReviewPoint
    var landing: ReviewPoint

    static let `default` = AssistedTracerPath(
        launch: ReviewPoint(CGPoint(x: 0.69, y: 0.61)),
        apex: ReviewPoint(CGPoint(x: 0.72, y: 0.20)),
        landing: ReviewPoint(CGPoint(x: 0.76, y: 0.48))
    )

    init(launch: ReviewPoint, apex: ReviewPoint, landing: ReviewPoint) {
        self.launch = launch
        self.apex = apex
        self.landing = landing
    }

    init(estimate: BallFlightEstimate) {
        launch = ReviewPoint(CGPoint(x: estimate.launch.x, y: estimate.launch.y))
        apex = ReviewPoint(CGPoint(x: estimate.apex.x, y: estimate.apex.y))
        landing = ReviewPoint(CGPoint(x: estimate.landing.x, y: estimate.landing.y))
    }
}

struct ReviewCandidate: Identifiable {
    let id: UUID
    var ordinal: Int
    var impactTime: TimeInterval
    var sourceDuration: TimeInterval
    var classification: ShotClassification
    var confidence: ConfidenceLevel
    var evidence: [String]
    var decision: CandidateDecision
    var tracerAvailable: Bool
    /// Vision's screen-space trajectory. This is deliberately retained as
    /// provisional geometry, not a physical flight or distance measurement.
    var trajectory: DetectedTrajectory?
    var assistedTracer: AssistedTracerPath?
    var tracerSource: BallFlightEstimateSource
    var tracerConfidence: Double
    var observedTracerPointCount: Int

    var startTime: TimeInterval { max(0, impactTime - 5) }
    var endTime: TimeInterval { min(sourceDuration, impactTime + 5) }
    var isAtSourceBoundary: Bool { startTime == 0 || endTime == sourceDuration }

    /// A primary shot is a classifier result that Ronde is willing to present
    /// as a real struck ball in a longer recording. Practice and uncertain
    /// moments remain available for correction, but never earn a tracer in
    /// the long-session rail.
    var isAcceptedShot: Bool {
        classification == .likelyShot && decision != .rejected
    }

    init(
        id: UUID = UUID(),
        ordinal: Int,
        impactTime: TimeInterval,
        sourceDuration: TimeInterval,
        classification: ShotClassification,
        confidence: ConfidenceLevel,
        evidence: [String],
        decision: CandidateDecision = .unreviewed,
        tracerAvailable: Bool = false,
        trajectory: DetectedTrajectory? = nil,
        assistedTracer: AssistedTracerPath? = nil,
        tracerSource: BallFlightEstimateSource = .unavailable,
        tracerConfidence: Double = 0,
        observedTracerPointCount: Int = 0
    ) {
        self.id = id
        self.ordinal = ordinal
        self.impactTime = impactTime
        self.sourceDuration = sourceDuration
        self.classification = classification
        self.confidence = confidence
        self.evidence = evidence
        self.decision = decision
        self.tracerAvailable = tracerAvailable
        self.trajectory = trajectory
        self.assistedTracer = assistedTracer
        self.tracerSource = tracerSource
        self.tracerConfidence = min(max(tracerConfidence, 0), 1)
        self.observedTracerPointCount = max(0, observedTracerPointCount)
    }
}

struct ReviewSession: Identifiable {
    let id: UUID
    var mode: ReviewMode
    var importKind: ReviewImportKind = .rangeSession
    var title: String
    var sourceName: String?
    var sourceURL: URL?
    var createdAt: Date
    var duration: TimeInterval
    /// The source's display width divided by its display height after applying
    /// the track transform. Review media uses this to preserve portrait video.
    var sourceAspectRatio: Double? = nil
    var status: ReviewStatus
    var progress: Double
    var candidates: [ReviewCandidate]
    var errorMessage: String?

    var keptCount: Int { candidates.filter { $0.decision == .kept }.count }
    var unreviewedCount: Int { candidates.filter { $0.decision == .unreviewed }.count }

    /// Import intent is authoritative. Duration is evidence quality and cost,
    /// not a reliable proxy for how many shots a recording contains.
    var isSingleShotImport: Bool {
        importKind == .oneShot
    }

    var acceptedShots: [ReviewCandidate] {
        candidates.filter(\.isAcceptedShot)
    }

    var reviewQueue: [ReviewCandidate] {
        candidates.filter { !$0.isAcceptedShot }
    }

    var defaultCandidate: ReviewCandidate? {
        (isSingleShotImport ? candidates : acceptedShots).first ?? candidates.first
    }
}

enum LibrarySection: String, CaseIterable, Identifiable, Hashable {
    case sessions
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sessions: return "Sessions"
        case .settings: return "Settings"
        }
    }

    var icon: String {
        switch self {
        case .sessions: return "rectangle.stack"
        case .settings: return "gearshape"
        }
    }
}

enum ReviewFixtures {
    static let sampleTrajectory = DetectedTrajectory(
        detectedPoints: [
            NormalizedPoint(x: 0.58, y: 0.38),
            NormalizedPoint(x: 0.64, y: 0.45),
            NormalizedPoint(x: 0.70, y: 0.51)
        ],
        projectedPoints: [
            NormalizedPoint(x: 0.76, y: 0.56),
            NormalizedPoint(x: 0.83, y: 0.58),
            NormalizedPoint(x: 0.90, y: 0.57)
        ],
        equationCoefficients: [0, 0, 0],
        confidence: 0.62
    )

    static let rangeSession = ReviewSession(
        id: UUID(uuidString: "C6C4F9D1-84AC-4DEB-8880-CCF7BF44E9D4")!,
        mode: .range,
        title: "Saturday range session",
        sourceName: "IMG_4028.MOV",
        sourceURL: nil,
        createdAt: Date(timeIntervalSince1970: 1_755_000_000),
        duration: 2_984,
        status: .reviewing,
        progress: 1,
        candidates: [
            ReviewCandidate(
                ordinal: 1,
                impactTime: 94,
                sourceDuration: 2_984,
                classification: .likelyShot,
                confidence: .high,
                evidence: ["Ball visible", "Strong impact motion"],
                tracerAvailable: true,
                trajectory: sampleTrajectory
            ),
            ReviewCandidate(
                ordinal: 2,
                impactTime: 168,
                sourceDuration: 2_984,
                classification: .practice,
                confidence: .medium,
                evidence: ["No ball departure"],
                tracerAvailable: false
            ),
            ReviewCandidate(
                ordinal: 3,
                impactTime: 241,
                sourceDuration: 2_984,
                classification: .uncertain,
                confidence: .low,
                evidence: ["Camera movement", "Ball occluded"],
                tracerAvailable: false
            )
        ]
    )

    static let quickReviewSession = ReviewSession(
        id: UUID(uuidString: "0B436158-6DE4-43E8-9317-4EFD8840474A")!,
        mode: .range,
        importKind: .oneShot,
        title: "One-shot review",
        sourceName: "Portrait range clip",
        sourceURL: nil,
        createdAt: Date(timeIntervalSince1970: 1_777_000_000),
        duration: 6.618,
        sourceAspectRatio: 9.0 / 16.0,
        status: .reviewing,
        progress: 1,
        candidates: [
            ReviewCandidate(
                ordinal: 1,
                impactTime: 1.72,
                sourceDuration: 6.618,
                classification: .uncertain,
                confidence: .medium,
                evidence: ["Impact audio"],
                tracerSource: .unavailable
            )
        ],
        errorMessage: nil
    )

    static let liveSession = ReviewSession(
        id: UUID(uuidString: "8B1A8A3E-83F8-4B0C-95D0-967B3EFDB501")!,
        mode: .live,
        title: "Live Review",
        sourceName: "Live camera",
        sourceURL: nil,
        createdAt: .now,
        duration: 0,
        status: .capturing,
        progress: 0,
        candidates: [],
        errorMessage: nil
    )
}

@MainActor
final class ReviewerStore: ObservableObject {
    @Published var sessions: [ReviewSession]
    @Published var selectedSessionID: UUID?
    @Published var selectedCandidateID: UUID?
    @Published var playheadTime: TimeInterval = 94
    @Published var isBusy = false

    private let mediaStore: LocalMediaStore?
    private let metadataProbe = VideoMetadataProbe()
    private let impactAnalysisService = ImpactCandidateAnalysisService()
    private let longSessionAnalysisService = LongSessionAnalysisService()
    private let ballTrackingService = WASBGolfBallTrackingService()

    init(includeFixtures: Bool = false, previewSourceURL: URL? = nil) {
        var previewSession = ReviewFixtures.quickReviewSession
        previewSession.sourceURL = previewSourceURL
        let initialSessions = includeFixtures ? [previewSession] : []
        sessions = initialSessions
        selectedSessionID = initialSessions.first?.id
        selectedCandidateID = initialSessions.first?.defaultCandidate?.id
        mediaStore = try? LocalMediaStore()
    }

    var selectedSession: ReviewSession? {
        guard let selectedSessionID else { return nil }
        return sessions.first { $0.id == selectedSessionID }
    }

    func select(_ session: ReviewSession) {
        selectedSessionID = session.id
        selectedCandidateID = session.defaultCandidate?.id
        playheadTime = session.defaultCandidate?.impactTime ?? 0
    }

    func selectCandidate(_ candidate: ReviewCandidate) {
        selectedCandidateID = candidate.id
        playheadTime = candidate.impactTime
    }

    func candidate(in session: ReviewSession) -> ReviewCandidate? {
        guard let selectedCandidateID else { return session.defaultCandidate }
        return session.candidates.first { $0.id == selectedCandidateID } ?? session.defaultCandidate
    }

    func setDecision(_ decision: CandidateDecision, for candidate: ReviewCandidate, in session: ReviewSession) {
        updateCandidate(candidate, in: session) { $0.decision = decision }
    }

    func setClassification(_ classification: ShotClassification, for candidate: ReviewCandidate, in session: ReviewSession) {
        updateCandidate(candidate, in: session) { $0.classification = classification }
    }

    func updateImpactTime(_ time: TimeInterval, for candidate: ReviewCandidate, in session: ReviewSession) {
        let clamped = min(max(0, time), session.duration)
        playheadTime = clamped
        updateCandidate(candidate, in: session) { $0.impactTime = clamped }
    }

    func updateAssistedTracer(_ path: AssistedTracerPath, for candidate: ReviewCandidate, in session: ReviewSession) {
        updateCandidate(candidate, in: session) { $0.assistedTracer = path }
    }

    func addManualMarker(in session: ReviewSession) {
        let nextOrdinal = (session.candidates.map(\.ordinal).max() ?? 0) + 1
        let marker = ReviewCandidate(
            ordinal: nextOrdinal,
            impactTime: min(max(0, playheadTime), session.duration),
            sourceDuration: session.duration,
            classification: .uncertain,
            confidence: .low,
            evidence: ["Added manually"]
        )
        updateSession(session) { $0.candidates.append(marker); $0.status = .reviewing }
        selectedCandidateID = marker.id
    }

    func importVideo(
        at sourceURL: URL,
        sourceName: String,
        importKind: ReviewImportKind
    ) async {
        guard let mediaStore else {
            let session = makeSession(title: sourceName, sourceName: sourceName, sourceURL: nil, duration: 0, importKind: importKind, status: .needsAttention, progress: 0, errorMessage: "Ronde could not prepare local media storage.")
            sessions.insert(session, at: 0)
            select(session)
            return
        }

        do {
            let reference = try await mediaStore.importVideo(at: sourceURL)
            let localURL = try await mediaStore.url(for: reference)
            let session = makeSession(title: sourceName, sourceName: reference.originalFilename, sourceURL: localURL, duration: 0, importKind: importKind, status: .analysing, progress: 0, errorMessage: nil)
            sessions.insert(session, at: 0)
            select(session)

            let metadata = try await metadataProbe.probe(url: localURL)
            let safeDuration = metadata.duration.isFinite && metadata.duration > 0 ? metadata.duration : 0
            let sourceAspectRatio = metadata.displayAspectRatio
            updateSession(session) {
                $0.duration = safeDuration
                $0.sourceAspectRatio = sourceAspectRatio
            }

            let reviewCandidates: [ReviewCandidate]
            if importKind == .rangeSession {
                reviewCandidates = await analyseLongSession(
                    url: localURL,
                    duration: safeDuration,
                    sessionID: session.id
                )
            } else {
                reviewCandidates = try await analyseSingleShot(
                    url: localURL,
                    duration: safeDuration,
                    sessionID: session.id
                )
            }
            guard let current = self.sessions.first(where: { $0.id == session.id }) else { return }
            self.updateSession(current) {
                $0.candidates = reviewCandidates
                $0.progress = 1
                $0.status = reviewCandidates.isEmpty ? .needsAttention : .reviewing
                $0.errorMessage = reviewCandidates.isEmpty
                    ? "No real shots were confirmed. The recording is preserved, and you can add a shot manually."
                    : nil
            }
            let defaultCandidate = self.sessions.first(where: { $0.id == session.id })?.defaultCandidate
            self.selectedCandidateID = defaultCandidate?.id
            self.playheadTime = defaultCandidate?.impactTime ?? 0
        } catch is CancellationError {
            guard let current = sessions.first(where: { $0.sourceName == sourceName }) else { return }
            updateSession(current) { $0.status = .needsAttention; $0.errorMessage = "Analysis was cancelled. You can add markers manually." }
        } catch {
            // Import succeeds even if analysis cannot produce candidates. The
            // review surface remains usable with manual markers.
            let title = sourceName.replacingOccurrences(of: ".MOV", with: "").replacingOccurrences(of: ".mov", with: "")
            if let current = sessions.first(where: { $0.title == title }) {
                if current.importKind == .oneShot, current.duration > 0 {
                    let fallback = ReviewCandidate(
                        ordinal: 1,
                        impactTime: current.duration * 0.52,
                        sourceDuration: current.duration,
                        classification: .uncertain,
                        confidence: .low,
                        evidence: ["Short clip", "Ball flight not tracked"],
                        tracerSource: .unavailable
                    )
                    updateSession(current) {
                        $0.candidates = [fallback]
                        $0.status = .reviewing
                        $0.progress = 1
                        $0.errorMessage = nil
                    }
                    selectedCandidateID = fallback.id
                    playheadTime = fallback.impactTime
                } else {
                    updateSession(current) { $0.status = .needsAttention; $0.progress = 1; $0.errorMessage = "The video is imported, but automatic analysis could not finish. Add a shot marker to continue." }
                }
            }
        }
    }

    /// Short clips remain a direct review flow. A tracer is added only when the on-device
    /// sports-ball model and temporal linker establish an observed source-frame track.
    private func analyseSingleShot(
        url: URL,
        duration: TimeInterval,
        sessionID: UUID
    ) async throws -> [ReviewCandidate] {
        let candidates = try await impactAnalysisService.analyse(url: url) { [weak self] progress in
            guard let self else { return }
            Task { @MainActor in
                guard let current = self.sessions.first(where: { $0.id == sessionID }) else { return }
                self.updateSession(current) { $0.progress = progress * 0.72; $0.status = .analysing }
            }
        }
        // Impact audio is the closest available timing anchor for a direct one-shot clip.
        // Body motion may peak during follow-through, so it is only the fallback here.
        let timingCandidates = candidates.filter { $0.evidence.contains(.audioTransient) }
        let strongest = (timingCandidates.isEmpty ? candidates : timingCandidates).max { lhs, rhs in
            lhs.classification.confidence < rhs.classification.confidence
        }
        let impactTime = strongest?.impactTime ?? (duration * 0.52)
        guard duration > 0 else { return [] }

        let trackedFlight = try? await ballTrackingService.analyse(
            url: url,
            impactTime: impactTime
        ) { [weak self] progress in
            guard let self else { return }
            Task { @MainActor in
                guard let current = self.sessions.first(where: { $0.id == sessionID }) else { return }
                self.updateSession(current) {
                    $0.progress = 0.72 + (progress * 0.27)
                    $0.status = .analysing
                }
            }
        }
        let flight = trackedFlight.flatMap { $0.isDisplayable ? $0 : nil }
        var evidence = strongest?.evidence.map(evidenceLabel) ?? ["Short clip"]
        evidence.append(tracerEvidenceLabel(flight?.source ?? .unavailable))
        return [ReviewCandidate(
            id: strongest?.id ?? UUID(),
            ordinal: 1,
            impactTime: impactTime,
            sourceDuration: duration,
            classification: .uncertain,
            confidence: mapConfidence(strongest?.classification.confidence ?? 0),
            evidence: evidence,
            tracerAvailable: flight != nil,
            trajectory: flight?.observedTrajectory,
            assistedTracer: flight.map(AssistedTracerPath.init(estimate:)),
            tracerSource: flight?.source ?? .unavailable,
            tracerConfidence: flight?.confidence ?? 0,
            observedTracerPointCount: flight?.observedPointCount ?? 0
        )]
    }

    /// Longer recordings have a stricter contract: proposal moments are classified first, and
    /// only accepted real shots can enter the clip and tracer pipeline. Practice, background and
    /// uncertain events remain recoverable without a tracer; rejected events are not surfaced.
    private func analyseLongSession(
        url: URL,
        duration: TimeInterval,
        sessionID: UUID
    ) async -> [ReviewCandidate] {
        let result = await longSessionAnalysisService.analyse(
            url: url,
            sourceDuration: duration
        ) { [weak self] progress in
            guard let self else { return }
            Task { @MainActor in
                guard let current = self.sessions.first(where: { $0.id == sessionID }) else { return }
                self.updateSession(current) { $0.progress = progress * 0.82; $0.status = .analysing }
            }
        }

        var acceptedCandidates: [ReviewCandidate] = []
        acceptedCandidates.reserveCapacity(result.acceptedShots.count)
        for (index, shot) in result.acceptedShots.enumerated() {
            let trackedFlight = try? await ballTrackingService.analyse(
                url: url,
                impactTime: shot.impactTime
            )
            let flight = trackedFlight.flatMap { $0.isDisplayable ? $0 : nil }
            let progress = 0.82 + (0.17 * (Double(index + 1) / Double(max(result.acceptedShots.count, 1))))
            if let current = sessions.first(where: { $0.id == sessionID }) {
                updateSession(current) { $0.progress = progress; $0.status = .analysing }
            }
            acceptedCandidates.append(ReviewCandidate(
                id: shot.id,
                ordinal: index + 1,
                impactTime: shot.impactTime,
                sourceDuration: duration,
                classification: .likelyShot,
                confidence: mapConfidence(shot.decision.confidence),
                evidence: [
                    shot.evidence.targetGolferSwing.sourceDescription,
                    shot.evidence.ballLaunch.detectorDescription,
                    shot.decision.explanation,
                    tracerEvidenceLabel(flight?.source ?? .unavailable)
                ],
                tracerAvailable: flight != nil,
                trajectory: flight?.observedTrajectory,
                assistedTracer: flight.map(AssistedTracerPath.init(estimate:)),
                tracerSource: flight?.source ?? .unavailable,
                tracerConfidence: flight?.confidence ?? 0,
                observedTracerPointCount: flight?.observedPointCount ?? 0
            ))
        }

        let uncertainCandidates = result.uncertainMoments.enumerated().map { offset, moment in
            ReviewCandidate(
                id: moment.id,
                ordinal: acceptedCandidates.count + offset + 1,
                impactTime: moment.proposal.sourceTime,
                sourceDuration: duration,
                classification: .uncertain,
                confidence: mapConfidence(moment.decision.confidence),
                evidence: [moment.decision.explanation],
                tracerAvailable: false,
                trajectory: nil,
                assistedTracer: nil,
                tracerSource: .unavailable,
                tracerConfidence: 0,
                observedTracerPointCount: 0
            )
        }
        return acceptedCandidates + uncertainCandidates
    }

    private func makeSession(title: String, sourceName: String?, sourceURL: URL?, duration: TimeInterval, importKind: ReviewImportKind, status: ReviewStatus, progress: Double, errorMessage: String?) -> ReviewSession {
        let session = ReviewSession(
            id: UUID(),
            mode: .range,
            importKind: importKind,
            title: title.replacingOccurrences(of: ".MOV", with: "").replacingOccurrences(of: ".mov", with: ""),
            sourceName: sourceName,
            sourceURL: sourceURL,
            createdAt: .now,
            duration: duration,
            status: status,
            progress: progress,
            candidates: [],
            errorMessage: errorMessage
        )
        return session
    }

    func addLivePlaceholder() -> ReviewSession {
        let session = ReviewSession(
            id: UUID(), mode: .live, title: "Live Review", sourceName: "Live camera",
            sourceURL: nil, createdAt: .now, duration: 0, status: .paused,
            progress: 0, candidates: [], errorMessage: "Live capture is waiting for the capture controller."
        )
        sessions.insert(session, at: 0)
        select(session)
        return session
    }

    private func mapClassification(_ classification: SwingClassificationKind) -> ShotClassification {
        switch classification {
        case .realShot: return .likelyShot
        case .practiceSwing: return .practice
        case .unclassified, .uncertainCandidate: return .uncertain
        }
    }

    private func mapConfidence(_ confidence: Double) -> ConfidenceLevel {
        switch confidence {
        case 0.7...: return .high
        case 0.45..<0.7: return .medium
        default: return .low
        }
    }

    private func evidenceLabel(_ evidence: SwingEvidence) -> String {
        switch evidence {
        case .trajectory: return "Ball trajectory"
        case .bodyMotion: return "Body motion"
        case .audioTransient: return "Impact audio"
        case .manual: return "Added manually"
        }
    }

    private func tracerEvidenceLabel(_ source: BallFlightEstimateSource) -> String {
        switch source {
        case .unavailable: return "Ball flight not tracked"
        case .observed: return "Observed ball flight"
        case .observedAndInferred: return "Observed launch · inferred continuation"
        case .inferred: return "Inferred flight path"
        }
    }

    private func updateSession(_ session: ReviewSession, _ update: (inout ReviewSession) -> Void) {
        guard let index = sessions.firstIndex(where: { $0.id == session.id }) else { return }
        update(&sessions[index])
    }

    private func updateCandidate(_ candidate: ReviewCandidate, in session: ReviewSession, _ update: (inout ReviewCandidate) -> Void) {
        guard let sessionIndex = sessions.firstIndex(where: { $0.id == session.id }),
              let candidateIndex = sessions[sessionIndex].candidates.firstIndex(where: { $0.id == candidate.id }) else { return }
        update(&sessions[sessionIndex].candidates[candidateIndex])
    }
}
