import SwiftUI
import CoreLocation

/// Fast, non-blocking round setup. Course detection happens in the background
/// while Quick 9 and Quick 18 remain immediately available.
struct CourseDetectView: View {
    let onCourseSelected: (CourseData) -> Void
    let onQuickStart: (Int) -> Void

    @StateObject private var locationService = LocationService()
    @State private var courses: [CourseData] = []
    @State private var isDetecting = true
    @State private var isShowingAll = false
    @State private var locationDenied = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Start in seconds")
                        .font(.titleSmall)
                        .foregroundStyle(Theme.textPrimary)
                    Text("Quick rounds use par 4 by default. Adjust any hole while you play.")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }

                HStack(spacing: 8) {
                    quickStartButton(holes: 9)
                    quickStartButton(holes: 18)
                }

                courseSection
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 14)
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .fairwayBackground()
        .fairwayContainerBackground()
        .navigationTitle("New Round")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }
        }
        .task { await detectNearbyCourses() }
        .onChange(of: locationService.authorizationStatus) { _, status in
            if status == .denied || status == .restricted {
                locationDenied = true
                isDetecting = false
            }
        }
        .onChange(of: locationService.currentLocation) { _, location in
            guard let location, !isShowingAll else { return }
            courses = CourseLibrary.shared.nearby(location, maxKilometers: 30, limit: 4)
            isDetecting = false
            locationService.stopUpdates()
        }
    }

    private func quickStartButton(holes: Int) -> some View {
        Button {
            onQuickStart(holes)
        } label: {
            VStack(spacing: 3) {
                Text("\(holes)")
                    .font(.scoreNumeral(size: 28))
                    .foregroundStyle(Theme.textPrimary)
                Text("HOLES")
                    .font(.micro)
                    .tracking(1)
                    .foregroundStyle(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 66)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Theme.cardSurface)
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Theme.fairway.opacity(0.35), lineWidth: 1)
                    }
            )
        }
        .buttonStyle(RondePressStyle())
        .accessibilityLabel("Quick start \(holes) hole round")
    }

    @ViewBuilder
    private var courseSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(isShowingAll ? "Sydney courses" : "Nearby courses")
                    .sectionHeaderStyle()
                Spacer()
                if isDetecting {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(Theme.fairway)
                }
            }

            if courses.isEmpty {
                HStack(spacing: 9) {
                    Image(systemName: locationDenied ? "location.slash.fill" : Theme.Symbol.location)
                        .foregroundStyle(locationDenied ? Theme.bunker : Theme.fairway)
                    Text(emptyCourseMessage)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                .padding(11)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.cardSurfaceShape)
            } else {
                ForEach(courses) { course in
                    Button { onCourseSelected(course) } label: {
                        CourseRow(course: course)
                            .padding(10)
                            .background(Theme.cardSurfaceShape)
                    }
                    .buttonStyle(RondePressStyle())
                }
            }

            if !isShowingAll {
                OutlineButton(title: "Browse All Courses", icon: Theme.Symbol.course) {
                    courses = CourseLibrary.shared.alphabetical()
                    isShowingAll = true
                    isDetecting = false
                }
            }
        }
    }

    private var emptyCourseMessage: String {
        if locationDenied { return "Location is off. Quick start still works anywhere." }
        if isDetecting { return "Finding courses without holding up your round…" }
        return "No nearby course found. Quick start still works anywhere."
    }

    private func detectNearbyCourses() async {
        switch locationService.authorizationStatus {
        case .denied, .restricted:
            locationDenied = true
            isDetecting = false
            return
        default:
            locationService.requestPermissionAndLocation()
        }

        try? await Task.sleep(for: .seconds(6))
        if locationService.currentLocation == nil, !Task.isCancelled {
            isDetecting = false
        }
    }
}
