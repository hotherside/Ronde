import SwiftUI
import CoreLocation

/// Detects the user's location, searches the bundled Sydney course catalog
/// for nearby clubs, and lets them pick one or fall through to manual entry
/// (which presents the full alphabetical course list).
struct CourseDetectView: View {
    let onCourseSelected: (CourseData) -> Void
    let onManual: () -> Void

    @StateObject private var locationService = LocationService()
    @State private var detectState: DetectState = .detecting

    private enum DetectState {
        case detecting
        case results([CourseData])
        case denied
        case noResults
    }

    var body: some View {
        VStack(spacing: 0) {
            NavHeader(title: "New Round", leading: .close)

            Group {
                switch detectState {
                case .detecting:
                    loadingView
                case .results(let courses):
                    resultsList(courses: courses)
                case .denied:
                    noLocationView(
                        icon: "location.slash.fill",
                        title: "Location off",
                        message: "Browse all courses or set up a custom round."
                    )
                case .noResults:
                    noLocationView(
                        icon: "map",
                        title: "Off the fairway",
                        message: "We didn't spot a course nearby. Browse all or tee it up your own way."
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .fairwayBackground()
        .fairwayContainerBackground()
        .toolbar(.hidden, for: .navigationBar)
        .task { await startDetection() }
        .onChange(of: locationService.authorizationStatus) { _, status in
            if status == .denied || status == .restricted {
                detectState = .denied
            }
        }
        .onChange(of: locationService.currentLocation) { _, location in
            guard let location, isDetecting else { return }
            handleLocation(location)
        }
    }

    // MARK: - Detection

    private var isDetecting: Bool {
        if case .detecting = detectState { return true }
        return false
    }

    private func startDetection() async {
        switch locationService.authorizationStatus {
        case .denied, .restricted:
            detectState = .denied
            return
        default:
            break
        }

        locationService.requestPermissionAndLocation()

        // 10s timeout — fall back to "noResults" so the user still sees the
        // browse-all path.
        try? await Task.sleep(for: .seconds(10))
        if case .detecting = detectState {
            detectState = .noResults
        }
    }

    private func handleLocation(_ location: CLLocation) {
        locationService.stopUpdates()
        let nearby = CourseLibrary.shared.nearby(location, maxKilometers: 30, limit: 5)
        if nearby.isEmpty {
            detectState = .noResults
        } else {
            detectState = .results(nearby)
        }
    }

    // MARK: - Sub-views

    private var loadingView: some View {
        VStack(spacing: 14) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Theme.fairway.opacity(0.18))
                    .frame(width: 60, height: 60)
                Image(systemName: Theme.Symbol.location)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Theme.fairwayBright)
            }

            VStack(spacing: 6) {
                ProgressView()
                Text("Finding nearby courses…")
                    .font(.caption)
                    .foregroundStyle(Theme.dimText)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            PrimaryButton(title: "Browse Courses", icon: Theme.Symbol.course) {
                let all = CourseLibrary.shared.alphabetical()
                detectState = all.isEmpty ? .noResults : .results(all)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func resultsList(courses: [CourseData]) -> some View {
        List {
            Section {
                ForEach(courses) { course in
                    Button {
                        onCourseSelected(course)
                    } label: {
                        CourseRow(course: course)
                    }
                    .buttonStyle(CardRowButtonStyle())
                    .listRowBackground(Theme.cardSurfaceShape)
                }
            } header: {
                Label {
                    Text("Nearby").sectionHeaderStyle()
                } icon: {
                    Image(systemName: Theme.Symbol.location)
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            Section {
                PrimaryButton(title: "Browse All", icon: Theme.Symbol.course) {
                    let all = CourseLibrary.shared.alphabetical()
                    detectState = all.isEmpty ? .noResults : .results(all)
                }
                .listRowBackground(Color.clear)

                OutlineButton(title: "Custom Round", action: onManual)
                    .listRowBackground(Color.clear)
            }
        }
        .scrollContentBackground(.hidden)
    }

    private func noLocationView(icon: String, title: String, message: String) -> some View {
        VStack(spacing: 12) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Theme.bunker.opacity(0.15))
                    .frame(width: 60, height: 60)
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Theme.bunker)
            }
            .padding(.bottom, 2)

            VStack(spacing: 4) {
                Text(title)
                    .font(.titleSmall)
                    .foregroundStyle(Theme.textPrimary)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(Theme.dimText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 6)
            }

            Spacer()

            VStack(spacing: 8) {
                PrimaryButton(title: "Browse Courses", icon: Theme.Symbol.course) {
                    let all = CourseLibrary.shared.alphabetical()
                    detectState = all.isEmpty ? .noResults : .results(all)
                }
                OutlineButton(title: "Custom Round", action: onManual)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
