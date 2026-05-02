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
                    message: "Browse all courses or enter your own."
                )
            case .noResults:
                noLocationView(
                    icon: "map",
                    title: "Off the fairway",
                    message: "No nearby Sydney clubs found."
                )
            }
        }
        .navigationTitle("New Round")
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
        VStack(spacing: 16) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Theme.fairway.opacity(0.18))
                    .frame(width: 56, height: 56)
                Image(systemName: Theme.Symbol.location)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Theme.fairwayBright)
            }

            VStack(spacing: 4) {
                ProgressView()
                Text("Finding nearby courses…")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.dimText)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            browseAllButton
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .fairwayBackground()
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
                    .buttonStyle(.plain)
                }
            } header: {
                Label("Nearby", systemImage: Theme.Symbol.location)
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .tracking(1)
            }

            Section {
                browseAllButton
                    .listRowBackground(Color.clear)
                manualButton
                    .listRowBackground(Color.clear)
            }
        }
    }

    private func noLocationView(icon: String, title: String, message: String) -> some View {
        VStack(spacing: 14) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Theme.bunker.opacity(0.15))
                    .frame(width: 56, height: 56)
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Theme.bunker)
            }

            VStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                Text(message)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.dimText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 6)
            }

            Spacer()

            browseAllButton
            manualButton
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .fairwayBackground()
    }

    private var browseAllButton: some View {
        Button {
            let all = CourseLibrary.shared.alphabetical()
            detectState = all.isEmpty ? .noResults : .results(all)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: Theme.Symbol.course)
                    .font(.system(size: 11, weight: .bold))
                Text("Browse Courses")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Capsule().fill(Theme.fairway))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Browse all courses")
    }

    private var manualButton: some View {
        Button(action: onManual) {
            Text("Custom Round")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Capsule().stroke(Theme.textPrimary.opacity(0.18), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Set up a custom round without a course")
    }
}

// MARK: - Course row

private struct CourseRow: View {
    let course: CourseData

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(Theme.fairway.opacity(0.18))
                    .frame(width: 26, height: 26)
                Image(systemName: Theme.Symbol.pin)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.fairwayBright)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(course.name)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text("\(course.numberOfHoles) holes")
                    Text("·")
                    Text("Par \(course.totalPar)")
                }
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Theme.dimText)
            }

            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(course.name), \(course.numberOfHoles) holes, par \(course.totalPar)")
    }
}
