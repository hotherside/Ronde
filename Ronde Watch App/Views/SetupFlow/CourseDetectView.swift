import SwiftUI
import CoreLocation

/// Detects the user's location, queries the course API, and lets them
/// pick from nearby courses or fall through to manual setup.
struct CourseDetectView: View {
    let onCourseSelected: (CourseData) -> Void
    let onManual: () -> Void

    @StateObject private var locationService = LocationService()
    @State private var detectState: DetectState = .detecting

    private enum DetectState {
        case detecting
        case searching
        case results([CourseData])
        case denied
        case failed
        case noResults
    }

    // MARK: - Body

    var body: some View {
        Group {
            switch detectState {
            case .detecting:
                loadingView(label: "Detecting location…")
            case .searching:
                loadingView(label: "Finding courses…")
            case .results(let courses):
                resultsList(courses: courses)
            case .denied:
                errorView(icon: "location.slash", message: "Location access denied")
            case .failed:
                errorView(icon: "wifi.slash", message: "Couldn't detect course")
            case .noResults:
                errorView(icon: "map", message: "No courses found nearby")
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
            Task { await searchCourses(near: location) }
        }
    }

    // MARK: - Detection Logic

    private var isDetecting: Bool {
        if case .detecting = detectState { return true }
        return false
    }

    private func startDetection() async {
        // React to an already-denied status without waiting for the delegate.
        switch locationService.authorizationStatus {
        case .denied, .restricted:
            detectState = .denied
            return
        default:
            break
        }

        locationService.requestPermissionAndLocation()

        // 15-second timeout: if no fix arrives, fall through to manual.
        try? await Task.sleep(for: .seconds(15))
        if case .detecting = detectState {
            detectState = .failed
        }
    }

    private func searchCourses(near location: CLLocation) async {
        detectState = .searching
        locationService.stopUpdates()
        let courses = await CourseAPIService.shared.fetchNearbyCourses(location: location)
        if courses.isEmpty {
            detectState = .noResults
        } else {
            detectState = .results(Array(courses.prefix(3)))
        }
    }

    // MARK: - Sub-views

    private func loadingView(label: String) -> some View {
        VStack(spacing: 16) {
            ProgressView()
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
            manualButton
        }
        .padding()
    }

    private func resultsList(courses: [CourseData]) -> some View {
        List {
            Section("Nearby Courses") {
                ForEach(courses) { course in
                    Button {
                        onCourseSelected(course)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(course.name)
                                .font(.body)
                                .lineLimit(1)
                            Text("\(course.numberOfHoles) holes · Par \(course.totalPar)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(course.name), \(course.numberOfHoles) holes, par \(course.totalPar)")
                }
            }

            Section {
                manualButton
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    private func errorView(icon: String, message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
            manualButton
        }
        .padding()
    }

    private var manualButton: some View {
        Button("Enter manually", action: onManual)
            .buttonStyle(.bordered)
            .accessibilityLabel("Set up round manually without GPS")
    }
}
