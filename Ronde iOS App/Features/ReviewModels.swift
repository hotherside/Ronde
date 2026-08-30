import Foundation
import SwiftUI

enum ReviewMode: String, CaseIterable, Identifiable, Hashable, Codable {
    case range
    case live

    var id: String { rawValue }

    var title: String {
        switch self {
        case .range: return "Shot Review"
        case .live: return "Live Review"
        }
    }

    var subtitle: String {
        switch self {
        case .range: return "Import one shot video up to 1 minute for automatic tracer review."
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

enum ShotVideoImportPolicy {
    static let maximumDuration: TimeInterval = 60

    static func accepts(duration: TimeInterval) -> Bool {
        duration.isFinite && duration > 0 && duration <= maximumDuration
    }
}

enum ReviewStatus: String, Hashable, Codable {
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

struct ReviewCandidate: Identifiable, Codable {
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
    /// One immutable automatic geometry used for both playback and rendered export. Its observed
    /// source-frame segment and inferred continuation stay separate so the UI cannot style both
    /// as detected flight by accident.
    var evidenceAnchoredPath: EvidenceAnchoredFlightPath?
    /// Person-authored rescue geometry. This remains separate from automatic evidence.
    var assistedTracer: AssistedTracerPath?
    var tracerSource: BallFlightEstimateSource
    var tracerConfidence: Double
    var observedTracerPointCount: Int
    /// A short shot-video import is already the clip. It should play and export intact rather
    /// than being sliced again around the internally detected impact time.
    var usesFullSourceRange: Bool

    var startTime: TimeInterval { usesFullSourceRange ? 0 : max(0, impactTime - 5) }
    var endTime: TimeInterval { usesFullSourceRange ? sourceDuration : min(sourceDuration, impactTime + 5) }
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
        evidenceAnchoredPath: EvidenceAnchoredFlightPath? = nil,
        assistedTracer: AssistedTracerPath? = nil,
        tracerSource: BallFlightEstimateSource = .unavailable,
        tracerConfidence: Double = 0,
        observedTracerPointCount: Int = 0,
        usesFullSourceRange: Bool = false
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
        self.evidenceAnchoredPath = evidenceAnchoredPath
        self.assistedTracer = assistedTracer
        self.tracerSource = tracerSource
        self.tracerConfidence = min(max(tracerConfidence, 0), 1)
        self.observedTracerPointCount = max(0, observedTracerPointCount)
        self.usesFullSourceRange = usesFullSourceRange
    }

    var hasAutomaticTracer: Bool { evidenceAnchoredPath != nil }
    var hasManualTracer: Bool { assistedTracer != nil }
}

struct ReviewSession: Identifiable, Codable {
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
    var placeName: String? = nil
    var clubName: String? = nil
    var note: String = ""
    var isFavourite: Bool = false
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
            NormalizedPoint(x: 0.42, y: 0.68),
            NormalizedPoint(x: 0.47, y: 0.59),
            NormalizedPoint(x: 0.53, y: 0.51)
        ],
        projectedPoints: [
            NormalizedPoint(x: 0.59, y: 0.43),
            NormalizedPoint(x: 0.65, y: 0.37),
            NormalizedPoint(x: 0.71, y: 0.33),
            NormalizedPoint(x: 0.77, y: 0.34),
            NormalizedPoint(x: 0.82, y: 0.40),
            NormalizedPoint(x: 0.87, y: 0.50),
            NormalizedPoint(x: 0.90, y: 0.62)
        ],
        presentationTimes: [1.72, 1.78, 1.84],
        equationCoefficients: [0, 0, 0],
        confidence: 0.62
    )

    static let sampleEvidenceAnchoredPath = EvidenceAnchoredFlightPath(
        observedPoints: sampleTrajectory.detectedPoints,
        inferredContinuation: sampleTrajectory.projectedPoints,
        observedPresentationTimes: sampleTrajectory.presentationTimes,
        estimatedCarry: EstimatedCarryDistance(lowerMetres: 145, upperMetres: 165),
        confidence: 0.62
    )!

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
                trajectory: sampleTrajectory,
                evidenceAnchoredPath: sampleEvidenceAnchoredPath,
                tracerSource: .observedAndInferred,
                tracerConfidence: 0.62,
                observedTracerPointCount: sampleTrajectory.detectedPoints.count
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
        createdAt: Date(timeIntervalSince1970: 1_787_992_920),
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
                evidence: ["Impact audio", "Ball launch tracked"],
                tracerAvailable: true,
                trajectory: sampleTrajectory,
                evidenceAnchoredPath: sampleEvidenceAnchoredPath,
                tracerSource: .observedAndInferred,
                tracerConfidence: 0.62,
                observedTracerPointCount: sampleTrajectory.detectedPoints.count
            )
        ],
        placeName: "Moore Park Golf",
        clubName: "7-iron",
        note: "Evening range session.",
        isFavourite: true,
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
    @Published private(set) var lastExportedTracerURL: URL?

    private let mediaStore: LocalMediaStore?
    private var archive: ReviewSessionArchive?
    private let persistenceEnabled: Bool
    private var activeAccountID: UUID?
    private let metadataProbe = VideoMetadataProbe()
    private let impactAnalysisService = ImpactCandidateAnalysisService()
    private var longSessionAnalysisService: LongSessionAnalysisService
    private(set) var fixedSingleGolferSessionEvidence: FixedCameraSingleGolferSessionEvidence?
    private let ballTrackingService = WASBGolfBallTrackingService()
    private let flightPathExtrapolator = EvidenceAnchoredFlightPathExtrapolator()
    private let tracedVideoExporter = TracedVideoExporter()

    init(
        includeFixtures: Bool = false,
        previewSourceURL: URL? = nil,
        fixedSingleGolferSessionEvidence: FixedCameraSingleGolferSessionEvidence? = nil,
        persistenceEnabled: Bool = false
    ) {
        self.persistenceEnabled = persistenceEnabled
        archive = nil
        if let fixedSingleGolferSessionEvidence,
           fixedSingleGolferSessionEvidence.permitsAssociation {
            self.fixedSingleGolferSessionEvidence = fixedSingleGolferSessionEvidence
            self.longSessionAnalysisService = LongSessionAnalysisService(
                fixedSingleGolferEvidence: fixedSingleGolferSessionEvidence
            )
        } else {
            self.fixedSingleGolferSessionEvidence = nil
            self.longSessionAnalysisService = LongSessionAnalysisService()
        }
        var previewSession = ReviewFixtures.quickReviewSession
        previewSession.sourceURL = previewSourceURL
        let initialSessions = includeFixtures ? [previewSession] : []
        sessions = initialSessions
        selectedSessionID = initialSessions.first?.id
        selectedCandidateID = initialSessions.first?.defaultCandidate?.id
        mediaStore = try? LocalMediaStore()
    }

    /// Opens the local library that belongs to the signed-in Apple account. This prevents a
    /// second account on the same device from seeing or syncing the first account's reviews.
    func activateLibrary(for accountID: UUID) {
        guard persistenceEnabled, activeAccountID != accountID else { return }
        archive = try? ReviewSessionArchive(accountID: accountID)
        activeAccountID = accountID
        sessions = archive?.load() ?? []
        selectedSessionID = sessions.first?.id
        selectedCandidateID = sessions.first?.defaultCandidate?.id
    }

    func deactivateLibrary() {
        guard persistenceEnabled else { return }
        archive = nil
        activeAccountID = nil
        sessions = []
        selectedSessionID = nil
        selectedCandidateID = nil
    }

    /// Explicitly enables the narrow range-session detector path after the person reviewing the
    /// video has confirmed the fixed-camera and single-golfer conditions. An incomplete
    /// confirmation resets to the normal fail-closed service rather than using proximity.
    @discardableResult
    func configureFixedSingleGolferRangeAnalysis(
        with evidence: FixedCameraSingleGolferSessionEvidence
    ) -> Bool {
        guard evidence.permitsAssociation else {
            fixedSingleGolferSessionEvidence = nil
            longSessionAnalysisService = LongSessionAnalysisService()
            return false
        }
        fixedSingleGolferSessionEvidence = evidence
        longSessionAnalysisService = LongSessionAnalysisService(fixedSingleGolferEvidence: evidence)
        return true
    }

    func disableFixedSingleGolferRangeAnalysis() {
        fixedSingleGolferSessionEvidence = nil
        longSessionAnalysisService = LongSessionAnalysisService()
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
        updateCandidate(candidate, in: session) { candidate in
            candidate.assistedTracer = path
            candidate.tracerAvailable = true
            if candidate.evidenceAnchoredPath == nil {
                candidate.tracerSource = .inferred
                candidate.tracerConfidence = 0
            }
            if !candidate.evidence.contains("User-assisted tracer") {
                candidate.evidence.append("User-assisted tracer")
            }
        }
    }

    /// Starts a recoverable manual overlay without pretending that a missed automatic track was
    /// observed. The result is saved with the local review archive when persistence is enabled.
    @discardableResult
    func startManualTracer(for candidate: ReviewCandidate, in session: ReviewSession) -> AssistedTracerPath {
        let path = candidate.assistedTracer ?? AssistedTracerPath.default
        updateAssistedTracer(path, for: candidate, in: session)
        return path
    }

    func clearManualTracer(for candidate: ReviewCandidate, in session: ReviewSession) {
        updateCandidate(candidate, in: session) { candidate in
            candidate.assistedTracer = nil
            candidate.evidence.removeAll { $0 == "User-assisted tracer" }
            if let automatic = candidate.evidenceAnchoredPath {
                candidate.tracerAvailable = true
                candidate.tracerSource = automatic.source
                candidate.tracerConfidence = automatic.confidence
            } else {
                candidate.tracerAvailable = false
                candidate.tracerSource = .unavailable
                candidate.tracerConfidence = 0
            }
        }
    }

    func toggleFavourite(_ session: ReviewSession) {
        updateSession(session) { $0.isFavourite.toggle() }
    }

    func updateDetails(
        for session: ReviewSession,
        title: String,
        placeName: String,
        clubName: String,
        note: String
    ) {
        updateSession(session) { value in
            let cleanedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            value.title = cleanedTitle.isEmpty ? value.title : String(cleanedTitle.prefix(160))
            value.placeName = Self.cleanOptional(placeName, limit: 120)
            value.clubName = Self.cleanOptional(clubName, limit: 80)
            value.note = String(note.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1_000))
        }
    }

    func delete(_ session: ReviewSession) async {
        if let sourceURL = session.sourceURL {
            try? await mediaStore?.delete(sourceURL)
        }
        sessions.removeAll { $0.id == session.id }
        if selectedSessionID == session.id {
            selectedSessionID = sessions.first?.id
            selectedCandidateID = sessions.first?.defaultCandidate?.id
        }
        persistSessions()
    }

    /// Produces a local MOV using the exact geometry already stored on the selected candidate.
    /// It is intentionally separate from analysis: sharing a video cannot rerun detection, invent
    /// missing points, or turn a manual rescue into observed flight.
    func exportTracedVideo(for candidate: ReviewCandidate, in session: ReviewSession) async throws -> URL {
        guard let sourceURL = session.sourceURL else {
            throw TracedVideoExportError.sourceUnavailable
        }
        let geometry: TracedVideoTracerGeometry
        let revealStartTime: TimeInterval
        if let manualPath = candidate.assistedTracer {
            geometry = TracedVideoTracerGeometry(
                manualLaunch: NormalizedPoint(x: manualPath.launch.x, y: manualPath.launch.y),
                apex: NormalizedPoint(x: manualPath.apex.x, y: manualPath.apex.y),
                landing: NormalizedPoint(x: manualPath.landing.x, y: manualPath.landing.y)
            )
            revealStartTime = candidate.impactTime
        } else if let automaticPath = candidate.evidenceAnchoredPath,
                  let automaticGeometry = TracedVideoTracerGeometry(path: automaticPath) {
            geometry = automaticGeometry
            revealStartTime = automaticPath.inferredLaunchConnector.isEmpty
                ? (automaticPath.observedPresentationTimes.first ?? candidate.impactTime)
                : candidate.impactTime
        } else {
            throw TracedVideoExportError.noStoredTracerGeometry
        }

        let range = ReviewTimeRange(
            start: candidate.startTime,
            duration: max(0, candidate.endTime - candidate.startTime)
        )
        let output = try await tracedVideoExporter.export(TracedVideoExportRequest(
            sourceURL: sourceURL,
            sourceRange: range,
            revealStartTime: revealStartTime,
            geometry: geometry
        ))
        lastExportedTracerURL = output
        return output
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
            persistSessions()
            return
        }

        do {
            let reference = try await mediaStore.importVideo(at: sourceURL)
            let localURL = try await mediaStore.url(for: reference)
            let session = makeSession(title: sourceName, sourceName: reference.originalFilename, sourceURL: localURL, duration: 0, importKind: importKind, status: .analysing, progress: 0, errorMessage: nil)
            sessions.insert(session, at: 0)
            select(session)
            persistSessions()

            let metadata = try await metadataProbe.probe(url: localURL)
            let safeDuration = metadata.duration.isFinite && metadata.duration > 0 ? metadata.duration : 0
            let sourceAspectRatio = metadata.displayAspectRatio
            updateSession(session) {
                $0.duration = safeDuration
                $0.sourceAspectRatio = sourceAspectRatio
            }

            if importKind == .oneShot, !ShotVideoImportPolicy.accepts(duration: safeDuration) {
                updateSession(session) {
                    $0.progress = 1
                    $0.status = .needsAttention
                    $0.errorMessage = "Choose one shot video that is 1 minute or shorter. Automatic session slicing is outside this MVP."
                }
                return
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
                updateSession(current) {
                    $0.status = .needsAttention
                    $0.progress = 1
                    $0.errorMessage = "The video is imported, but automatic analysis could not finish. Add a shot marker to continue."
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
        // Impact audio is the closest available timing anchor for a direct one-shot clip. Silent
        // clips fall back to observed body motion, then the ball tracker performs its own local
        // acquisition scan from that source time. A duration-based impact guess is never used.
        let audioCandidates = candidates.filter { $0.evidence.contains(.audioTransient) }
        let bodyCandidates = candidates.filter { $0.evidence.contains(.bodyMotion) }
        let timingCandidates = audioCandidates.isEmpty ? bodyCandidates : audioCandidates
        let strongest = timingCandidates.max { lhs, rhs in
            lhs.classification.confidence < rhs.classification.confidence
        }
        guard duration > 0, let strongest else { return [] }
        let impactTime = strongest.impactTime

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
        let automaticPath = flight.flatMap { flightPathExtrapolator.path(from: $0, impactTime: impactTime) }
        var evidence = strongest.evidence.map(evidenceLabel)
        evidence.append(tracerEvidenceLabel(automaticPath?.source ?? .unavailable))
        return [ReviewCandidate(
            id: strongest.id,
            ordinal: 1,
            impactTime: impactTime,
            sourceDuration: duration,
            classification: .uncertain,
            confidence: mapConfidence(strongest.classification.confidence),
            evidence: evidence,
            tracerAvailable: automaticPath != nil,
            trajectory: flight?.observedTrajectory,
            evidenceAnchoredPath: automaticPath,
            assistedTracer: nil,
            tracerSource: automaticPath?.source ?? .unavailable,
            tracerConfidence: automaticPath?.confidence ?? 0,
            observedTracerPointCount: flight?.observedPointCount ?? 0,
            usesFullSourceRange: true
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
            let automaticPath = flight.flatMap { flightPathExtrapolator.path(from: $0, impactTime: shot.impactTime) }
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
                    tracerEvidenceLabel(automaticPath?.source ?? .unavailable)
                ],
                tracerAvailable: automaticPath != nil,
                trajectory: flight?.observedTrajectory,
                evidenceAnchoredPath: automaticPath,
                assistedTracer: nil,
                tracerSource: automaticPath?.source ?? .unavailable,
                tracerConfidence: automaticPath?.confidence ?? 0,
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
        persistSessions()
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
        case .observedAndInferred: return "Observed launch · estimated flight"
        case .inferred: return "Manual tracer"
        }
    }

    private func updateSession(_ session: ReviewSession, _ update: (inout ReviewSession) -> Void) {
        guard let index = sessions.firstIndex(where: { $0.id == session.id }) else { return }
        update(&sessions[index])
        persistSessions()
    }

    private func updateCandidate(_ candidate: ReviewCandidate, in session: ReviewSession, _ update: (inout ReviewCandidate) -> Void) {
        guard let sessionIndex = sessions.firstIndex(where: { $0.id == session.id }),
              let candidateIndex = sessions[sessionIndex].candidates.firstIndex(where: { $0.id == candidate.id }) else { return }
        update(&sessions[sessionIndex].candidates[candidateIndex])
        persistSessions()
    }

    private func persistSessions() {
        try? archive?.save(sessions)
    }

    private static func cleanOptional(_ value: String, limit: Int) -> String? {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : String(cleaned.prefix(limit))
    }
}
