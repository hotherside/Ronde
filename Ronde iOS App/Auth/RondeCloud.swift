import Foundation
import Supabase

struct RondeCloudConfiguration: Sendable {
    let url: URL
    let publishableKey: String

    init?(bundle: Bundle = .main) {
        let urlValue = (bundle.object(forInfoDictionaryKey: "RondeSupabaseURL") as? String)
            ?? "https://apaowuzliauwxbxylfpk.supabase.co"
        let key = (bundle.object(forInfoDictionaryKey: "RondeSupabasePublishableKey") as? String)
            ?? "sb_publishable_pXFjmdTpYoGk4SwgD0PLuA_J0YUtv67"
        guard
              let url = URL(string: urlValue),
              !key.isEmpty else {
            return nil
        }
        self.url = url
        publishableKey = key
    }
}

struct RondeAccount: Equatable, Sendable {
    let id: UUID
    let displayName: String?
    let email: String?

    var initials: String {
        let source = displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = (source?.isEmpty == false ? source! : "Ronde Golfer")
            .split(separator: " ")
            .prefix(2)
        return parts.compactMap(\.first).map(String.init).joined().uppercased()
    }
}

enum RondeCloudSyncState: Equatable {
    case localOnly
    case syncing
    case synced(Date)
    case failed

    var label: String {
        switch self {
        case .localOnly: "Waiting to sync"
        case .syncing: "Syncing metadata"
        case .synced: "Metadata up to date"
        case .failed: "Metadata sync paused"
        }
    }
}

@MainActor
final class RondeCloudRepository {
    static var live: RondeCloudRepository? {
        guard let configuration = RondeCloudConfiguration() else { return nil }
        return RondeCloudRepository(configuration: configuration)
    }

    private struct ProfileRow: Codable {
        let id: UUID
        let displayName: String?

        enum CodingKeys: String, CodingKey {
            case id
            case displayName = "display_name"
        }
    }

    private struct ProfileUpdate: Encodable {
        let displayName: String

        enum CodingKeys: String, CodingKey {
            case displayName = "display_name"
        }
    }

    private struct LibraryItemRow: Encodable {
        let id: UUID
        let userID: UUID
        let title: String
        let sourceName: String?
        let capturedAt: Date
        let durationSeconds: Double
        let placeName: String?
        let clubName: String?
        let note: String
        let isFavourite: Bool
        let traceProvenance: String
        let observedPointCount: Int
        let estimatedCarryLowerMetres: Int?
        let estimatedCarryUpperMetres: Int?
        let deviceUpdatedAt: Date

        enum CodingKeys: String, CodingKey {
            case id
            case userID = "user_id"
            case title
            case sourceName = "source_name"
            case capturedAt = "captured_at"
            case durationSeconds = "duration_seconds"
            case placeName = "place_name"
            case clubName = "club_name"
            case note
            case isFavourite = "is_favourite"
            case traceProvenance = "trace_provenance"
            case observedPointCount = "observed_point_count"
            case estimatedCarryLowerMetres = "estimated_carry_lower_metres"
            case estimatedCarryUpperMetres = "estimated_carry_upper_metres"
            case deviceUpdatedAt = "device_updated_at"
        }
    }

    private let client: SupabaseClient

    init(configuration: RondeCloudConfiguration) {
        client = SupabaseClient(
            supabaseURL: configuration.url,
            supabaseKey: configuration.publishableKey,
            options: SupabaseClientOptions(auth: .init(emitLocalSessionAsInitialSession: true))
        )
    }

    func currentAccount() async -> RondeAccount? {
        guard let session = try? await client.auth.session, !session.isExpired else { return nil }
        let profiles: [ProfileRow] = (try? await client
            .from("profiles")
            .select("id, display_name")
            .eq("id", value: session.user.id)
            .limit(1)
            .execute()
            .value) ?? []
        return RondeAccount(
            id: session.user.id,
            displayName: profiles.first?.displayName,
            email: session.user.email
        )
    }

    func signInWithApple(identityToken: String, nonce: String, fullName: String?) async throws -> RondeAccount {
        let session = try await client.auth.signInWithIdToken(
            credentials: OpenIDConnectCredentials(provider: .apple, idToken: identityToken, nonce: nonce)
        )
        let cleanName = fullName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let cleanName, !cleanName.isEmpty {
            try await client
                .from("profiles")
                .update(ProfileUpdate(displayName: String(cleanName.prefix(80))))
                .eq("id", value: session.user.id)
                .execute()
        }
        return await currentAccount()
            ?? RondeAccount(id: session.user.id, displayName: cleanName, email: session.user.email)
    }

    func signOut() async throws {
        try await client.auth.signOut(scope: .local)
    }

    func syncLibrary(_ sessions: [ReviewSession], accountID: UUID) async throws {
        guard !sessions.isEmpty else { return }
        let rows = sessions.map { session in
            let candidate = session.defaultCandidate
            let carry = candidate?.evidenceAnchoredPath?.estimatedCarry
            return LibraryItemRow(
                id: session.id,
                userID: accountID,
                title: session.title,
                sourceName: session.sourceName,
                capturedAt: session.createdAt,
                durationSeconds: min(max(session.duration, 0), ShotVideoImportPolicy.maximumDuration),
                placeName: session.placeName,
                clubName: session.clubName,
                note: session.note,
                isFavourite: session.isFavourite,
                traceProvenance: Self.traceProvenance(for: candidate),
                observedPointCount: candidate?.observedTracerPointCount ?? 0,
                estimatedCarryLowerMetres: carry?.lowerMetres,
                estimatedCarryUpperMetres: carry?.upperMetres,
                deviceUpdatedAt: .now
            )
        }
        try await client.from("library_items").upsert(rows).execute()
    }

    func deleteLibraryItem(id: UUID) async throws {
        try await client.from("library_items").delete().eq("id", value: id).execute()
    }

    private static func traceProvenance(for candidate: ReviewCandidate?) -> String {
        guard let candidate else { return "unavailable" }
        if candidate.hasManualTracer { return "manual" }
        switch candidate.tracerSource {
        case .unavailable: return "unavailable"
        case .observed: return "observed"
        case .observedAndInferred: return "observed_and_estimated"
        case .inferred: return "manual"
        }
    }
}

@MainActor
final class RondeAccountStore: ObservableObject {
    @Published private(set) var isCheckingSession: Bool
    @Published private(set) var account: RondeAccount?
    @Published private(set) var syncState: RondeCloudSyncState = .localOnly
    @Published var authenticationError: String?

    private let cloud: RondeCloudRepository?
    private var hasRestoredSession = false

    init(previewAccount: RondeAccount? = nil) {
        account = previewAccount
        isCheckingSession = previewAccount == nil
        cloud = previewAccount == nil ? RondeCloudRepository.live : nil
    }

    var isConfigured: Bool { cloud != nil || account != nil }

    func restoreSession() async {
        guard !hasRestoredSession else { return }
        hasRestoredSession = true
        guard let cloud else {
            isCheckingSession = false
            return
        }
        account = await cloud.currentAccount()
        isCheckingSession = false
    }

    func signInWithApple(identityToken: String, nonce: String, fullName: String?) async {
        guard let cloud else {
            authenticationError = "This build is missing its Ronde cloud configuration."
            return
        }
        authenticationError = nil
        do {
            account = try await cloud.signInWithApple(
                identityToken: identityToken,
                nonce: nonce,
                fullName: fullName
            )
        } catch {
            authenticationError = "Apple sign-in could not finish. Check your connection and try again."
        }
    }

    func signOut() async {
        guard let cloud else {
            account = nil
            return
        }
        do {
            try await cloud.signOut()
            account = nil
            syncState = .localOnly
        } catch {
            authenticationError = "Ronde could not sign out on this device. Try again."
        }
    }

    func synchronise(_ sessions: [ReviewSession]) async {
        guard let cloud, let account else { return }
        syncState = .syncing
        do {
            try await cloud.syncLibrary(sessions, accountID: account.id)
            syncState = .synced(.now)
        } catch {
            syncState = .failed
        }
    }

    func deleteRemoteLibraryItem(id: UUID) async {
        try? await cloud?.deleteLibraryItem(id: id)
    }
}
