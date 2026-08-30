import AuthenticationServices
import AVFoundation
import Charts
import Combine
import SwiftUI

enum RondeAppTab: Hashable {
    case home
    case library
    case profile
}

struct RondeRootView: View {
    @ObservedObject var store: ReviewerStore
    @ObservedObject var accountStore: RondeAccountStore
    var initialTab: RondeAppTab = .home

    var body: some View {
        Group {
            if accountStore.isCheckingSession {
                RondeLaunchView()
            } else if accountStore.account != nil {
                RondeAppShell(store: store, accountStore: accountStore, initialSelection: initialTab)
            } else {
                RondeSignInView(accountStore: accountStore)
            }
        }
        .task { await accountStore.restoreSession() }
    }
}

private struct RondeLaunchView: View {
    var body: some View {
        ZStack {
            RondeReviewDesign.canvas.ignoresSafeArea()
            VStack(spacing: 14) {
                Image(systemName: "scope")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(RondeReviewDesign.fairway)
                ProgressView()
                    .tint(RondeReviewDesign.fairway)
                    .accessibilityLabel("Opening Ronde")
            }
        }
    }
}

struct RondeSignInView: View {
    @ObservedObject var accountStore: RondeAccountStore
    @State private var currentNonce: String?
    @State private var isSigningIn = false

    var body: some View {
        ZStack {
            RondeReviewDesign.canvas.ignoresSafeArea()
            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 0) {
                        ZStack(alignment: .bottomLeading) {
                            SignInBackdrop()
                                .accessibilityHidden(true)

                            VStack(alignment: .leading, spacing: 14) {
                                Text("R")
                                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.white)
                                    .frame(width: 48, height: 48)
                                    .rondeGlassSurface(cornerRadius: 16)
                                Text("RONDE")
                                    .font(.reviewerSection)
                                    .tracking(2.2)
                                    .foregroundStyle(.white.opacity(0.72))
                                Text("Keep the shots\nworth seeing again.")
                                    .font(.system(.largeTitle, design: .default).weight(.semibold))
                                    .foregroundStyle(.white)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text("Review locally. Remember the places and sessions that shape your game.")
                                    .font(.body)
                                    .foregroundStyle(.white.opacity(0.74))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.horizontal, 26)
                            .padding(.bottom, 30)
                        }
                        .frame(height: max(430, geometry.size.height * 0.63))
                        .clipped()

                        VStack(spacing: 14) {
                            SignInWithAppleButton(.continue) { request in
                                request.requestedScopes = [.fullName, .email]
                                do {
                                    let nonce = try AppleSignInNonce.make()
                                    currentNonce = nonce
                                    request.nonce = AppleSignInNonce.hashed(nonce)
                                    accountStore.authenticationError = nil
                                } catch {
                                    accountStore.authenticationError = "Ronde could not prepare secure Apple sign-in. Try again."
                                }
                            } onCompletion: { result in
                                completeAppleSignIn(result)
                            }
                            .signInWithAppleButtonStyle(.black)
                            .frame(height: 54)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .disabled(isSigningIn || !accountStore.isConfigured)
                            .accessibilityIdentifier("ronde-apple-sign-in")

                            if isSigningIn {
                                ProgressView("Signing in with Apple…")
                                    .font(.caption)
                                    .foregroundStyle(RondeReviewDesign.graphiteMuted)
                            }

                            if let error = accountStore.authenticationError {
                                Text(error)
                                    .font(.caption)
                                    .foregroundStyle(RondeReviewDesign.red)
                                    .multilineTextAlignment(.center)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            Text("Videos and analysis stay on this device. Your account syncs lightweight library details only.")
                                .font(.caption)
                                .foregroundStyle(RondeReviewDesign.graphiteMuted)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 24)
                        .padding(.bottom, 28)
                    }
                    .frame(maxWidth: 620)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: geometry.size.height)
                }
                .scrollIndicators(.hidden)
            }
            .ignoresSafeArea(edges: .top)
        }
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

private struct SignInBackdrop: View {
    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(
                Gradient(colors: [Color(red: 0.05, green: 0.12, blue: 0.10), Color(red: 0.13, green: 0.27, blue: 0.20)]),
                startPoint: CGPoint(x: size.width * 0.15, y: 0),
                endPoint: CGPoint(x: size.width, y: size.height)
            ))

            let groundRect = CGRect(x: 0, y: size.height * 0.62, width: size.width, height: size.height * 0.38)
            context.fill(Path(groundRect), with: .linearGradient(
                Gradient(colors: [Color(red: 0.20, green: 0.36, blue: 0.22), Color(red: 0.04, green: 0.12, blue: 0.08)]),
                startPoint: CGPoint(x: size.width * 0.5, y: groundRect.minY),
                endPoint: CGPoint(x: size.width * 0.5, y: groundRect.maxY)
            ))

            for index in 0..<7 {
                let x = size.width * (0.08 + (Double(index) * 0.15))
                var post = Path()
                post.move(to: CGPoint(x: x, y: size.height * 0.57))
                post.addLine(to: CGPoint(x: x, y: size.height * 0.72))
                context.stroke(post, with: .color(.white.opacity(0.07)), lineWidth: 1)
            }

            var flight = Path()
            flight.move(to: CGPoint(x: size.width * 0.13, y: size.height * 0.64))
            flight.addCurve(
                to: CGPoint(x: size.width * 0.88, y: size.height * 0.30),
                control1: CGPoint(x: size.width * 0.31, y: size.height * 0.28),
                control2: CGPoint(x: size.width * 0.66, y: size.height * 0.16)
            )
            context.drawLayer { layer in
                layer.addFilter(.shadow(color: RondeReviewDesign.tracerPurple.opacity(0.55), radius: 10))
                layer.stroke(flight, with: .color(RondeReviewDesign.tracerPurpleSoft.opacity(0.86)), style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
            }
        }
    }
}

struct RondeAppShell: View {
    @ObservedObject var store: ReviewerStore
    @ObservedObject var accountStore: RondeAccountStore
    @State private var selection: RondeAppTab

    init(store: ReviewerStore, accountStore: RondeAccountStore, initialSelection: RondeAppTab = .home) {
        self.store = store
        self.accountStore = accountStore
        _selection = State(initialValue: initialSelection)
    }

    var body: some View {
        TabView(selection: $selection) {
            RondeHomeView(store: store, accountStore: accountStore, selectedTab: $selection)
                .tabItem { Label("Home", systemImage: "house") }
                .tag(RondeAppTab.home)

            RondeMediaLibraryView(store: store, accountStore: accountStore)
                .tabItem { Label("Library", systemImage: "rectangle.stack") }
                .tag(RondeAppTab.library)

            RondeProfileView(store: store, accountStore: accountStore)
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
                .tag(RondeAppTab.profile)
        }
        .tint(RondeReviewDesign.fairway)
        .task(id: accountStore.account?.id) {
            guard let account = accountStore.account else {
                store.deactivateLibrary()
                return
            }
            store.activateLibrary(for: account.id)
            await accountStore.synchronise(store.sessions)
        }
        .onReceive(store.$sessions.dropFirst().debounce(for: .seconds(1.2), scheduler: RunLoop.main)) { sessions in
            Task { await accountStore.synchronise(sessions) }
        }
    }
}

struct RondeHomeView: View {
    @ObservedObject var store: ReviewerStore
    @ObservedObject var accountStore: RondeAccountStore
    @Binding var selectedTab: RondeAppTab
    @State private var isImportPresented = false

    private var metrics: RondeLibraryMetrics { RondeLibraryMetrics(sessions: store.sessions) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    homeHeader

                    if store.sessions.isEmpty {
                        RondeEmptyLibraryCard { isImportPresented = true }
                    } else {
                        latestCarousel
                        metricStrip
                        FlightlineEvidenceCard(metrics: metrics)
                        if store.sessions.count > 1 {
                            recentRow
                        }
                    }
                }
                .frame(maxWidth: 1080, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 30)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .background(RondeReviewDesign.canvas.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $isImportPresented) {
                RangeSessionEntryView(store: store, intent: .oneShot) { session in
                    store.select(session)
                }
            }
            .navigationDestination(for: UUID.self) { sessionID in
                RondeMediaDetailRoute(store: store, accountStore: accountStore, sessionID: sessionID)
            }
        }
    }

    private var homeHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(dateLine)
                        .font(.reviewerSection)
                        .tracking(1.5)
                        .foregroundStyle(RondeReviewDesign.fairway)
                    Text(greeting)
                        .font(.reviewerDisplay)
                        .foregroundStyle(RondeReviewDesign.graphite)
                }
                Spacer(minLength: 8)
                Button {
                    selectedTab = .profile
                } label: {
                    Text(accountStore.account?.initials ?? "RG")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(RondeReviewDesign.fairway, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open profile")
            }

            HStack(alignment: .center, spacing: 12) {
                Text(store.sessions.isEmpty ? "Your private golf video library starts here." : "Recent footage and honest trace evidence, kept private on this device.")
                    .font(.subheadline)
                    .foregroundStyle(RondeReviewDesign.graphiteMuted)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                RondeAddVideoButton(action: { isImportPresented = true })
            }
        }
    }

    private var dateLine: String {
        Date.now.formatted(.dateTime.weekday(.wide).day().month(.abbreviated)).uppercased()
    }

    private var greeting: String {
        let hour = Calendar.autoupdatingCurrent.component(.hour, from: .now)
        let salutation = hour < 12 ? "Good morning" : (hour < 18 ? "Good afternoon" : "Good evening")
        let firstName = accountStore.account?.displayName?
            .split(separator: " ")
            .first
            .map(String.init)
        return firstName.map { "\(salutation), \($0)." } ?? "\(salutation)."
    }

    private var latestCarousel: some View {
        VStack(alignment: .leading, spacing: 11) {
            RondeSectionHeader(title: "Latest reviews", actionTitle: "See all") { selectedTab = .library }
            ScrollView(.horizontal) {
                LazyHStack(spacing: 14) {
                    ForEach(store.sessions.prefix(5)) { session in
                        NavigationLink(value: session.id) {
                            RondeHeroMediaCard(session: session)
                                .containerRelativeFrame(.horizontal, count: 1, spacing: 14)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .contentMargins(.horizontal, 0, for: .scrollContent)
            .scrollIndicators(.hidden)
        }
    }

    private var metricStrip: some View {
        HStack(spacing: 0) {
            RondeMetricCell(value: "\(metrics.reviewCount)", label: "Reviews")
            Divider().frame(height: 44)
            RondeMetricCell(value: "\(metrics.tracedCount)", label: "Traced")
            Divider().frame(height: 44)
            RondeMetricCell(value: "\(metrics.placeCount)", label: "Places")
        }
        .padding(.vertical, 12)
        .background(RondeReviewDesign.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(RondeReviewDesign.border, lineWidth: 0.8) }
    }

    private var recentRow: some View {
        VStack(alignment: .leading, spacing: 11) {
            RondeSectionHeader(title: "Recent", actionTitle: "Library") { selectedTab = .library }
            ScrollView(.horizontal) {
                LazyHStack(spacing: 12) {
                    ForEach(store.sessions.dropFirst().prefix(6)) { session in
                        NavigationLink(value: session.id) {
                            RondeCompactMediaCard(session: session)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }
}

private struct RondeAddVideoButton: View {
    let action: () -> Void

    @ViewBuilder
    var body: some View {
        if #available(iOS 26.0, *) {
            Button(action: action) {
                Label("Add video", systemImage: "photo.on.rectangle.angled")
            }
            .font(.subheadline.weight(.semibold))
            .buttonStyle(.glassProminent)
            .tint(RondeReviewDesign.fairway)
            .accessibilityIdentifier("ronde-import-action")
        } else {
            Button(action: action) {
                Label("Add video", systemImage: "photo.on.rectangle.angled")
            }
            .buttonStyle(ReviewPrimaryButtonStyle())
            .accessibilityIdentifier("ronde-import-action")
        }
    }
}

private struct RondeSectionHeader: View {
    let title: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        HStack {
            Text(title)
                .font(.headline)
                .foregroundStyle(RondeReviewDesign.graphite)
            Spacer()
            Button(actionTitle, action: action)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(RondeReviewDesign.fairway)
        }
    }
}

private struct RondeMetricCell: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.title3.weight(.semibold))
                .foregroundStyle(RondeReviewDesign.graphite)
                .monospacedDigit()
                .minimumScaleFactor(0.72)
                .lineLimit(1)
            Text(label)
                .font(.caption2)
                .foregroundStyle(RondeReviewDesign.graphiteMuted)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

private struct FlightlineEvidenceCard: View {
    let metrics: RondeLibraryMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("TRACE RATE")
                        .font(.reviewerSection)
                        .tracking(1.3)
                        .foregroundStyle(RondeReviewDesign.fairway)
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text("\(metrics.tracedCount)")
                            .font(.system(.title, design: .rounded).weight(.semibold))
                        Text("/ \(metrics.reviewCount)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(RondeReviewDesign.graphiteMuted)
                    }
                    .foregroundStyle(RondeReviewDesign.graphite)
                    .monospacedDigit()
                    ProgressView(value: metrics.availability)
                        .tint(RondeReviewDesign.tracerPurple)
                        .frame(maxWidth: 145)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Divider()
                    .frame(height: 66)

                VStack(alignment: .leading, spacing: 3) {
                    Text("THIS MONTH")
                        .font(.reviewerSection)
                        .tracking(1.3)
                        .foregroundStyle(RondeReviewDesign.fairway)
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text("\(metrics.thisMonthCount)")
                            .font(.system(.title, design: .rounded).weight(.semibold))
                        Text(metrics.thisMonthCount == 1 ? "review" : "reviews")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(RondeReviewDesign.graphiteMuted)
                    }
                        .foregroundStyle(RondeReviewDesign.graphite)
                        .monospacedDigit()
                    Text(metrics.favouriteCount == 1 ? "1 saved" : "\(metrics.favouriteCount) saved")
                        .font(.caption2)
                        .foregroundStyle(RondeReviewDesign.graphiteMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Chart(metrics.weeklyActivity) { point in
                AreaMark(
                    x: .value("Week", point.week, unit: .weekOfYear),
                    y: .value("Reviews", point.count)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [RondeReviewDesign.fairway.opacity(0.28), RondeReviewDesign.fairway.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                LineMark(
                    x: .value("Week", point.week, unit: .weekOfYear),
                    y: .value("Reviews", point.count)
                )
                .foregroundStyle(RondeReviewDesign.fairway)
                .lineStyle(StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                PointMark(
                    x: .value("Week", point.week, unit: .weekOfYear),
                    y: .value("Reviews", point.count)
                )
                .foregroundStyle(RondeReviewDesign.fairway)
                .symbolSize(18)
            }
            .chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks(values: .stride(by: .weekOfYear, count: 2)) { _ in
                    AxisGridLine().foregroundStyle(RondeReviewDesign.border)
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                        .foregroundStyle(RondeReviewDesign.graphiteFaint)
                }
            }
            .frame(height: 104)

            Text("Trace rate reflects available evidence, not shot quality.")
                .font(.caption)
                .foregroundStyle(RondeReviewDesign.graphiteMuted)
        }
        .reviewCard(cardPadding: 18)
    }
}

private struct RondeHeroMediaCard: View {
    let session: ReviewSession

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RondeMediaArtwork(session: session)
            LinearGradient(colors: [.clear, .black.opacity(0.66)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Label(session.placeName ?? "Place not added", systemImage: "mappin")
                    Spacer()
                    Text(rondeFormatDuration(session.duration))
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.84))

                Text(session.clubName ?? session.title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(session.createdAt, format: .dateTime.day().month(.abbreviated).hour().minute())
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.72))
            }
            .padding(16)
        }
        .frame(height: 238)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(.white.opacity(0.18), lineWidth: 0.8) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(session.title), \(session.placeName ?? "place not added"), \(rondeFormatDuration(session.duration))")
    }
}

private struct RondeCompactMediaCard: View {
    let session: ReviewSession

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RondeMediaArtwork(session: session)
                .frame(width: 170, height: 112)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    if session.isFavourite {
                        Image(systemName: "heart.fill")
                            .font(.caption)
                            .foregroundStyle(.white)
                            .padding(8)
                    }
                }
            Text(session.clubName ?? session.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(RondeReviewDesign.graphite)
                .lineLimit(1)
            Text(session.placeName ?? "Place not added")
                .font(.caption)
                .foregroundStyle(RondeReviewDesign.graphiteMuted)
                .lineLimit(1)
        }
        .frame(width: 170, alignment: .leading)
    }
}

private struct RondeMediaArtwork: View {
    let session: ReviewSession

    var body: some View {
        ZStack {
            RondeVideoThumbnail(
                sourceURL: session.sourceURL,
                time: session.defaultCandidate?.impactTime ?? 0
            )

            LinearGradient(
                colors: [.black.opacity(0.04), .clear, .black.opacity(0.22)],
                startPoint: .top,
                endPoint: .bottom
            )

            Canvas { context, size in
                if let path = session.defaultCandidate?.evidenceAnchoredPath {
                    draw(points: path.allDisplayPoints, in: size, context: &context, dashed: false)
                } else if let manual = session.defaultCandidate?.assistedTracer {
                    draw(points: [
                        NormalizedPoint(x: manual.launch.x, y: manual.launch.y),
                        NormalizedPoint(x: manual.apex.x, y: manual.apex.y),
                        NormalizedPoint(x: manual.landing.x, y: manual.landing.y)
                    ], in: size, context: &context, dashed: true)
                }
            }
        }
        .overlay(alignment: .topLeading) {
            if session.defaultCandidate?.tracerAvailable != true {
                Text("NO VERIFIED TRACE")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1.1)
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(10)
            }
        }
        .accessibilityHidden(true)
    }

    private func draw(points: [NormalizedPoint], in size: CGSize, context: inout GraphicsContext, dashed: Bool) {
        guard points.count >= 2 else { return }
        var path = Path()
        path.move(to: CGPoint(x: points[0].x * size.width, y: points[0].y * size.height))
        for point in points.dropFirst() {
            path.addLine(to: CGPoint(x: point.x * size.width, y: point.y * size.height))
        }
        context.stroke(
            path,
            with: .color(RondeReviewDesign.tracerPurpleSoft),
            style: StrokeStyle(lineWidth: dashed ? 2.2 : 3.1, lineCap: .round, lineJoin: .round, dash: dashed ? [5, 5] : [])
        )
    }
}

private struct RondeVideoThumbnail: View {
    let sourceURL: URL?
    let time: TimeInterval
    @State private var image: CGImage?

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 1, orientation: .up)
                    .resizable()
                    .scaledToFill()
            } else {
                RondeMediaFallbackArtwork()
            }
        }
        .clipped()
        .task(id: sourceURL) {
            image = await makeImage()
        }
    }

    private func makeImage() async -> CGImage? {
        guard let sourceURL else { return nil }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: sourceURL))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1200, height: 1200)
        let requestedTime = CMTime(seconds: max(0, time), preferredTimescale: 600)
        return try? await generator.image(at: requestedTime).image
    }
}

private struct RondeMediaFallbackArtwork: View {
    var body: some View {
        Canvas { context, size in
            context.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .linearGradient(
                    Gradient(colors: [Color(red: 0.44, green: 0.58, blue: 0.58), Color(red: 0.12, green: 0.28, blue: 0.20)]),
                    startPoint: .zero,
                    endPoint: CGPoint(x: size.width, y: size.height)
                )
            )
            let ground = CGRect(x: 0, y: size.height * 0.57, width: size.width, height: size.height * 0.43)
            context.fill(
                Path(ground),
                with: .linearGradient(
                    Gradient(colors: [Color(red: 0.31, green: 0.48, blue: 0.29), Color(red: 0.07, green: 0.18, blue: 0.11)]),
                    startPoint: CGPoint(x: 0, y: ground.minY),
                    endPoint: CGPoint(x: size.width, y: ground.maxY)
                )
            )

            let personX = size.width * 0.28
            let personY = size.height * 0.72
            context.fill(
                Circle().path(in: CGRect(x: personX - 5, y: personY - 43, width: 10, height: 10)),
                with: .color(.black.opacity(0.58))
            )
            var body = Path()
            body.move(to: CGPoint(x: personX, y: personY - 33))
            body.addLine(to: CGPoint(x: personX - 5, y: personY - 4))
            body.move(to: CGPoint(x: personX - 1, y: personY - 25))
            body.addLine(to: CGPoint(x: personX + 24, y: personY - 10))
            body.move(to: CGPoint(x: personX - 5, y: personY - 4))
            body.addLine(to: CGPoint(x: personX - 17, y: personY + 22))
            body.move(to: CGPoint(x: personX - 5, y: personY - 4))
            body.addLine(to: CGPoint(x: personX + 8, y: personY + 22))
            context.stroke(body, with: .color(.black.opacity(0.58)), style: StrokeStyle(lineWidth: 5, lineCap: .round))
        }
        .accessibilityHidden(true)
    }
}

private struct RondeEmptyLibraryCard: View {
    let importAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            RondeEmptyArtwork()
                .frame(height: 180)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay {
                    Image(systemName: "play.rectangle.on.rectangle")
                        .font(.system(size: 34, weight: .medium))
                        .foregroundStyle(.white)
                }
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text("Your first review starts with one video.")
                    .font(.headline)
                    .foregroundStyle(RondeReviewDesign.graphite)
                Text("Choose a shot video up to one minute. Analysis and raw media stay on this device.")
                    .font(.subheadline)
                    .foregroundStyle(RondeReviewDesign.graphiteMuted)
            }
            Button(action: importAction) {
                Label("Choose a shot video", systemImage: "photo.on.rectangle.angled")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(ReviewPrimaryButtonStyle())
        }
        .reviewCard(cardPadding: 18)
    }
}

private struct RondeEmptyArtwork: View {
    var body: some View {
        Canvas { context, size in
            let bounds = CGRect(origin: .zero, size: size)
            context.fill(
                Path(bounds),
                with: .linearGradient(
                    Gradient(colors: [Color.white, RondeReviewDesign.fairwayWash.opacity(0.64)]),
                    startPoint: .zero,
                    endPoint: CGPoint(x: size.width, y: size.height)
                )
            )

            let ground = CGRect(x: 0, y: size.height * 0.62, width: size.width, height: size.height * 0.38)
            context.fill(Path(ground), with: .color(RondeReviewDesign.fairway.opacity(0.18)))

            var flag = Path()
            flag.move(to: CGPoint(x: size.width * 0.70, y: size.height * 0.30))
            flag.addLine(to: CGPoint(x: size.width * 0.70, y: size.height * 0.74))
            context.stroke(flag, with: .color(RondeReviewDesign.graphiteMuted.opacity(0.42)), lineWidth: 2)

            let flagShape = Path { path in
                path.move(to: CGPoint(x: size.width * 0.70, y: size.height * 0.31))
                path.addLine(to: CGPoint(x: size.width * 0.82, y: size.height * 0.36))
                path.addLine(to: CGPoint(x: size.width * 0.70, y: size.height * 0.41))
                path.closeSubpath()
            }
            context.fill(flagShape, with: .color(RondeReviewDesign.fairway.opacity(0.46)))
        }
    }
}

enum RondeLibraryFilter: String, CaseIterable, Identifiable {
    case recent = "Recent"
    case traced = "With trace"
    case saved = "Saved"
    var id: String { rawValue }
}

private struct RondeLibraryFilterButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    @ViewBuilder
    var body: some View {
        if #available(iOS 26.0, *) {
            Button(title, action: action)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isSelected ? Color.white : RondeReviewDesign.graphite)
                .padding(.horizontal, 14)
                .frame(minHeight: 40)
                .glassEffect(
                    isSelected
                        ? .regular.tint(RondeReviewDesign.fairway).interactive()
                        : .regular.interactive(),
                    in: .capsule
                )
        } else {
            Button(title, action: action)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isSelected ? Color.white : RondeReviewDesign.graphite)
                .padding(.horizontal, 14)
                .frame(minHeight: 40)
                .background(isSelected ? RondeReviewDesign.fairway : RondeReviewDesign.surface, in: Capsule())
                .overlay { Capsule().stroke(RondeReviewDesign.border, lineWidth: isSelected ? 0 : 0.8) }
        }
    }
}

struct RondeMediaLibraryView: View {
    @ObservedObject var store: ReviewerStore
    @ObservedObject var accountStore: RondeAccountStore
    @State private var selectedFilter: RondeLibraryFilter = .recent
    @State private var searchText = ""
    @State private var isImportPresented = false

    private var filteredSessions: [ReviewSession] {
        store.sessions.filter { session in
            let matchesFilter: Bool
            switch selectedFilter {
            case .recent: matchesFilter = true
            case .traced: matchesFilter = session.defaultCandidate?.tracerAvailable == true
            case .saved: matchesFilter = session.isFavourite
            }
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            let matchesSearch = query.isEmpty || [session.title, session.clubName, session.placeName, session.sourceName]
                .compactMap { $0 }
                .contains { $0.localizedCaseInsensitiveContains(query) }
            return matchesFilter && matchesSearch
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    libraryHeader
                    filterRow

                    if store.sessions.isEmpty {
                        RondeEmptyLibraryCard { isImportPresented = true }
                    } else if filteredSessions.isEmpty {
                        ContentUnavailableView(
                            "No matching reviews",
                            systemImage: "line.3.horizontal.decrease.circle",
                            description: Text("Try another filter or search term.")
                        )
                        .frame(maxWidth: .infinity, minHeight: 320)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 158), spacing: 14)], spacing: 18) {
                            ForEach(filteredSessions) { session in
                                NavigationLink(value: session.id) {
                                    RondeLibraryTile(session: session) {
                                        store.toggleFavourite(session)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .frame(maxWidth: 1080, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
                .frame(maxWidth: .infinity)
            }
            .background(RondeReviewDesign.canvas.ignoresSafeArea())
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Club, place or filename")
            .sheet(isPresented: $isImportPresented) {
                RangeSessionEntryView(store: store, intent: .oneShot) { session in store.select(session) }
            }
            .navigationDestination(for: UUID.self) { sessionID in
                RondeMediaDetailRoute(store: store, accountStore: accountStore, sessionID: sessionID)
            }
        }
    }

    private var libraryHeader: some View {
        HStack(alignment: .bottom, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("YOUR FOOTAGE")
                    .font(.reviewerSection)
                    .tracking(1.5)
                    .foregroundStyle(RondeReviewDesign.fairway)
                Text("Library")
                    .font(.reviewerDisplay)
                    .foregroundStyle(RondeReviewDesign.graphite)
                Text("\(store.sessions.count) videos · private on this device")
                    .font(.caption)
                    .foregroundStyle(RondeReviewDesign.graphiteMuted)
            }
            Spacer()
            RondeAddVideoButton(action: { isImportPresented = true })
        }
    }

    private var filterRow: some View {
        ScrollView(.horizontal) {
            Group {
                if #available(iOS 26.0, *) {
                    GlassEffectContainer(spacing: 10) {
                        filterButtons
                    }
                } else {
                    filterButtons
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private var filterButtons: some View {
        HStack(spacing: 9) {
            ForEach(RondeLibraryFilter.allCases) { filter in
                RondeLibraryFilterButton(
                    title: filter.rawValue,
                    isSelected: selectedFilter == filter,
                    action: { selectedFilter = filter }
                )
            }
        }
    }
}

private struct RondeLibraryTile: View {
    let session: ReviewSession
    let favouriteAction: () -> Void

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RondeMediaArtwork(session: session)
            LinearGradient(colors: [.clear, .black.opacity(0.78)], startPoint: .center, endPoint: .bottom)

            VStack(alignment: .leading, spacing: 4) {
                Text(session.clubName ?? session.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(session.placeName ?? "Place not added")
                    Text("·")
                    Text(rondeFormatDuration(session.duration))
                }
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.76))
                .lineLimit(1)
                HStack(spacing: 5) {
                    Circle()
                        .fill(session.defaultCandidate?.tracerAvailable == true ? RondeReviewDesign.tracerPurpleSoft : Color.white.opacity(0.64))
                        .frame(width: 6, height: 6)
                    Text(session.defaultCandidate?.tracerAvailable == true ? traceLabel : "Ball flight not tracked")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.84))
                        .lineLimit(1)
                }
            }
            .padding(13)

            Button(action: favouriteAction) {
                Image(systemName: session.isFavourite ? "heart.fill" : "heart")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(.black.opacity(0.24), in: Circle())
            }
            .buttonStyle(.plain)
            .padding(9)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .accessibilityLabel(session.isFavourite ? "Remove from favourites" : "Add to favourites")
        }
        .aspectRatio(0.92, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 19, style: .continuous).stroke(.white.opacity(0.42), lineWidth: 0.8) }
        .accessibilityElement(children: .combine)
    }

    private var traceLabel: String {
        let count = session.defaultCandidate?.observedTracerPointCount ?? 0
        return count > 0 ? "\(count) observed points" : "Manual trace"
    }
}

struct RondeProfileView: View {
    @ObservedObject var store: ReviewerStore
    @ObservedObject var accountStore: RondeAccountStore
    private var metrics: RondeLibraryMetrics { RondeLibraryMetrics(sessions: store.sessions) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    profileHeader
                    profileScorecard
                    if !metrics.topPlaces.isEmpty {
                        placesCard
                    }
                    evidenceSummary
                    activityCard
                    privacyCard
                    accountActions
                }
                .frame(maxWidth: 720, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity)
            }
            .background(RondeReviewDesign.canvas.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var profileHeader: some View {
        HStack(spacing: 16) {
            Text(accountStore.account?.initials ?? "RG")
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 64, height: 64)
                .background(RondeReviewDesign.fairway, in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text("RONDE MEMBER")
                    .font(.reviewerSection)
                    .tracking(1.4)
                    .foregroundStyle(RondeReviewDesign.fairway)
                Text(accountStore.account?.displayName ?? "Ronde golfer")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(RondeReviewDesign.graphite)
                Text(metrics.memberSinceLabel)
                    .font(.caption)
                    .foregroundStyle(RondeReviewDesign.graphiteMuted)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var profileScorecard: some View {
        HStack(spacing: 0) {
            profileMetric(value: "\(metrics.reviewCount)", label: "REVIEWS", detail: metrics.memberSinceShortLabel)
            Divider().frame(height: 56)
            profileMetric(value: "\(metrics.favouriteCount)", label: "SAVED", detail: "Worth revisiting")
        }
        .padding(.vertical, 14)
        .background(RondeReviewDesign.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(RondeReviewDesign.border, lineWidth: 0.8) }
    }

    private func profileMetric(value: String, label: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.reviewerSection)
                .tracking(1.25)
                .foregroundStyle(RondeReviewDesign.fairway)
            Text(value)
                .font(.system(.title, design: .rounded).weight(.semibold))
                .foregroundStyle(RondeReviewDesign.graphite)
                .monospacedDigit()
            Text(detail)
                .font(.caption2)
                .foregroundStyle(RondeReviewDesign.graphiteMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .accessibilityElement(children: .combine)
    }

    private var placesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("YOUR PLACES")
                .font(.reviewerSection)
                .tracking(1.3)
                .foregroundStyle(RondeReviewDesign.graphiteFaint)

            ForEach(Array(metrics.topPlaces.prefix(3).enumerated()), id: \.element.name) { index, place in
                HStack(spacing: 12) {
                    Text(String(format: "%02d", index + 1))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(RondeReviewDesign.fairway)
                        .monospacedDigit()
                    VStack(alignment: .leading, spacing: 2) {
                        Text(place.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(RondeReviewDesign.graphite)
                        Text(place.count == 1 ? "1 review" : "\(place.count) reviews")
                            .font(.caption)
                            .foregroundStyle(RondeReviewDesign.graphiteMuted)
                    }
                    Spacer()
                    Text(place.shareLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(RondeReviewDesign.fairway)
                        .monospacedDigit()
                }
                if index < min(2, metrics.topPlaces.count - 1) {
                    Divider().overlay(RondeReviewDesign.border)
                }
            }
        }
        .reviewCard(cardPadding: 16)
    }

    private var evidenceSummary: some View {
        HStack(spacing: 18) {
            Gauge(value: metrics.availability) {
                Text("Trace availability")
            } currentValueLabel: {
                Text(metrics.availabilityLabel)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(RondeReviewDesign.graphite)
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .tint(RondeReviewDesign.tracerPurple)
            .frame(width: 78)

            VStack(alignment: .leading, spacing: 5) {
                Text("TRACE AVAILABILITY")
                    .font(.reviewerSection)
                    .tracking(1.3)
                    .foregroundStyle(RondeReviewDesign.graphiteFaint)
                Text("\(metrics.tracedCount) of \(metrics.reviewCount) reviews")
                    .font(.headline)
                    .foregroundStyle(RondeReviewDesign.graphite)
                Text("This measures whether enough evidence existed for a trace, not how well you hit the ball.")
                    .font(.caption)
                    .foregroundStyle(RondeReviewDesign.graphiteMuted)
            }
        }
        .reviewCard(cardPadding: 18)
    }

    private var activityCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("ACTIVITY · 8 WEEKS")
                .font(.reviewerSection)
                .tracking(1.3)
                .foregroundStyle(RondeReviewDesign.graphiteFaint)
            Chart(metrics.weeklyActivity) { point in
                BarMark(x: .value("Week", point.week, unit: .weekOfYear), y: .value("Reviews", point.count))
                    .foregroundStyle(RondeReviewDesign.fairway.gradient)
                    .cornerRadius(4)
            }
            .chartYAxis { AxisMarks(position: .leading) }
            .frame(height: 150)
            HStack {
                Label("\(metrics.reviewCount) reviews", systemImage: "rectangle.stack")
                Spacer()
                Label("\(metrics.favouriteCount) saved", systemImage: "heart")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(RondeReviewDesign.graphiteMuted)
        }
        .reviewCard(cardPadding: 18)
    }

    private var privacyCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Private by design", systemImage: "lock.shield")
                .font(.headline)
                .foregroundStyle(RondeReviewDesign.graphite)
            Text("Raw videos and tracer analysis stay on this device. Ronde syncs account identity and lightweight library labels without turning footage into cloud storage.")
                .font(.subheadline)
                .foregroundStyle(RondeReviewDesign.graphiteMuted)
            HStack {
                Label("On-device media", systemImage: "iphone")
                Spacer()
                Text("\(store.sessions.count) items")
            }
            HStack {
                Label("Metadata sync", systemImage: "icloud")
                Spacer()
                Text(accountStore.syncState.label)
            }
            .foregroundStyle(accountStore.syncState == .failed ? RondeReviewDesign.amber : RondeReviewDesign.graphite)
        }
        .font(.subheadline)
        .reviewCard(cardPadding: 18)
    }

    private var accountActions: some View {
        Button(role: .destructive) {
            Task {
                await accountStore.signOut()
                if accountStore.account == nil {
                    store.deactivateLibrary()
                }
            }
        } label: {
            Label("Sign out on this device", systemImage: "rectangle.portrait.and.arrow.right")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(ReviewSecondaryButtonStyle(tint: RondeReviewDesign.red))
    }
}

struct RondeMediaDetailRoute: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: ReviewerStore
    @ObservedObject var accountStore: RondeAccountStore
    let sessionID: UUID
    @State private var isEditingDetails = false

    private var session: ReviewSession? { store.sessions.first { $0.id == sessionID } }

    var body: some View {
        Group {
            if let session {
                ZStack(alignment: .top) {
                    SessionWorkspaceView(
                        store: store,
                        session: session,
                        onEditDetails: { isEditingDetails = true },
                        onToggleFavourite: { store.toggleFavourite(session) }
                    )

                    detailChrome
                }
            } else {
                ContentUnavailableView("Review unavailable", systemImage: "film", description: Text("This local review is no longer available."))
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .sheet(isPresented: $isEditingDetails) {
            RondeMediaDetailsEditor(
                store: store,
                accountStore: accountStore,
                sessionID: sessionID,
                onDeleted: { dismiss() }
            )
        }
    }

    @ViewBuilder
    private var detailChrome: some View {
        HStack {
            RondeDetailChromeButton(
                systemImage: "chevron.left",
                accessibilityLabel: "Back",
                action: dismiss.callAsFunction
            )

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
    }
}

private struct RondeDetailChromeButton: View {
    let systemImage: String
    let accessibilityLabel: String
    let action: () -> Void

    @ViewBuilder
    var body: some View {
        if #available(iOS 26.0, *) {
            Button(action: action) {
                Image(systemName: systemImage)
                    .font(.body.weight(.semibold))
                    .frame(width: 42, height: 42)
            }
            .buttonStyle(.glass)
            .tint(.white)
            .accessibilityLabel(accessibilityLabel)
        } else {
            Button(action: action) {
                Image(systemName: systemImage)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibilityLabel)
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
                Section("Review") {
                    TextField("Title", text: $title)
                    TextField("Place or course", text: $placeName)
                        .textContentType(.location)
                    TextField("Club", text: $clubName)
                    TextField("Note", text: $note, axis: .vertical)
                        .lineLimit(3...7)
                }

                if let session, let candidate = session.defaultCandidate {
                    Section("Impact timing") {
                        Slider(
                            value: Binding(
                                get: { candidate.impactTime },
                                set: { store.updateImpactTime($0, for: candidate, in: session) }
                            ),
                            in: 0...max(session.duration, 0.1),
                            step: 0.05
                        )
                        .tint(RondeReviewDesign.fairway)
                        HStack {
                            Text("Impact")
                            Spacer()
                            Text(rondeFormatTimestamp(candidate.impactTime)).monospacedDigit()
                        }
                        .font(.caption)
                        Text("This corrects when the trace begins. The original shot video remains intact.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Section("Trace evidence") {
                        LabeledContent("Source", value: traceSourceLabel(candidate))
                        LabeledContent("Observed points", value: "\(candidate.observedTracerPointCount)")
                        if let carry = candidate.evidenceAnchoredPath?.estimatedCarry {
                            LabeledContent("Model carry", value: carry.displayText)
                            Text("Uncalibrated estimate, not a measured distance.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    Button("Delete review", role: .destructive) { showsDeleteConfirmation = true }
                } footer: {
                    Text("Deleting removes the app-owned local video, its trace and its synced metadata. Your original Photos or Files item is untouched.")
                }
            }
            .navigationTitle("Edit review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let session else { return }
                        store.updateDetails(for: session, title: title, placeName: placeName, clubName: clubName, note: note)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .task { loadValues() }
            .confirmationDialog("Delete this review?", isPresented: $showsDeleteConfirmation, titleVisibility: .visible) {
                Button("Delete review", role: .destructive) {
                    guard let session else { return }
                    Task {
                        await accountStore.deleteRemoteLibraryItem(id: session.id)
                        await store.delete(session)
                        dismiss()
                        onDeleted()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This cannot be undone inside Ronde.")
            }
        }
    }

    private func loadValues() {
        guard let session else { return }
        title = session.title
        placeName = session.placeName ?? ""
        clubName = session.clubName ?? ""
        note = session.note
    }

    private func traceSourceLabel(_ candidate: ReviewCandidate) -> String {
        if candidate.hasManualTracer { return "Manual trace" }
        switch candidate.tracerSource {
        case .unavailable: return "Ball flight not tracked"
        case .observed: return "Observed"
        case .observedAndInferred: return "Observed + estimated"
        case .inferred: return "Estimated"
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

private func rondeFormatDuration(_ seconds: TimeInterval) -> String {
    guard seconds.isFinite, seconds > 0 else { return "0:00" }
    let total = Int(seconds.rounded())
    return String(format: "%d:%02d", total / 60, total % 60)
}

private func rondeFormatTimestamp(_ seconds: TimeInterval) -> String {
    let safe = max(0, seconds.isFinite ? seconds : 0)
    let minutes = Int(safe) / 60
    let remainder = safe - Double(minutes * 60)
    return String(format: "%d:%04.1f", minutes, remainder)
}
