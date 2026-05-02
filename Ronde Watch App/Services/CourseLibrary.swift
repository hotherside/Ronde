import Foundation
import CoreLocation
import os

/// Loads the bundled Sydney golf course catalog and returns nearby matches.
///
/// The course list lives in `Resources/SydneyCourses.json` and is shipped
/// inside the app bundle so the watch can find courses entirely offline.
@MainActor
final class CourseLibrary {
    static let shared = CourseLibrary()

    private let logger = Logger(subsystem: "com.ronde.Ronde", category: "CourseLibrary")
    private(set) lazy var allCourses: [CourseData] = loadCatalog()

    /// Courses sorted by distance from the given location, optionally filtered
    /// to those within `maxKilometers`.
    func nearby(_ location: CLLocation, maxKilometers: Double = 50, limit: Int = 5) -> [CourseData] {
        let withDistance = allCourses.map { course -> (CourseData, CLLocationDistance) in
            let courseLoc = CLLocation(latitude: course.latitude, longitude: course.longitude)
            return (course, courseLoc.distance(from: location))
        }

        return withDistance
            .filter { $0.1 <= maxKilometers * 1000 }
            .sorted { $0.1 < $1.1 }
            .prefix(limit)
            .map(\.0)
    }

    /// All courses sorted alphabetically — used as the manual-entry fallback list.
    func alphabetical() -> [CourseData] {
        allCourses.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: - Private

    private func loadCatalog() -> [CourseData] {
        guard let url = Bundle.main.url(forResource: "SydneyCourses", withExtension: "json") else {
            logger.error("SydneyCourses.json missing from bundle")
            return []
        }

        do {
            let data = try Data(contentsOf: url)
            let courses = try JSONDecoder().decode([CourseData].self, from: data)
            logger.info("Loaded \(courses.count) bundled courses")
            return courses
        } catch {
            logger.error("Failed to decode SydneyCourses.json: \(error.localizedDescription)")
            return []
        }
    }
}
