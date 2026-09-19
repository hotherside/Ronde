import Foundation
import SwiftUI

enum ReviewMode: String, CaseIterable, Identifiable, Hashable, Codable, Sendable {
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

enum ReviewImportKind: String, Hashable, Codable, Sendable {
    case oneShot
    case rangeSession
    /// A manually reviewed 10–20 minute source. Recording imports never start perception work.
    case recording
}

enum ShotVideoImportPolicy {
    static let maximumDuration: TimeInterval = 60

    static func accepts(duration: TimeInterval) -> Bool {
        duration.isFinite && duration > 0 && duration <= maximumDuration
    }
}

enum RecordingImportPolicy {
    static let maximumDuration: TimeInterval = 20 * 60

    static func accepts(duration: TimeInterval) -> Bool {
        duration.isFinite && duration > 0 && duration <= maximumDuration
    }
}

/// A person-authored point in a full recording. It is deliberately not an analysis result and
/// carries no implication that a ball or impact was observed.
struct RecordingBookmark: Identifiable, Codable, Hashable, Sendable {
    static let defaultBeforeDuration: TimeInterval = 5
    static let defaultAfterDuration: TimeInterval = 5
    static let duplicateTolerance: TimeInterval = 0.05

    let id: UUID
    var sourceTime: TimeInterval
    var beforeDuration: TimeInterval
    var afterDuration: TimeInterval
    var createdAt: Date

    init(
        id: UUID = UUID(),
        sourceTime: TimeInterval,
        beforeDuration: TimeInterval = Self.defaultBeforeDuration,
        afterDuration: TimeInterval = Self.defaultAfterDuration,
        createdAt: Date = .now
    ) {
        self.id = id
        self.sourceTime = sourceTime.isFinite ? max(0, sourceTime) : 0
        self.beforeDuration = beforeDuration.isFinite ? max(0, beforeDuration) : Self.defaultBeforeDuration
        self.afterDuration = afterDuration.isFinite ? max(0, afterDuration) : Self.defaultAfterDuration
        self.createdAt = createdAt
    }

    func clipRange(sourceDuration: TimeInterval) -> ReviewTimeRange {
        let safeDuration = sourceDuration.isFinite ? max(0, sourceDuration) : 0
        let impact = min(max(0, sourceTime), safeDuration)
        let start = max(0, impact - beforeDuration)
        let end = min(safeDuration, impact + afterDuration)
        return ReviewTimeRange(start: start, duration: max(0, end - start))
    }
}

enum ReviewStatus: String, Hashable, Codable, Sendable {
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

enum ShotClassification: String, CaseIterable, Hashable, Codable, Sendable {
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

enum CandidateDecision: String, Hashable, Codable, Sendable {
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

enum ConfidenceLevel: String, Hashable, Codable, Sendable {
    case high
    case medium
    case low

    var title: String { rawValue.capitalized + " confidence" }
}

struct ReviewPoint: Codable, Hashable, Sendable {
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
struct AssistedTracerPath: Codable, Hashable, Sendable {
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

struct ReviewCandidate: Identifiable, Codable, Sendable {
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

struct ReviewSession: Identifiable, Codable, Sendable {
    let id: UUID
    var mode: ReviewMode
    var importKind: ReviewImportKind = .rangeSession
    var title: String
    var sourceName: String?
    var sourceURL: URL?
    var sourceRelativePath: String? = nil
    var videoEdit: ShotVideoEdit? = nil
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
    /// Rows in the same user-facing Session. Legacy rows remain valid and form their own group.
    var groupID: UUID? = nil
    var groupTitle: String? = nil
    /// A source-linked shot points to its full recording. Root recordings leave this nil.
    var sourceRecordingID: UUID? = nil
    var sourceBookmarkID: UUID? = nil
    /// The immutable extraction window of a derived shot in absolute source time. Nil means that
    /// the row's studio uses the full source, which preserves legacy archive behaviour.
    /// Set only when the source-linked shot is created. The studio treats it as immutable and
    /// applies later trim edits inside its bounded source range.
    var sourceClipRange: ReviewTimeRange? = nil
    // Optional backing storage is intentional: synthesised Codable must tolerate pre-bookmark
    // archives that have no corresponding key. `bookmarks` is the safe public collection.
    var storedBookmarks: [RecordingBookmark]? = nil

    var bookmarks: [RecordingBookmark] {
        get { storedBookmarks ?? [] }
        set { storedBookmarks = newValue }
    }

    var keptCount: Int { candidates.filter { $0.decision == .kept }.count }
    var unreviewedCount: Int { candidates.filter { $0.decision == .unreviewed }.count }

    /// Import intent is authoritative. Duration is evidence quality and cost,
    /// not a reliable proxy for how many shots a recording contains.
    var isSingleShotImport: Bool {
        importKind == .oneShot
    }

    var isRecording: Bool { importKind == .recording }
    var isDerivedShot: Bool { sourceRecordingID != nil }
    /// A pre-recording-library row remains a source root even though it uses the original
    /// one-shot/range import kinds. It routes to its existing studio rather than becoming a
    /// phantom child shot in the new Sessions collection.
    var isLegacySourceRoot: Bool {
        !isRecording && !isDerivedShot && groupID == nil && sourceClipRange == nil
    }

    /// A stable local source identity. Legacy rows use their own ID, while derived rows always
    /// resolve to the root recording so shared media is never removed prematurely.
    var recordingID: UUID { sourceRecordingID ?? id }

    var studioSourceRange: ReviewTimeRange {
        sourceClipRange?.clipped(to: duration)
            ?? ReviewTimeRange(start: 0, duration: max(0, duration))
    }

    var editableSourceRange: ReviewTimeRange { studioSourceRange }

    /// The range a library card should describe. A saved reversible cut takes precedence; an
    /// unedited source-linked shot describes its immutable bookmarked extraction instead.
    var displayRange: ReviewTimeRange {
        videoEdit?.normalised(sourceDuration: duration).sourceRange ?? studioSourceRange
    }

    func bookmark(id: UUID) -> RecordingBookmark? {
        bookmarks.first { $0.id == id }
    }

    func clipRange(for bookmark: RecordingBookmark) -> ReviewTimeRange {
        bookmark.clipRange(sourceDuration: duration)
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

/// A presentation-only grouping derived from persisted rows. No separate archive envelope is
/// required, so old archives remain readable and account-scoped exactly as before.
struct ReviewSessionGroup: Identifiable, Hashable, Sendable {
    let id: UUID
    let title: String
    let recordings: [ReviewSession]
    let shots: [ReviewSession]

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
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

/// Captured before a picker begins transferring media. Account changes invalidate it.
struct ReviewImportOwnership: Equatable, Sendable {
    fileprivate let accountID: UUID?
    fileprivate let generation: UUID
}

enum ReviewImportResult: Sendable {
    case imported(ReviewSession)
    case cancelled
    case failed(String)
}

protocol ReviewMediaImporting: Sendable {
    func importVideo(at sourceURL: URL) async throws -> LocalMediaReference
    func url(for reference: LocalMediaReference) async throws -> URL
    func delete(_ url: URL) async throws
}

extension LocalMediaStore: ReviewMediaImporting {}

@MainActor
final class ReviewerStore: ObservableObject {
    @Published var sessions: [ReviewSession]
    @Published var selectedSessionID: UUID?
    @Published var selectedCandidateID: UUID?
    @Published var playheadTime: TimeInterval = 94
    @Published var isBusy = false
    @Published private(set) var lastExportedTracerURL: URL?
    @Published private(set) var libraryError: String?
    @Published private(set) var hasUnsavedChanges = false
    @Published private(set) var libraryIsReadable = false

    private let mediaStore: (any ReviewMediaImporting)?
    private var archive: ReviewSessionArchive?
    private let persistenceEnabled: Bool
    private var activeAccountID: UUID?
    private let libraryRootURL: URL?
    private var libraryGeneration = UUID()
    private var operations: [UUID: Task<ReviewImportResult, Never>] = [:]
    private var analysisOperations: [UUID: UUID] = [:]
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
        persistenceEnabled: Bool = false,
        libraryRootURL: URL? = nil,
        mediaStore: (any ReviewMediaImporting)? = nil
    ) {
        self.persistenceEnabled = persistenceEnabled
        self.libraryRootURL = libraryRootURL
        libraryIsReadable = !persistenceEnabled
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
        self.mediaStore = mediaStore ?? (try? LocalMediaStore(rootURL: libraryRootURL))
    }

    var canModifyLibrary: Bool {
        !persistenceEnabled || (activeAccountID != nil && archive != nil && libraryIsReadable)
    }

    /// Opens the local library that belongs to the signed-in Apple account. Pending work from a
    /// former account can never acquire this archive after its asynchronous transfer completes.
    func activateLibrary(for accountID: UUID) {
        guard persistenceEnabled, activeAccountID != accountID else { return }
        invalidateOperations()
        activeAccountID = accountID
        hasUnsavedChanges = false
        openLibrary()
    }

    func deactivateLibrary() {
        guard persistenceEnabled else { return }
        invalidateOperations()
        archive = nil
        activeAccountID = nil
        libraryIsReadable = false
        libraryError = nil
        hasUnsavedChanges = false
        sessions = []
        selectedSessionID = nil
        selectedCandidateID = nil
        lastExportedTracerURL = nil
    }

    func retryLibraryLoad() {
        guard persistenceEnabled, activeAccountID != nil else { return }
        if hasUnsavedChanges {
            _ = persistSessions()
        } else {
            invalidateOperations()
            openLibrary()
        }
    }

    func retrySavingLibrary() {
        _ = persistSessions()
    }

    /// Call this when opening Photos/Files, not after the selected media has downloaded.
    func captureImportOwnership() -> ReviewImportOwnership? {
        guard canModifyLibrary else { return nil }
        return ReviewImportOwnership(accountID: activeAccountID, generation: libraryGeneration)
    }

    private func ownsLibrary(_ ownership: ReviewImportOwnership) -> Bool {
        canModifyLibrary && ownership.accountID == activeAccountID && ownership.generation == libraryGeneration
    }

    private func invalidateOperations() {
        libraryGeneration = UUID()
        for task in operations.values { task.cancel() }
        operations.removeAll()
        analysisOperations.removeAll()
        isBusy = false
    }

    private func openLibrary() {
        guard let accountID = activeAccountID else { return }
        libraryError = nil
        libraryIsReadable = false
        do {
            let opened = try ReviewSessionArchive(accountID: accountID, rootURL: libraryRootURL)
            archive = opened
            switch opened.read() {
            case .missing:
                sessions = []
                libraryIsReadable = true
            case .loaded(let restored):
                sessions = restored.map { session in
                    var value = session
                    if value.status == .analysing {
                        value.status = .needsAttention
                        value.progress = 0
                        value.errorMessage = "Analysis was interrupted. Play the original or try again."
                    }
                    return value
                }
                libraryIsReadable = true
            case .failed(let error):
                sessions = []
                libraryError = error.localizedDescription
            }
        } catch {
            archive = nil
            sessions = []
            libraryError = "Ronde could not open your local library. Its existing files have been kept."
        }
        selectedSessionID = sessions.first?.id
        selectedCandidateID = sessions.first?.defaultCandidate?.id
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

    /// User-facing Sessions are derived from durable row grouping, keeping the archive format
    /// compatible with the original one-shot-only library.
    var sessionGroups: [ReviewSessionGroup] {
        let grouped = Dictionary(grouping: sessions) { $0.groupID ?? $0.recordingID }
        return grouped.compactMap { id, rows in
            let ordered = rows.sorted { $0.createdAt > $1.createdAt }
            let recording = ordered.first(where: { $0.isRecording })
            let title = ordered.compactMap(\.groupTitle).first
                ?? recording?.title
                ?? ordered.first?.title
                ?? "Session"
            return ReviewSessionGroup(
                id: id,
                title: title,
                recordings: ordered.filter { $0.isRecording || $0.isLegacySourceRoot },
                shots: ordered.filter { !$0.isRecording }
            )
        }
        .sorted { lhs, rhs in
            let left = (lhs.recordings + lhs.shots).map(\.createdAt).max() ?? .distantPast
            let right = (rhs.recordings + rhs.shots).map(\.createdAt).max() ?? .distantPast
            return left > right
        }
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

    /// Adds a manual moment to a recording. Repeating a bookmark at the same source time returns
    /// the existing moment instead of creating another extractable shot.
    @discardableResult
    func addBookmark(
        at sourceTime: TimeInterval,
        before: TimeInterval = RecordingBookmark.defaultBeforeDuration,
        after: TimeInterval = RecordingBookmark.defaultAfterDuration,
        to recording: ReviewSession
    ) -> RecordingBookmark? {
        guard sourceTime.isFinite, before.isFinite, after.isFinite,
              let current = sessions.first(where: { $0.id == recording.id }), current.isRecording else { return nil }
        let clampedTime = min(max(0, sourceTime), max(0, current.duration))
        if let existing = current.bookmarks.first(where: {
            abs($0.sourceTime - clampedTime) <= RecordingBookmark.duplicateTolerance
        }) {
            return existing
        }
        let bookmark = RecordingBookmark(sourceTime: clampedTime, beforeDuration: before, afterDuration: after)
        guard mutateAtomically({ rows in
            guard let index = rows.firstIndex(where: { $0.id == recording.id }) else { return }
            rows[index].bookmarks.append(bookmark)
        }) else { return nil }
        return bookmark
    }

    @discardableResult
    func updateBookmark(
        _ bookmarkID: UUID,
        sourceTime: TimeInterval,
        before: TimeInterval,
        after: TimeInterval,
        in recording: ReviewSession
    ) -> Bool {
        guard sourceTime.isFinite, before.isFinite, after.isFinite,
              let current = sessions.first(where: { $0.id == recording.id }), current.isRecording else { return false }
        let clampedTime = min(max(0, sourceTime), max(0, current.duration))
        guard !current.bookmarks.contains(where: {
            $0.id != bookmarkID && abs($0.sourceTime - clampedTime) <= RecordingBookmark.duplicateTolerance
        }) else { return false }
        return mutateAtomically { rows in
            guard let sessionIndex = rows.firstIndex(where: { $0.id == recording.id }),
                  let bookmarkIndex = rows[sessionIndex].bookmarks.firstIndex(where: { $0.id == bookmarkID }) else { return }
            rows[sessionIndex].bookmarks[bookmarkIndex].sourceTime = clampedTime
            rows[sessionIndex].bookmarks[bookmarkIndex].beforeDuration = max(0, before)
            rows[sessionIndex].bookmarks[bookmarkIndex].afterDuration = max(0, after)
        }
    }

    @discardableResult
    func removeBookmark(_ bookmarkID: UUID, from recording: ReviewSession) -> Bool {
        guard let current = sessions.first(where: { $0.id == recording.id }), current.isRecording,
              current.bookmark(id: bookmarkID) != nil,
              !sessions.contains(where: { $0.sourceRecordingID == recording.id && $0.sourceBookmarkID == bookmarkID }) else {
            return false
        }
        return mutateAtomically { rows in
            guard let index = rows.firstIndex(where: { $0.id == recording.id }) else { return }
            rows[index].bookmarks.removeAll { $0.id == bookmarkID }
        }
    }

    /// Creates source-linked shots without copying or mutating the original recording. Each
    /// bookmark may be extracted once; a retry deliberately preserves the existing shot's edits.
    @discardableResult
    func createShots(from recording: ReviewSession, bookmarkIDs: [UUID]? = nil) -> [UUID] {
        guard let current = sessions.first(where: { $0.id == recording.id }), current.isRecording else { return [] }
        let requested = bookmarkIDs.map(Set.init) ?? Set(current.bookmarks.map(\.id))
        let bookmarks = current.bookmarks.filter { requested.contains($0.id) }
        let existingLinks = Set(sessions.compactMap { row -> UUID? in
            row.sourceRecordingID == current.id ? row.sourceBookmarkID : nil
        })
        let pending = bookmarks.filter { !existingLinks.contains($0.id) }
        guard !pending.isEmpty else { return [] }

        let groupID = current.groupID ?? current.id
        let groupTitle = current.groupTitle ?? current.title
        let nextShotOrdinal = sessions.filter { $0.sourceRecordingID == current.id }.count
        let created = pending.enumerated().compactMap { offset, bookmark -> ReviewSession? in
            let range = bookmark.clipRange(sourceDuration: current.duration)
            guard range.duration > 0 else { return nil }
            let candidate = ReviewCandidate(
                ordinal: 1,
                impactTime: min(max(0, bookmark.sourceTime), current.duration),
                sourceDuration: current.duration,
                classification: .uncertain,
                confidence: .low,
                evidence: ["Created from a manual bookmark", "Ball flight not tracked"],
                tracerAvailable: false,
                tracerSource: .unavailable,
                usesFullSourceRange: false
            )
            var shot = ReviewSession(
                id: UUID(),
                mode: .range,
                importKind: .oneShot,
                title: "\(groupTitle) shot \(nextShotOrdinal + offset + 1)",
                sourceName: current.sourceName,
                sourceURL: current.sourceURL,
                sourceRelativePath: current.sourceRelativePath,
                videoEdit: ShotVideoEdit(trimStart: range.start, trimEnd: range.end, overlay: .original),
                createdAt: .now,
                duration: current.duration,
                sourceAspectRatio: current.sourceAspectRatio,
                status: .reviewing,
                progress: 1,
                candidates: [candidate],
                placeName: current.placeName,
                clubName: current.clubName,
                note: "",
                isFavourite: false,
                errorMessage: nil,
                sourceClipRange: range
            )
            shot.groupID = groupID
            shot.groupTitle = groupTitle
            shot.sourceRecordingID = current.id
            shot.sourceBookmarkID = bookmark.id
            return shot
        }
        guard !created.isEmpty, mutateAtomically({ rows in
            rows.insert(contentsOf: created.reversed(), at: 0)
        }) else { return [] }
        if let first = created.first { select(first) }
        return created.map(\.id)
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

    @discardableResult
    func setVideoEdit(_ edit: ShotVideoEdit, for session: ReviewSession) -> Bool {
        updateSession(session) { $0.videoEdit = edit }
    }

    @discardableResult
    func delete(_ session: ReviewSession) async -> Bool {
        guard let owner = captureImportOwnership(),
              let current = sessions.first(where: { $0.id == session.id }) else { return false }
        if current.isRecording,
           sessions.contains(where: { $0.sourceRecordingID == current.id }) {
            libraryError = "Remove this recording's shots before removing the original recording."
            return false
        }
        let previous = sessions
        let wasUnsaved = hasUnsavedChanges
        sessions.removeAll { $0.id == session.id }
        guard persistSessions() else {
            sessions = previous
            hasUnsavedChanges = wasUnsaved
            libraryError = "The deletion could not be saved. Your review and video have been kept. Try again."
            return false
        }
        cancelAnalysis(for: current)
        analysisOperations[current.id] = nil
        if selectedSessionID == session.id {
            selectedSessionID = sessions.first?.id
            selectedCandidateID = sessions.first?.defaultCandidate?.id
        }
        if let sourceURL = current.sourceURL, !hasRemainingMediaReference(to: current) {
            do {
                try await mediaStore?.delete(sourceURL)
            } catch {
                if ownsLibrary(owner) {
                    libraryError = "The review was removed, but its local video could not be cleared from storage."
                }
            }
        }
        return true
    }

    /// Produces a local MOV using the exact geometry already stored on the selected candidate.
    /// It is intentionally separate from analysis: sharing a video cannot rerun detection, invent
    /// missing points, or turn a manual rescue into observed flight.
    func exportTracedVideo(for candidate: ReviewCandidate, in session: ReviewSession) async throws -> URL {
        guard let ownership = captureImportOwnership(),
              sessions.contains(where: { $0.id == session.id }), let sourceURL = session.sourceURL else {
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
        guard ownsLibrary(ownership), !Task.isCancelled else {
            try? FileManager.default.removeItem(at: output)
            throw CancellationError()
        }
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
            evidence: ["Added manually"],
            usesFullSourceRange: session.isSingleShotImport
        )
        updateSession(session) { $0.candidates.append(marker); $0.status = .reviewing }
        selectedCandidateID = marker.id
    }

    @discardableResult
    func importVideo(
        at sourceURL: URL,
        sourceName: String,
        importKind: ReviewImportKind,
        groupID: UUID? = nil,
        groupTitle: String? = nil,
        ownership: ReviewImportOwnership? = nil,
        onPrepared: (@MainActor (ReviewSession) -> Void)? = nil
    ) async -> ReviewImportResult {
        guard let owner = ownership ?? captureImportOwnership() else {
            return .failed(libraryError ?? "Open your local library before importing a video.")
        }
        guard ownsLibrary(owner), !Task.isCancelled else { return .cancelled }
        let operationID = UUID()
        let task = Task { @MainActor in
            await self.performImport(
                at: sourceURL, sourceName: sourceName, importKind: importKind,
                groupID: groupID, groupTitle: groupTitle,
                ownership: owner, operationID: operationID, onPrepared: onPrepared
            )
        }
        return await awaitOperation(task, id: operationID)
    }

    @discardableResult
    func retryAnalysis(for session: ReviewSession) async -> ReviewImportResult {
        guard let owner = captureImportOwnership(),
              sessions.contains(where: { $0.id == session.id }) else {
            return .failed(libraryError ?? "This review is no longer in the open library.")
        }
        guard !session.isRecording, !session.isDerivedShot else {
            return .failed("Automatic analysis is unavailable for manually bookmarked recordings and source-linked shots.")
        }
        guard analysisOperations[session.id] == nil else {
            return .failed("This video is already being analysed.")
        }
        let operationID = UUID()
        analysisOperations[session.id] = operationID
        let task = Task { @MainActor in
            await self.performAnalysis(sessionID: session.id, ownership: owner, operationID: operationID)
        }
        return await awaitOperation(task, id: operationID)
    }

    func cancelAnalysis(for session: ReviewSession) {
        guard let operationID = analysisOperations[session.id] else { return }
        operations[operationID]?.cancel()
    }

    private func awaitOperation(_ task: Task<ReviewImportResult, Never>, id: UUID) async -> ReviewImportResult {
        operations[id] = task
        isBusy = true
        let result = await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
        operations[id] = nil
        analysisOperations = analysisOperations.filter { $0.value != id }
        isBusy = !operations.isEmpty
        return result
    }

    private func performImport(
        at sourceURL: URL,
        sourceName: String,
        importKind: ReviewImportKind,
        groupID: UUID?,
        groupTitle: String?,
        ownership: ReviewImportOwnership,
        operationID: UUID,
        onPrepared: (@MainActor (ReviewSession) -> Void)?
    ) async -> ReviewImportResult {
        guard let mediaStore else { return .failed("Ronde could not prepare local media storage.") }
        var stagedURL: URL?
        do {
            try Task.checkCancellation()
            guard ownsLibrary(ownership) else { return .cancelled }
            let reference = try await mediaStore.importVideo(at: sourceURL)
            let localURL = try await mediaStore.url(for: reference)
            stagedURL = localURL
            try Task.checkCancellation()
            guard ownsLibrary(ownership) else { throw CancellationError() }

            let metadata = try await metadataProbe.probe(url: localURL)
            try Task.checkCancellation()
            guard ownsLibrary(ownership) else { throw CancellationError() }
            let duration = metadata.duration
            guard duration.isFinite, duration > 0,
                  importKind != .oneShot || ShotVideoImportPolicy.accepts(duration: duration),
                  importKind != .recording || RecordingImportPolicy.accepts(duration: duration) else {
                try? await mediaStore.delete(localURL)
                return .failed(importKind == .recording
                    ? "Choose a recording that is 20 minutes or shorter."
                    : "Choose one shot video that is 1 minute or shorter.")
            }
            var session = makeSession(
                title: sourceName, sourceName: reference.originalFilename, sourceURL: localURL,
                duration: duration, importKind: importKind,
                status: importKind == .recording ? .reviewing : .analysing,
                progress: importKind == .recording ? 1 : 0,
                errorMessage: nil
            )
            session.sourceRelativePath = reference.relativePath
            session.sourceAspectRatio = metadata.displayAspectRatio
            if importKind == .recording {
                session.groupID = groupID ?? session.id
                session.groupTitle = Self.cleanOptional(groupTitle ?? sourceName, limit: 160) ?? session.title
            } else if let groupID {
                session.groupID = groupID
                session.groupTitle = Self.cleanOptional(groupTitle ?? sourceName, limit: 160)
            }
            let priorSelection = selectedSessionID
            let priorCandidate = selectedCandidateID
            let wasUnsaved = hasUnsavedChanges
            sessions.insert(session, at: 0)
            select(session)
            guard persistSessions() else {
                sessions.removeAll { $0.id == session.id }
                selectedSessionID = priorSelection
                selectedCandidateID = priorCandidate
                hasUnsavedChanges = wasUnsaved
                try? await mediaStore.delete(localURL)
                return .failed(libraryError ?? "The video could not be saved. Your original is unchanged.")
            }
            stagedURL = nil // The durable archive now owns the copied source.
            onPrepared?(session)
            if importKind == .recording { return .imported(session) }
            return await performAnalysis(sessionID: session.id, ownership: ownership, operationID: operationID)
        } catch {
            if let stagedURL { try? await mediaStore.delete(stagedURL) }
            if error is CancellationError || Task.isCancelled || !ownsLibrary(ownership) { return .cancelled }
            return .failed("The video could not be imported. Check that it is available and your device has free storage.")
        }
    }

    private func performAnalysis(
        sessionID: UUID,
        ownership: ReviewImportOwnership,
        operationID: UUID
    ) async -> ReviewImportResult {
        guard ownsLibrary(ownership), let initial = sessions.first(where: { $0.id == sessionID }) else { return .cancelled }
        guard !initial.isRecording, !initial.isDerivedShot else {
            return .failed("Automatic analysis is unavailable for manually bookmarked recordings and source-linked shots.")
        }
        guard analysisOperations[sessionID] == nil || analysisOperations[sessionID] == operationID else {
            return .failed("This video is already being analysed.")
        }
        guard let sourceURL = initial.sourceURL, FileManager.default.fileExists(atPath: sourceURL.path) else {
            updateSession(initial) {
                $0.status = .needsAttention
                $0.errorMessage = "The local video is unavailable. Import the original again to analyse it."
            }
            return .failed("The local source video is unavailable.")
        }
        analysisOperations[sessionID] = operationID
        defer {
            if analysisOperations[sessionID] == operationID { analysisOperations[sessionID] = nil }
        }
        updateSession(initial) { $0.status = .analysing; $0.progress = 0; $0.errorMessage = nil }
        do {
            try Task.checkCancellation()
            var candidates: [ReviewCandidate]
            if initial.importKind == .rangeSession {
                candidates = try await analyseLongSession(
                    url: sourceURL, duration: initial.duration, sessionID: sessionID,
                    ownership: ownership, operationID: operationID
                )
            } else {
                candidates = try await analyseSingleShot(
                    url: sourceURL, duration: initial.duration, sessionID: sessionID,
                    ownership: ownership, operationID: operationID
                )
            }
            try Task.checkCancellation()
            guard ownsLibrary(ownership), let current = sessions.first(where: { $0.id == sessionID }) else { return .cancelled }
            // Retrying automatic analysis must not discard a person's separately saved trace.
            if current.isSingleShotImport, let manual = current.defaultCandidate?.assistedTracer {
                if candidates.isEmpty, let previous = current.defaultCandidate {
                    candidates = [previous]
                } else if !candidates.isEmpty {
                    candidates[0].assistedTracer = manual
                    candidates[0].tracerAvailable = true
                    if !candidates[0].evidence.contains("User-assisted tracer") { candidates[0].evidence.append("User-assisted tracer") }
                }
            }
            updateSession(current) {
                $0.candidates = candidates
                $0.progress = 1
                $0.status = candidates.isEmpty ? .needsAttention : .reviewing
                $0.errorMessage = candidates.isEmpty ? "Ball flight not tracked. Play the original or add a manual trace." : nil
            }
            guard let finished = sessions.first(where: { $0.id == sessionID }) else { return .cancelled }
            if selectedSessionID == sessionID {
                selectedCandidateID = finished.defaultCandidate?.id
                playheadTime = finished.defaultCandidate?.impactTime ?? 0
            }
            return .imported(finished)
        } catch {
            guard ownsLibrary(ownership), let current = sessions.first(where: { $0.id == sessionID }) else { return .cancelled }
            let wasCancelled = error is CancellationError || Task.isCancelled
            updateSession(current) {
                $0.status = .needsAttention
                $0.errorMessage = wasCancelled
                    ? "Analysis was interrupted. Play the original or try again."
                    : "Automatic analysis could not finish. Play the original or try again."
            }
            if wasCancelled { return .cancelled }
            return sessions.first(where: { $0.id == sessionID }).map(ReviewImportResult.imported)
                ?? .failed("This review is no longer available.")
        }
    }

    private func updateAnalysisProgress(
        _ progress: Double, sessionID: UUID,
        ownership: ReviewImportOwnership, operationID: UUID
    ) {
        guard ownsLibrary(ownership), analysisOperations[sessionID] == operationID,
              let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        // Progress is transient. Persisting every callback rewrote the full archive on the UI actor.
        sessions[index].progress = min(max(progress, 0), 1)
    }

    /// Short clips remain a direct review flow. A tracer is added only when the on-device
    /// sports-ball model and temporal linker establish an observed source-frame track.
    private func analyseSingleShot(
        url: URL,
        duration: TimeInterval,
        sessionID: UUID,
        ownership: ReviewImportOwnership,
        operationID: UUID
    ) async throws -> [ReviewCandidate] {
        let candidates = try await impactAnalysisService.analyse(url: url) { [weak self] progress in
            guard let self else { return }
            Task { @MainActor in
                self.updateAnalysisProgress(progress * 0.72, sessionID: sessionID, ownership: ownership, operationID: operationID)
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
                self.updateAnalysisProgress(0.72 + progress * 0.27, sessionID: sessionID, ownership: ownership, operationID: operationID)
            }
        }
        try Task.checkCancellation()
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
        sessionID: UUID,
        ownership: ReviewImportOwnership,
        operationID: UUID
    ) async throws -> [ReviewCandidate] {
        let result = await longSessionAnalysisService.analyse(
            url: url,
            sourceDuration: duration
        ) { [weak self] progress in
            guard let self else { return }
            Task { @MainActor in
                self.updateAnalysisProgress(progress * 0.82, sessionID: sessionID, ownership: ownership, operationID: operationID)
            }
        }

        var acceptedCandidates: [ReviewCandidate] = []
        acceptedCandidates.reserveCapacity(result.acceptedShots.count)
        for (index, shot) in result.acceptedShots.enumerated() {
            try Task.checkCancellation()
            let trackedFlight = try? await ballTrackingService.analyse(
                url: url,
                impactTime: shot.impactTime
            )
            let flight = trackedFlight.flatMap { $0.isDisplayable ? $0 : nil }
            let automaticPath = flight.flatMap { flightPathExtrapolator.path(from: $0, impactTime: shot.impactTime) }
            let progress = 0.82 + (0.17 * (Double(index + 1) / Double(max(result.acceptedShots.count, 1))))
            updateAnalysisProgress(progress, sessionID: sessionID, ownership: ownership, operationID: operationID)
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
        guard canModifyLibrary else { return session }
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

    @discardableResult
    private func updateSession(_ session: ReviewSession, _ update: (inout ReviewSession) -> Void) -> Bool {
        guard canModifyLibrary, let index = sessions.firstIndex(where: { $0.id == session.id }) else { return false }
        update(&sessions[index])
        return persistSessions()
    }

    /// Applies a multi-row local mutation only when the replacement archive can be written. This
    /// is used for bookmark extraction so a failed save cannot leave duplicate or orphaned shots
    /// in the visible in-memory library.
    @discardableResult
    private func mutateAtomically(_ mutation: (inout [ReviewSession]) -> Void) -> Bool {
        guard canModifyLibrary else { return false }
        let previousSessions = sessions
        let previousSelection = selectedSessionID
        let previousCandidate = selectedCandidateID
        let wasUnsaved = hasUnsavedChanges
        mutation(&sessions)
        guard persistSessions() else {
            sessions = previousSessions
            selectedSessionID = previousSelection
            selectedCandidateID = previousCandidate
            hasUnsavedChanges = wasUnsaved
            libraryError = "The change could not be saved. Your recording and existing shots have been kept. Try again."
            return false
        }
        return true
    }

    private func hasRemainingMediaReference(to session: ReviewSession) -> Bool {
        sessions.contains { other in
            if let relative = session.sourceRelativePath, other.sourceRelativePath == relative { return true }
            guard let sourceURL = session.sourceURL, let otherURL = other.sourceURL else { return false }
            return sourceURL.standardizedFileURL == otherURL.standardizedFileURL
        }
    }

    private func updateCandidate(_ candidate: ReviewCandidate, in session: ReviewSession, _ update: (inout ReviewCandidate) -> Void) {
        guard canModifyLibrary, let sessionIndex = sessions.firstIndex(where: { $0.id == session.id }),
              let candidateIndex = sessions[sessionIndex].candidates.firstIndex(where: { $0.id == candidate.id }) else { return }
        update(&sessions[sessionIndex].candidates[candidateIndex])
        persistSessions()
    }

    @discardableResult
    private func persistSessions() -> Bool {
        guard persistenceEnabled else { return true }
        guard canModifyLibrary, let archive else {
            libraryError = libraryError ?? "Open your existing library before saving changes."
            return false
        }
        do {
            try archive.save(sessions)
            hasUnsavedChanges = false
            libraryError = nil
            return true
        } catch {
            hasUnsavedChanges = true
            libraryError = "Your latest changes have not been saved. Check free storage, then try saving again."
            return false
        }
    }

    private static func cleanOptional(_ value: String, limit: Int) -> String? {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : String(cleaned.prefix(limit))
    }
}
