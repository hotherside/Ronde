import AuthenticationServices
import AVFoundation
import Combine
import SwiftUI

// Retains debug preview links while the product has one library, not three tabs.
enum RondeAppTab: Hashable { case home, library, profile }

struct RondeRootView: View {
    @ObservedObject var store: ReviewerStore
    @ObservedObject var accountStore: RondeAccountStore
    var initialTab: RondeAppTab = .library

    var body: some View {
        Group {
            if accountStore.isCheckingSession {
                ProgressView("Opening Ronde")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .reviewCanvasBackground()
            } else if accountStore.account != nil {
                RondeAppShell(store: store, accountStore: accountStore, initialSelection: initialTab)
            } else {
                RondeSignInView(accountStore: accountStore)
            }
        }
        .task { await accountStore.restoreSession() }
        .onChange(of: accountStore.account?.id) { old, new in
            if old != nil && new == nil { store.deactivateLibrary() }
        }
    }
}

struct RondeSignInView: View {
    @ObservedObject var accountStore: RondeAccountStore
    @State private var currentNonce: String?
    @State private var isSigningIn = false

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 36) {
                    Label("Ronde", systemImage: "viewfinder")
                        .font(.title2.weight(.semibold))
                    Spacer(minLength: 32)
                    VStack(alignment: .leading, spacing: 18) {
                        Text("Your swing.\nWorth another look.")
                            .font(.largeTitle.weight(.bold))
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Review your shots. Shape the clip. Share the moment.")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    // A graphic identity, never an example of measured flight.
                    HStack(spacing: 4) {
                        ForEach(0..<24) { index in
                            RoundedRectangle(cornerRadius: 3)
                                .fill(index == 14 ? RondeReviewDesign.tracerPurple : Color.primary.opacity(0.08))
                                .frame(height: index == 14 ? 88 : 40 + CGFloat((index * 13) % 40))
                        }
                    }
                    .frame(height: 96)
                    .accessibilityHidden(true)
                    Spacer(minLength: 32)
                    VStack(spacing: 18) {
                        SignInWithAppleButton(.continue) { request in
                            request.requestedScopes = [.fullName, .email]
                            do {
                                let nonce = try AppleSignInNonce.make()
                                currentNonce = nonce
                                request.nonce = AppleSignInNonce.hashed(nonce)
                                accountStore.authenticationError = nil
                            } catch {
                                accountStore.authenticationError = "Could not prepare Apple sign-in. Try again."
                            }
                        } onCompletion: { completeAppleSignIn($0) }
                        .signInWithAppleButtonStyle(.black)
                        .frame(height: 54)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .disabled(isSigningIn || !accountStore.isConfigured)
                        .accessibilityIdentifier("ronde-apple-sign-in")
                        if isSigningIn { ProgressView("Signing in…") }
                        if let error = accountStore.authenticationError {
                            Text(error).foregroundStyle(RondeReviewDesign.red)
                        }
                        Text("Videos stay on this device. Your account syncs library details only.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(28)
                .frame(maxWidth: 560, minHeight: geometry.size.height, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
        .reviewCanvasBackground()
    }

    private func completeAppleSignIn(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .failure(let error):
            currentNonce = nil
            if let authorisationError = error as? ASAuthorizationError,
               authorisationError.code == .canceled {
                return
            }
            accountStore.authenticationError = "Apple sign-in was interrupted. Check your connection and try again."
        case .success(let authorisation):
            guard let credential = authorisation.credential as? ASAuthorizationAppleIDCredential,
                  let nonce = currentNonce,
                  let tokenData = credential.identityToken,
                  let identityToken = String(data: tokenData, encoding: .utf8) else {
                currentNonce = nil
                accountStore.authenticationError = "Apple did not return the secure sign-in details Ronde needs. Try again."
                return
            }
            let name = PersonNameComponentsFormatter().string(from: credential.fullName ?? PersonNameComponents())
            isSigningIn = true
            Task {
                await accountStore.signInWithApple(
                    identityToken: identityToken,
                    nonce: nonce,
                    fullName: name.isEmpty ? nil : name
                )
                currentNonce = nil
                isSigningIn = false
            }
        }
    }
}


struct RondeAppShell: View {
    @ObservedObject var store: ReviewerStore
    @ObservedObject var accountStore: RondeAccountStore
    @State private var path: [UUID] = []
    @State private var search = ""
    @State private var favouritesOnly = false
    @State private var showsImport = false
    @State private var showsSettings = false
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.horizontalSizeClass) private var sizeClass

    init(store: ReviewerStore, accountStore: RondeAccountStore, initialSelection: RondeAppTab = .library) {
        self.store = store
        self.accountStore = accountStore
        _showsSettings = State(initialValue: initialSelection == .profile)
    }

    private var visibleSessions: [ReviewSession] {
        store.sessions.filter { session in
            (!favouritesOnly || session.isFavourite) &&
            (search.isEmpty || [session.title, session.placeName ?? "", session.clubName ?? "", session.note]
                .joined(separator: " ").localizedCaseInsensitiveContains(search))
        }.sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if let error = store.libraryError {
                        LibrarySaveNotice(store: store, message: error)
                    }
                    if !store.sessions.isEmpty {
                        Picker("Library filter", selection: $favouritesOnly) {
                            Text("All shots").tag(false)
                            Text("Favourites").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 340)
                        .accessibilityIdentifier("library-filter")
                    }
                    if visibleSessions.isEmpty {
                        emptyLibrary
                    } else {
                        LazyVGrid(columns: sizeClass == .regular ? [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 360 : 280), spacing: 24)] : [GridItem(.flexible())], alignment: .leading, spacing: 28) {
                            ForEach(visibleSessions) { session in
                                NavigationLink(value: session.id) {
                                    ShotLibraryCard(session: session)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button(session.isFavourite ? "Remove favourite" : "Favourite", systemImage: session.isFavourite ? "star.slash" : "star") {
                                        store.toggleFavourite(session)
                                    }
                                    .disabled(!store.canModifyLibrary)
                                }
                            }
                        }
                    }
                }
                .padding(sizeClass == .regular ? 32 : 20)
                .frame(maxWidth: 1500, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .reviewCanvasBackground()
            .navigationTitle("Shot library")
            .searchable(text: $search, prompt: "Find a shot")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showsSettings = true } label: {
                        Image(systemName: "sidebar.left")
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel("Library settings")
                    .accessibilityIdentifier("library-settings")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { showsImport = true } label: {
                        Label("Add video", systemImage: "plus")
                            .fontWeight(.semibold)
                    }
                    .disabled(!store.canModifyLibrary)
                    .accessibilityIdentifier("add-video")
                }
            }
            .navigationDestination(for: UUID.self) { id in
                RondeMediaDetailRoute(store: store, accountStore: accountStore, sessionID: id)
            }
            .sheet(isPresented: $showsImport) {
                RangeSessionEntryView(store: store, intent: .oneShot) { session in
                    store.select(session)
                    path.append(session.id)
                }
            }
            .sheet(isPresented: $showsSettings) {
                RondeSettingsView(store: store, accountStore: accountStore)
            }
        }
        .tint(RondeReviewDesign.graphite)
        .task(id: accountStore.account?.id) {
            guard let account = accountStore.account else { store.deactivateLibrary(); return }
            store.activateLibrary(for: account.id)
            await accountStore.synchronise(store.sessions)
        }
        .onReceive(store.$sessions.dropFirst().debounce(for: .seconds(1.2), scheduler: RunLoop.main)) { sessions in
            guard store.libraryError == nil else { return }
            Task { await accountStore.synchronise(sessions) }
        }
    }

    private var emptyLibrary: some View {
        ContentUnavailableView {
            Label(search.isEmpty && !favouritesOnly ? "Make room for a great shot." : "No shots found", systemImage: "play.rectangle.on.rectangle")
        } description: {
            Text(search.isEmpty && !favouritesOnly ? "Add a video to review, trim and share." : "Try another search or save a favourite.")
        } actions: {
            if search.isEmpty && !favouritesOnly {
                Button("Add your first video") { showsImport = true }
                    .buttonStyle(ReviewPrimaryButtonStyle(tint: RondeReviewDesign.graphite))
                    .disabled(!store.canModifyLibrary)
            }
        }
        .padding(.vertical, 40)
    }
}

private struct ShotLibraryCard: View {
    let session: ReviewSession

    private var subtitle: String {
        let context = [session.clubName, session.placeName].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        return context.isEmpty ? session.createdAt.formatted(.dateTime.day().month(.abbreviated)) : context
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ShotPoster(sourceURL: session.sourceURL, time: session.defaultCandidate?.impactTime ?? 0)
                .aspectRatio(16 / 10, contentMode: .fit)
                .overlay(alignment: .bottomTrailing) {
                    Text(Self.duration(session.duration))
                        .font(.subheadline.monospacedDigit().weight(.medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 6))
                        .padding(12)
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(session.title).font(.headline).lineLimit(2)
                Spacer(minLength: 0)
                if session.isFavourite {
                    Image(systemName: "star.fill").foregroundStyle(RondeReviewDesign.graphiteMuted)
                        .accessibilityLabel("Favourite")
                }
            }
            Text(session.status == .analysing ? "Finding your shot…" : subtitle)
                .font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
        }
        .foregroundStyle(RondeReviewDesign.graphite)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("shot-card-\(session.id)")
    }

    private static func duration(_ value: Double) -> String {
        let seconds = Int(max(0, value.isFinite ? value : 0))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

private struct ShotPoster: View {
    let sourceURL: URL?
    let time: Double
    @State private var thumbnail: CGImage?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color(white: 0.92)
                if let thumbnail {
                    Image(decorative: thumbnail, scale: 1)
                        .resizable().scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                } else {
                    Image(systemName: "play.rectangle")
                        .font(.largeTitle).foregroundStyle(.tertiary)
                }
            }
        }
        .accessibilityHidden(true)
        .task(id: "\(sourceURL?.absoluteString ?? "missing")-\(time)") {
            thumbnail = nil
            guard let sourceURL else { return }
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: sourceURL))
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 900, height: 900)
            if let result = try? await generator.image(at: CMTime(seconds: max(0, time), preferredTimescale: 600)), !Task.isCancelled {
                thumbnail = result.image
            }
        }
    }
}

struct LibrarySaveNotice: View {
    @ObservedObject var store: ReviewerStore
    let message: String
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Your library needs attention", systemImage: "exclamationmark.circle")
                .font(.headline)
            Text(message).font(.body)
            Button("Try again") {
                if store.hasUnsavedChanges { store.retrySavingLibrary() }
                else { store.retryLibraryLoad() }
            }
            .buttonStyle(ReviewSecondaryButtonStyle())
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RondeReviewDesign.amberWash, in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct RondeSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: ReviewerStore
    @ObservedObject var accountStore: RondeAccountStore
    @State private var confirmingSignOut = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Account") {
                    if let account = accountStore.account {
                        Text(account.displayName ?? "Ronde Golfer").font(.headline)
                        if let email = account.email { Text(email).foregroundStyle(.secondary) }
                    }
                }
                Section {
                    LabeledContent("Library details", value: accountStore.syncState.label)
                    if accountStore.syncState == .failed {
                        Button("Retry sync") { Task { await accountStore.synchronise(store.sessions) } }
                    }
                } header: { Text("Storage") } footer: {
                    Text("Videos, traces and edits stay on this device. Your account syncs titles, places and favourites. Keep original videos in Photos or Files for backup.")
                }
                if let error = accountStore.authenticationError {
                    Section { Text(error).foregroundStyle(RondeReviewDesign.red) }
                }
                Section {
                    Button("Sign out", role: .destructive) { confirmingSignOut = true }
                        .disabled(store.hasUnsavedChanges)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .confirmationDialog("Sign out of Ronde?", isPresented: $confirmingSignOut, titleVisibility: .visible) {
                Button("Sign out", role: .destructive) {
                    Task {
                        await accountStore.signOut()
                        if accountStore.account == nil { dismiss() }
                    }
                }
            } message: { Text("Your local library stays on this device for this account.") }
        }
    }
}

struct RondeMediaDetailRoute: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: ReviewerStore
    @ObservedObject var accountStore: RondeAccountStore
    let sessionID: UUID
    @State private var isEditingDetails = false

    var body: some View {
        ShotStudioView(store: store, sessionID: sessionID, onEditDetails: { isEditingDetails = true })
            .sheet(isPresented: $isEditingDetails) {
                RondeMediaDetailsEditor(store: store, accountStore: accountStore, sessionID: sessionID, onDeleted: { dismiss() })
            }
    }
}

private struct RondeMediaDetailsEditor: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: ReviewerStore
    @ObservedObject var accountStore: RondeAccountStore
    let sessionID: UUID
    let onDeleted: () -> Void
    @State private var title = ""
    @State private var placeName = ""
    @State private var clubName = ""
    @State private var note = ""
    @State private var showsDeleteConfirmation = false
    private var session: ReviewSession? { store.sessions.first { $0.id == sessionID } }

    var body: some View {
        NavigationStack {
            Form {
                Section("Shot details") {
                    TextField("Title", text: $title)
                        .accessibilityIdentifier("shot-title-field")
                    TextField("Course or range", text: $placeName).textContentType(.location)
                    TextField("Club", text: $clubName)
                    TextField("Notes", text: $note, axis: .vertical).lineLimit(3...7)
                }
                if let error = store.libraryError { Section { LibrarySaveNotice(store: store, message: error) } }
                Section {
                    Button("Delete shot", role: .destructive) { showsDeleteConfirmation = true }
                        .disabled(!store.canModifyLibrary)
                } footer: {
                    Text("Your original video in Photos or Files is kept.")
                }
            }
            .navigationTitle("Shot details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let session else { return }
                        store.updateDetails(for: session, title: title, placeName: placeName, clubName: clubName, note: note)
                        if store.libraryError == nil { dismiss() }
                    }
                    .fontWeight(.semibold)
                    .disabled(!store.canModifyLibrary)
                }
            }
            .task {
                guard let session else { return }
                title = session.title
                placeName = session.placeName ?? ""
                clubName = session.clubName ?? ""
                note = session.note
            }
            .confirmationDialog("Delete this shot?", isPresented: $showsDeleteConfirmation, titleVisibility: .visible) {
                Button("Delete shot", role: .destructive) {
                    guard let session else { return }
                    Task {
                        guard await store.delete(session) else { return }
                        await accountStore.deleteRemoteLibraryItem(id: session.id)
                        dismiss()
                        onDeleted()
                    }
                }
            }
        }
    }
}

struct RondeLibraryMetrics {
    struct WeeklyPoint: Identifiable {
        let week: Date
        let count: Int
        var id: Date { week }
    }

    struct PlacePoint {
        let name: String
        let count: Int
        let total: Int

        var shareLabel: String {
            guard total > 0 else { return "0%" }
            return "\(Int((Double(count) / Double(total) * 100).rounded()))%"
        }
    }

    let sessions: [ReviewSession]

    var reviewCount: Int { sessions.count }
    var tracedCount: Int { sessions.filter { $0.defaultCandidate?.tracerAvailable == true }.count }
    var favouriteCount: Int { sessions.filter(\.isFavourite).count }
    var placeCount: Int {
        Set(sessions.compactMap { session in
            let place = session.placeName?.trimmingCharacters(in: .whitespacesAndNewlines)
            return place?.isEmpty == false ? place : nil
        }).count
    }
    var thisMonthCount: Int {
        guard let month = Calendar.autoupdatingCurrent.dateInterval(of: .month, for: .now) else { return 0 }
        return sessions.filter { month.contains($0.createdAt) }.count
    }
    var topPlaces: [PlacePoint] {
        let names = sessions.compactMap { session -> String? in
            let place = session.placeName?.trimmingCharacters(in: .whitespacesAndNewlines)
            return place?.isEmpty == false ? place : nil
        }
        let counts = Dictionary(grouping: names, by: { $0 }).mapValues(\.count)
        return counts
            .map { PlacePoint(name: $0.key, count: $0.value, total: max(1, names.count)) }
            .sorted { lhs, rhs in
                lhs.count == rhs.count ? lhs.name < rhs.name : lhs.count > rhs.count
            }
    }
    var memberSinceLabel: String {
        guard let first = sessions.map(\.createdAt).min() else { return "Your private player profile" }
        return "Member since \(first.formatted(.dateTime.month(.wide).year()))"
    }
    var memberSinceShortLabel: String {
        guard let first = sessions.map(\.createdAt).min() else { return "Private library" }
        return "Since \(first.formatted(.dateTime.month(.abbreviated)))"
    }
    var availability: Double { reviewCount == 0 ? 0 : Double(tracedCount) / Double(reviewCount) }
    var availabilityLabel: String { "\(Int((availability * 100).rounded()))%" }
    var summaryLine: String {
        let saved = favouriteCount == 1 ? "1 favourite" : "\(favouriteCount) favourites"
        return "\(reviewCount) reviews · \(tracedCount) with trace · \(saved)"
    }

    var weeklyActivity: [WeeklyPoint] {
        let calendar = Calendar.autoupdatingCurrent
        let currentWeek = calendar.dateInterval(of: .weekOfYear, for: .now)?.start ?? .now
        return (0..<8).reversed().compactMap { offset in
            guard let week = calendar.date(byAdding: .weekOfYear, value: -offset, to: currentWeek),
                  let next = calendar.date(byAdding: .weekOfYear, value: 1, to: week) else { return nil }
            return WeeklyPoint(week: week, count: sessions.filter { $0.createdAt >= week && $0.createdAt < next }.count)
        }
    }
}

extension View {
    @ViewBuilder
    func rondeGlassSurface(cornerRadius: CGFloat) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            self.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).stroke(.white.opacity(0.42), lineWidth: 0.8) }
        }
    }
}
