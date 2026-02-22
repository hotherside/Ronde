import Foundation

/// Represents golf course data from the API or local cache.
/// Used for auto-detect flow (Session 5). Stubbed for now.
struct CourseData: Codable, Identifiable {
    let id: String
    let name: String
    let address: String
    let latitude: Double
    let longitude: Double
    let holes: [HoleData]

    var numberOfHoles: Int { holes.count }
    var totalPar: Int { holes.reduce(0) { $0 + $1.par } }
    var pars: [Int] { holes.sorted { $0.number < $1.number }.map(\.par) }
}

struct HoleData: Codable, Identifiable {
    var id: Int { number }
    let number: Int
    let par: Int
    let yardage: Int?
}
