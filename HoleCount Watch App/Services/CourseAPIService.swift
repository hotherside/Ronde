import Foundation

/// Placeholder for Session 5: GolfCourseAPI.com integration.
/// Free tier: 300 requests/day, ~30,000 courses worldwide.
/// Base URL: https://api.golfcourseapi.com/v1
/// Auth: API key in header
struct CourseAPIService {
    // TODO: Session 5 - Add real API key and implementation
    // func searchCourses(lat: Double, lng: Double, radius: Double) async throws -> [CourseData]
    // func getCourseDetails(id: String) async throws -> CourseData

    /// Returns mock course data for development and testing.
    static func mockCourses() -> [CourseData] {
        [
            CourseData(
                id: "mock-1",
                name: "Pine Valley Golf Club",
                address: "1 Pine Valley Dr, Pine Valley, NJ",
                latitude: 39.7875,
                longitude: -74.9681,
                holes: (1...18).map { number in
                    let par: Int
                    switch number {
                    case 3, 5, 10, 14: par = 3
                    case 7, 13, 15: par = 5
                    default: par = 4
                    }
                    return HoleData(number: number, par: par, yardage: nil)
                }
            ),
        ]
    }
}
