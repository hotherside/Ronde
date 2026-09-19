import SwiftUI

struct RondeSessionsCollection: View {
    @ObservedObject var store: ReviewerStore
    let search: String
    let onImport: () -> Void

    private var groups: [ReviewSessionGroup] {
        store.sessionGroups.filter { group in
            search.isEmpty || ([group.title] + group.recordings.compactMap(\.placeName))
                .joined(separator: " ").localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            VStack(alignment: .leading, spacing: 8) {
                Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .font(.caption.weight(.semibold)).textCase(.uppercase).tracking(1.1)
                    .foregroundStyle(RondeReviewDesign.graphiteMuted)
                Text("Out there.\nKept here.")
                    .font(.largeTitle.weight(.semibold)).tracking(-1.2)
                    .fixedSize(horizontal: false, vertical: true)
                Text("The sessions, the swings, the ones worth sharing.")
                    .font(.subheadline).foregroundStyle(RondeReviewDesign.graphiteMuted)
            }
            if let latest = groups.first {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Your latest session").font(.title3.weight(.semibold))
                    NavigationLink(value: RondeNavigationRoute.session(latest.id)) {
                        RondeSessionCover(group: latest)
                    }
                    .buttonStyle(.plain).accessibilityIdentifier("session-card-\(latest.id)")
                }
                let keepers = store.sessions.filter { !$0.isRecording && $0.isFavourite }
                if search.isEmpty, !keepers.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("The good ones.").font(.title3.weight(.semibold))
                        ScrollView(.horizontal) {
                            LazyHStack(alignment: .top, spacing: 16) {
                                ForEach(keepers.prefix(8)) { shot in
                                    NavigationLink(value: RondeNavigationRoute.shot(shot.id)) {
                                        ShotLibraryCard(session: shot).frame(width: 230)
                                    }.buttonStyle(.plain)
                                }
                            }
                        }
                        .scrollIndicators(.hidden)
                    }
                }
                if groups.count > 1 {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("More time out there").font(.title3.weight(.semibold))
                        ForEach(Array(groups.dropFirst())) { group in
                            NavigationLink(value: RondeNavigationRoute.session(group.id)) {
                                RondeSessionRow(group: group)
                            }.buttonStyle(.plain)
                        }
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 20) {
                    Image(systemName: search.isEmpty ? "figure.golf" : "magnifyingglass")
                        .font(.system(size: 60, weight: .light))
                        .foregroundStyle(RondeReviewDesign.fairway).padding(.vertical, 16)
                        .accessibilityHidden(true)
                    Text(search.isEmpty ? "A whole session.\nA few worth keeping." : "No sessions found.")
                        .font(.title2.weight(.semibold))
                    Text(search.isEmpty ? "Bring in your recordings. Bookmark a swing, make a shot and give it a place to live." : "Try another session name or place.")
                        .font(.body).foregroundStyle(RondeReviewDesign.graphiteMuted)
                    if search.isEmpty {
                        Button(action: onImport) {
                            Label("Add your first recording", systemImage: "plus").frame(minHeight: 44)
                        }.rondePrimaryAction().disabled(!store.canModifyLibrary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading).reviewCard(cardPadding: 24)
            }
        }
        .foregroundStyle(RondeReviewDesign.graphite)
    }
}

private struct RondeSessionCover: View {
    let group: ReviewSessionGroup
    @Environment(\.dynamicTypeSize) private var typeSize
    private var source: ReviewSession? { group.recordings.first ?? group.shots.first }
    private var date: Date { source?.createdAt ?? .now }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            if !typeSize.isAccessibilitySize {
                HStack(spacing: 0) {
                    photograph.frame(width: 440, height: 300)
                    coverDetails.frame(minWidth: 250, maxWidth: .infinity, alignment: .leading)
                }
            }
            VStack(spacing: 0) {
                photograph.aspectRatio(1.5, contentMode: .fit)
                coverDetails
            }
        }
        .background(RondeReviewDesign.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(RondeReviewDesign.border, lineWidth: 1) }
        .accessibilityElement(children: .combine)
    }

    private var photograph: some View {
        ShotPoster(sourceURL: source?.sourceURL, time: source?.displayRange.start ?? 0)
            .overlay(alignment: .topLeading) {
                Label("\(group.recordings.count) \(group.recordings.count == 1 ? "recording" : "recordings")", systemImage: "video")
                    .font(.caption.weight(.semibold)).padding(10)
                    .background(RondeReviewDesign.canvas.opacity(0.95), in: RoundedRectangle(cornerRadius: 8))
                    .padding(14)
            }
    }

    private var coverDetails: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(date.formatted(.dateTime.day())).font(.largeTitle.weight(.medium)).tracking(-1)
                Text(date.formatted(.dateTime.month(.abbreviated).year())).font(.caption.weight(.semibold)).textCase(.uppercase)
                    .foregroundStyle(RondeReviewDesign.graphiteMuted)
            }
            Text(group.title).font(.title2.weight(.semibold)).tracking(-0.5).fixedSize(horizontal: false, vertical: true)
            if let place = source?.placeName { Text(place).font(.subheadline).foregroundStyle(RondeReviewDesign.graphiteMuted) }
            let keeperCount = group.shots.filter(\.isFavourite).count
            Text("\(group.shots.count) \(group.shots.count == 1 ? "shot" : "shots") · \(keeperCount) \(keeperCount == 1 ? "keeper" : "keepers")")
                .font(.subheadline).foregroundStyle(RondeReviewDesign.graphiteMuted)
            HStack {
                Text("Find the good ones").fontWeight(.semibold)
                Spacer()
                Image(systemName: "arrow.right")
            }
            .font(.subheadline).padding(.top, 3).frame(minHeight: 44)
        }
        .padding(22).frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct RondeSessionRow: View {
    let group: ReviewSessionGroup
    private var source: ReviewSession? { group.recordings.first ?? group.shots.first }
    var body: some View {
        HStack(spacing: 14) {
            ShotPoster(sourceURL: source?.sourceURL, time: source?.displayRange.start ?? 0)
                .frame(width: 90, height: 72).clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 5) {
                Text(group.title).font(.headline).lineLimit(2)
                Text("\(group.recordings.count) \(group.recordings.count == 1 ? "recording" : "recordings") · \(group.shots.count) \(group.shots.count == 1 ? "shot" : "shots")")
                    .font(.caption).foregroundStyle(RondeReviewDesign.graphiteMuted)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).accessibilityHidden(true)
        }
        .padding(.vertical, 8).contentShape(Rectangle()).accessibilityElement(children: .combine)
    }
}

struct RondeSessionDetailView: View {
    @ObservedObject var store: ReviewerStore
    let groupID: UUID
    let onImport: (ReviewSessionGroup) -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    private var group: ReviewSessionGroup? { store.sessionGroups.first { $0.id == groupID } }

    var body: some View {
        Group {
            if let group {
                ScrollView {
                    VStack(alignment: .leading, spacing: 26) {
                        if let error = store.libraryError { LibrarySaveNotice(store: store, message: error) }
                        VStack(alignment: .leading, spacing: 8) {
                            Text(group.title).font(.largeTitle.weight(.semibold)).tracking(-1)
                            Text("Start with the recording. Keep what feels good.")
                                .font(.subheadline).foregroundStyle(RondeReviewDesign.graphiteMuted)
                        }
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Recordings").font(.title3.weight(.semibold))
                            LazyVGrid(columns: typeSize.isAccessibilitySize ? [GridItem(.flexible())] : [GridItem(.adaptive(minimum: 270), spacing: 18)], spacing: 20) {
                                ForEach(group.recordings) { recording in
                                    NavigationLink(value: recording.isRecording ? RondeNavigationRoute.recording(recording.id) : .shot(recording.id)) {
                                        VStack(alignment: .leading, spacing: 10) {
                                            ShotPoster(sourceURL: recording.sourceURL, time: 0)
                                                .aspectRatio(1.5, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 12))
                                            Text(recording.sourceName ?? recording.title).font(.headline).lineLimit(2)
                                            HStack {
                                                Text(rondeMediaTime(recording.duration)).monospacedDigit()
                                                Text("· \(recording.bookmarks.count) bookmarks")
                                                Spacer(minLength: 0)
                                                Image(systemName: "arrow.up.right")
                                            }.font(.caption).foregroundStyle(RondeReviewDesign.graphiteMuted)
                                        }
                                    }
                                    .buttonStyle(.plain).accessibilityIdentifier("recording-card-\(recording.id)")
                                }
                            }
                        }
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Shots from this session").font(.title3.weight(.semibold))
                            if group.shots.isEmpty {
                                Label("Bookmark a few moments in a recording to create your first shots.", systemImage: "bookmark")
                                    .font(.body).foregroundStyle(RondeReviewDesign.graphiteMuted).reviewCard()
                            } else {
                                LazyVGrid(columns: typeSize.isAccessibilitySize ? [GridItem(.flexible())] : [GridItem(.adaptive(minimum: 240), spacing: 18)], spacing: 24) {
                                    ForEach(group.shots) { shot in
                                        NavigationLink(value: RondeNavigationRoute.shot(shot.id)) { ShotLibraryCard(session: shot) }
                                            .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }
                    .padding(20).frame(maxWidth: 1200, alignment: .leading).frame(maxWidth: .infinity)
                }
                .reviewCanvasBackground()
                .navigationTitle("Session").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button { onImport(group) } label: { Label("Add recording", systemImage: "plus") }
                            .disabled(!store.canModifyLibrary).accessibilityIdentifier("session-add-recording")
                    }
                }
            } else {
                ContentUnavailableView("Session unavailable", systemImage: "rectangle.stack")
            }
        }
        .foregroundStyle(RondeReviewDesign.graphite)
    }
}

func rondeMediaTime(_ seconds: TimeInterval) -> String {
    let value = Int(max(0, seconds.isFinite ? seconds : 0))
    return String(format: "%d:%02d", value / 60, value % 60)
}
