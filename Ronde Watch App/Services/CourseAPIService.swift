import Foundation
import CoreLocation
import os

/// Fetches nearby golf courses from GolfCourseAPI.com.
/// Falls back to mock data when the API key is empty or any request fails.
///
/// To enable live data: set `apiKey` below to your key from golfcourseapi.com
/// (free tier — 300 req/day). Leave it empty to use mock data.
@MainActor
final class CourseAPIService {
    static let shared = CourseAPIService()

    // Replace with your GolfCourseAPI.com key to enable live course lookup.
    private let apiKey = ""
    private let baseURL = URL(string: "https://api.golfcourseapi.com/v1")!
    private let logger = Logger(subsystem: "com.ronde.Ronde", category: "CourseAPIService")

    /// Session-level cache keyed by a ~1 km grid cell.
    private var sessionCache: [String: [CourseData]] = [:]

    // MARK: - Public API

    func fetchNearbyCourses(location: CLLocation) async -> [CourseData] {
        guard !apiKey.isEmpty else {
            logger.info("No API key — returning mock courses")
            return CourseAPIService.mockCourses()
        }

        let cacheKey = locationCacheKey(for: location)
        if let cached = sessionCache[cacheKey] {
            logger.info("Cache hit for key \(cacheKey)")
            return cached
        }

        do {
            let query = try await reverseGeocodeQuery(for: location)
            let courses = try await searchCourses(query: query, near: location)
            sessionCache[cacheKey] = courses
            return courses
        } catch {
            logger.error("Course fetch failed: \(error.localizedDescription) — using mock data")
            return CourseAPIService.mockCourses()
        }
    }

    // MARK: - Private Helpers

    private func reverseGeocodeQuery(for location: CLLocation) async throws -> String {
        let geocoder = CLGeocoder()
        let placemarks = try await geocoder.reverseGeocodeLocation(location)
        guard let placemark = placemarks.first else { throw APIError.geocodingFailed }
        let parts = [placemark.locality, placemark.administrativeArea].compactMap { $0 }
        guard !parts.isEmpty else { throw APIError.geocodingFailed }
        return parts.joined(separator: ", ")
    }

    private func searchCourses(query: String, near location: CLLocation) async throws -> [CourseData] {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("search"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "search_query", value: query)]
        guard let url = components.url else { throw APIError.badURL }

        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue("Key \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw APIError.badStatus
        }

        let apiResponse = try JSONDecoder().decode(CourseSearchResponse.self, from: data)
        let courses = apiResponse.courses.compactMap { CourseData(apiCourse: $0) }

        // Sort by distance from the user's current location.
        return courses.sorted {
            CLLocation(latitude: $0.latitude, longitude: $0.longitude).distance(from: location) <
            CLLocation(latitude: $1.latitude, longitude: $1.longitude).distance(from: location)
        }
    }

    /// Rounds lat/lng to a ~1 km grid so nearby queries share a cache entry.
    private func locationCacheKey(for location: CLLocation) -> String {
        let lat = Int(location.coordinate.latitude * 100)
        let lng = Int(location.coordinate.longitude * 100)
        return "\(lat),\(lng)"
    }

    // MARK: - Errors

    enum APIError: Error {
        case geocodingFailed
        case badURL
        case badStatus
    }

    // MARK: - Mock Data

    static func mockCourses() -> [CourseData] {
        [
            CourseData(
                id: "mock-1",
                name: "Pine Valley Golf Club",
                address: "1 Pine Valley Dr, Pine Valley, NJ",
                latitude: 39.7875,
                longitude: -74.9681,
                holes: (1...18).map { n in
                    HoleData(number: n, par: [3, 5, 10, 14].contains(n) ? 3 : [7, 13, 15].contains(n) ? 5 : 4, yardage: nil)
                }
            ),
            CourseData(
                id: "mock-2",
                name: "Pebble Beach Golf Links",
                address: "1700 17-Mile Dr, Pebble Beach, CA",
                latitude: 36.5675,
                longitude: -121.9498,
                holes: (1...18).map { n in
                    HoleData(number: n, par: [5, 7, 17].contains(n) ? 3 : [6, 14, 18].contains(n) ? 5 : 4, yardage: nil)
                }
            ),
            CourseData(
                id: "mock-3",
                name: "Augusta National Golf Club",
                address: "2604 Washington Rd, Augusta, GA",
                latitude: 33.5032,
                longitude: -82.0182,
                holes: (1...18).map { n in
                    HoleData(number: n, par: [4, 6, 12, 16].contains(n) ? 3 : [2, 8, 13, 15].contains(n) ? 5 : 4, yardage: nil)
                }
            ),
        ]
    }
}

// MARK: - API Response Models

private struct CourseSearchResponse: Decodable {
    let courses: [APICourse]
}

private struct APICourse: Decodable {
    let id: Int
    let clubName: String
    let courseName: String?
    let location: APILocation?
    let holes: [APIHole]?

    enum CodingKeys: String, CodingKey {
        case id
        case clubName = "club_name"
        case courseName = "course_name"
        case location
        case holes
    }
}

private struct APILocation: Decodable {
    let address: String?
    let city: String?
    let state: String?
    let latitude: Double?
    let longitude: Double?
}

private struct APIHole: Decodable {
    let holeNumber: Int
    let par: Int
    let yardage: Int?

    enum CodingKeys: String, CodingKey {
        case holeNumber = "hole_number"
        case par
        case yardage
    }
}

// MARK: - CourseData convenience init from API response

private extension CourseData {
    init?(apiCourse: APICourse) {
        guard let loc = apiCourse.location,
              let lat = loc.latitude,
              let lng = loc.longitude else { return nil }

        let name: String
        if let courseName = apiCourse.courseName, !courseName.isEmpty {
            name = "\(apiCourse.clubName) — \(courseName)"
        } else {
            name = apiCourse.clubName
        }

        let address = [loc.address, loc.city, loc.state]
            .compactMap { $0 }
            .joined(separator: ", ")

        let holesData: [HoleData]
        if let apiHoles = apiCourse.holes, !apiHoles.isEmpty {
            holesData = apiHoles.map { HoleData(number: $0.holeNumber, par: $0.par, yardage: $0.yardage) }
        } else {
            holesData = (1...18).map { HoleData(number: $0, par: 4, yardage: nil) }
        }

        self.init(
            id: String(apiCourse.id),
            name: name,
            address: address,
            latitude: lat,
            longitude: lng,
            holes: holesData
        )
    }
}
