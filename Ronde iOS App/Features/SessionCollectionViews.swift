import SwiftUI

struct RondeSessionsCollection: View {
    @ObservedObject var store: ReviewerStore
    let search: String
    let onImport: () -> Void
    let onShowKeepers: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    private var groups: [ReviewSessionGroup] {
        store.sessionGroups.filter { group in
            search.isEmpty || ([group.title] + group.recordings.compactMap(\.placeName))
                .joined(separator: " ").localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            RondeCollectionHeading(title: "Sessions", count: groups.count)
            if let latest = groups.first {
                NavigationLink(value: RondeNavigationRoute.session(latest.id)) {
                    RondeSessionCover(group: latest)
                }
                .buttonStyle(.plain).accessibilityIdentifier("session-card-\(latest.id)")

                let keepers = store.sessions.filter { !$0.isRecording && $0.isFavourite }
                    .sorted { $0.createdAt > $1.createdAt }
                if search.isEmpty, !keepers.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("Keepers").font(.rondeSectionTitle)
                            Spacer()
                            Button("View all", action: onShowKeepers)
                                .font(.rondeLabel).frame(minHeight: 44)
                                .accessibilityLabel("View all keepers")
                        }
                        LazyVGrid(columns: RondeShotGrid.columns(accessibility: typeSize.isAccessibilitySize), spacing: 16) {
                            ForEach(keepers.prefix(2)) { shot in
                                NavigationLink(value: RondeNavigationRoute.shot(shot.id)) {
                                    ShotLibraryCard(session: shot)
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                }
                if groups.count > 1 {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Earlier sessions").font(.rondeSectionTitle)
                        ForEach(Array(groups.dropFirst())) { group in
                            NavigationLink(value: RondeNavigationRoute.session(group.id)) {
                                RondeSessionRow(group: group)
                            }.buttonStyle(.plain)
                            if group.id != groups.last?.id { Divider().overlay(RondeReviewDesign.border) }
                        }
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    Image(systemName: search.isEmpty ? "video.badge.plus" : "magnifyingglass")
                        .font(.system(size: 34, weight: .medium))
                        .foregroundStyle(RondeReviewDesign.fairway).padding(.top, 28)
                        .accessibilityHidden(true)
                    Text(search.isEmpty ? "Your first session starts here." : "No sessions found.")
                        .font(.rondeCardTitle)
                    Text(search.isEmpty ? "Add a recording, bookmark your best swings and turn them into shots." : "Try another session name or place.")
                        .font(.rondeBody).foregroundStyle(RondeReviewDesign.graphiteMuted)
                    if search.isEmpty {
                        Button(action: onImport) {
                            Label("Add recording", systemImage: "plus").font(.rondeLabel)
                        }.rondePrimaryAction().disabled(!store.canModifyLibrary)
                    }
                }
                .frame(maxWidth: 440, alignment: .leading)
            }
        }
        .foregroundStyle(RondeReviewDesign.graphite)
    }
}

struct RondeCollectionHeading: View {
    let title: String
    let count: Int

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title).font(.rondePageTitle).tracking(-0.7)
            Text(count.formatted()).font(.rondeLabel).foregroundStyle(RondeReviewDesign.graphiteMuted)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine).accessibilityAddTraits(.isHeader)
    }
}

enum RondeShotGrid {
    static func columns(accessibility: Bool, regular: Bool = false) -> [GridItem] {
        if accessibility { return [GridItem(.flexible())] }
        if regular { return [GridItem(.adaptive(minimum: 200), spacing: 12)] }
        return [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
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
                    photograph.frame(width: 440, height: 280)
                    coverDetails.frame(minWidth: 260, maxWidth: .infinity, alignment: .leading)
                }
            }
            VStack(spacing: 0) {
                photograph.aspectRatio(1.55, contentMode: .fit)
                coverDetails
            }
        }
        .background(RondeReviewDesign.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(RondeReviewDesign.border, lineWidth: 1) }
        .accessibilityElement(children: .combine)
    }

    private var photograph: some View {
        ShotPoster(sourceURL: source?.sourceURL, time: source?.displayRange.start ?? 0)
            .overlay(alignment: .topLeading) {
                Text("LATEST SESSION")
                    .font(.rondeMicro).tracking(1)
                    .padding(.horizontal, 9).padding(.vertical, 6)
                    .background(RondeReviewDesign.canvas, in: RoundedRectangle(cornerRadius: 5))
                    .padding(12)
            }
    }

    private var coverDetails: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(group.title).font(.rondeCardTitle).tracking(-0.5)
                        .fixedSize(horizontal: false, vertical: true)
                    if let place = source?.placeName, !place.isEmpty {
                        Text(place).font(.rondeCaption).foregroundStyle(RondeReviewDesign.graphiteMuted)
                    }
                }
                Spacer(minLength: 0)
                if !typeSize.isAccessibilitySize {
                    VStack(spacing: 0) {
                        Text(date.formatted(.dateTime.day())).font(.rondePageTitle)
                        Text(date.formatted(.dateTime.month(.abbreviated))).font(.rondeMicro).textCase(.uppercase)
                    }
                    .foregroundStyle(RondeReviewDesign.graphiteMuted).accessibilityHidden(true)
                }
            }
            Divider().overlay(RondeReviewDesign.border)
            HStack(spacing: 8) {
                Text(rondeSessionCount(group))
                    .font(.rondeCaption).foregroundStyle(RondeReviewDesign.graphiteMuted)
                Spacer(minLength: 0)
                Image(systemName: "arrow.right").font(.body.weight(.semibold))
                    .foregroundStyle(RondeReviewDesign.fairway).accessibilityHidden(true)
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct RondeSessionRow: View {
    let group: ReviewSessionGroup
    private var source: ReviewSession? { group.recordings.first ?? group.shots.first }
    var body: some View {
        HStack(spacing: 12) {
            ShotPoster(sourceURL: source?.sourceURL, time: source?.displayRange.start ?? 0)
                .frame(width: 76, height: 66).clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 4) {
                Text(group.title).font(.rondeLabel).lineLimit(2)
                Text(rondeSessionCount(group))
                    .font(.rondeCaption).foregroundStyle(RondeReviewDesign.graphiteMuted)
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
    @Environment(\.horizontalSizeClass) private var sizeClass
    private var group: ReviewSessionGroup? { store.sessionGroups.first { $0.id == groupID } }

    var body: some View {
        Group {
            if let group {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        if let error = store.libraryError { LibrarySaveNotice(store: store, message: error) }
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Recordings").font(.rondeSectionTitle)
                                Spacer()
                                Text("\(group.recordings.count)").font(.rondeLabel).foregroundStyle(RondeReviewDesign.graphiteMuted)
                            }
                            LazyVGrid(columns: typeSize.isAccessibilitySize ? [GridItem(.flexible())] : [GridItem(.adaptive(minimum: 300), spacing: 12)], spacing: 8) {
                                ForEach(group.recordings) { recording in
                                    NavigationLink(value: recording.isRecording ? RondeNavigationRoute.recording(recording.id) : .shot(recording.id)) {
                                        HStack(spacing: 12) {
                                            ShotPoster(sourceURL: recording.sourceURL, time: 0)
                                                .frame(width: 84, height: 64).clipShape(RoundedRectangle(cornerRadius: 8))
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(recording.sourceName ?? recording.title).font(.rondeLabel).lineLimit(2)
                                                Text("\(rondeMediaTime(recording.duration)) · \(recording.bookmarks.count) bookmarks")
                                                    .font(.rondeCaption).monospacedDigit().foregroundStyle(RondeReviewDesign.graphiteMuted)
                                            }
                                            Spacer(minLength: 0)
                                            Image(systemName: "arrow.up.right").font(.caption.weight(.semibold))
                                        }
                                        .padding(10).background(RondeReviewDesign.surface, in: RoundedRectangle(cornerRadius: 10))
                                        .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(RondeReviewDesign.border, lineWidth: 1) }
                                    }
                                    .buttonStyle(.plain).accessibilityIdentifier("recording-card-\(recording.id)")
                                }
                            }
                        }
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Shots").font(.rondeSectionTitle)
                                Spacer()
                                Text("\(group.shots.count)").font(.rondeLabel).foregroundStyle(RondeReviewDesign.graphiteMuted)
                            }
                            if group.shots.isEmpty {
                                Label("Bookmark a moment in a recording to create a shot.", systemImage: "bookmark")
                                    .font(.rondeBody).foregroundStyle(RondeReviewDesign.graphiteMuted).padding(.vertical, 20)
                            } else {
                                LazyVGrid(columns: RondeShotGrid.columns(accessibility: typeSize.isAccessibilitySize, regular: sizeClass == .regular), spacing: 18) {
                                    ForEach(group.shots) { shot in
                                        NavigationLink(value: RondeNavigationRoute.shot(shot.id)) { ShotLibraryCard(session: shot) }
                                            .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }
                    .padding(16).frame(maxWidth: 1100, alignment: .leading).frame(maxWidth: .infinity)
                }
                .reviewCanvasBackground()
                .navigationTitle(group.title).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        Text(group.title).font(.rondeLabel).lineLimit(1)
                    }
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

private func rondeSessionCount(_ group: ReviewSessionGroup) -> String {
    "\(group.recordings.count) \(group.recordings.count == 1 ? "video" : "videos") · \(group.shots.count) \(group.shots.count == 1 ? "shot" : "shots")"
}

func rondeMediaTime(_ seconds: TimeInterval) -> String {
    let value = Int(max(0, seconds.isFinite ? seconds : 0))
    return String(format: "%d:%02d", value / 60, value % 60)
}
