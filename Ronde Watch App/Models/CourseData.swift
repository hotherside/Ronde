import Foundation

/// Represents golf course data from the API or local cache.
/// Used for auto-detect flow (Session 5). Stubbed for now.
struct CourseData: Codable, Identifiable {
    let id: String
    let name: String
    let address: String
    let latitude: Double
    let longitude: Double
    let yardageUnit: String?
    let holes: [HoleData]

    var numberOfHoles: Int { holes.count }
    var totalPar: Int { holes.reduce(0) { $0 + $1.par } }
    var pars: [Int] { holes.sorted { $0.number < $1.number }.map(\.par) }

    /// Sum of per-hole yardage. `nil` if any hole is missing yardage — avoids
    /// quoting a deceptively short course distance.
    var totalYardage: Int? {
        var sum = 0
        for hole in holes {
            guard let y = hole.yardage else { return nil }
            sum += y
        }
        return holes.isEmpty ? nil : sum
    }

    /// Total course length in metres regardless of source unit.
    var totalDistanceMeters: Double? {
        guard let total = totalYardage else { return nil }
        let unit = (yardageUnit ?? "metres").lowercased()
        if unit == "yards" || unit == "yds" || unit == "yd" {
            return Double(total) / 1.0936133
        }
        return Double(total)
    }

    /// One-decimal km string when ≥ 1 km, otherwise rounded metres. Single
    /// source of truth for course-distance UI.
    var totalDistanceDisplay: String? {
        guard let metres = totalDistanceMeters else { return nil }
        if metres >= 1000 {
            return String(format: "%.1f km", metres / 1000)
        }
        return "\(Int(metres.rounded())) m"
    }
}

struct HoleData: Codable, Identifiable {
    var id: Int { number }
    let number: Int
    let par: Int
    let yardage: Int?
}
