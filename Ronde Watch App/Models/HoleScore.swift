import Foundation
import SwiftData

@Model
final class HoleScore {
    var id: UUID
    var holeNumber: Int
    var par: Int
    var shots: Int
    var isComplete: Bool
    var round: Round?

    /// Per-swing metrics collected during play. Only populated for auto-detected swings.
    var swingData: [SwingMetrics] = []

    var scoreToPar: Int {
        shots - par
    }

    var scoreLabel: String {
        if shots == 0 { return "—" }
        let diff = scoreToPar
        if diff == 0 { return "E" }
        return diff > 0 ? "+\(diff)" : "\(diff)"
    }

    // MARK: - Swing Aggregates

    var swingCount: Int { swingData.count }

    var averageSpeedKMH: Double {
        guard !swingData.isEmpty else { return 0 }
        return swingData.map(\.estimatedSpeedKMH).reduce(0, +) / Double(swingData.count)
    }

    var fastestSpeedKMH: Double {
        swingData.map(\.estimatedSpeedKMH).max() ?? 0
    }

    var averagePeakG: Double {
        guard !swingData.isEmpty else { return 0 }
        return swingData.map(\.peakG).reduce(0, +) / Double(swingData.count)
    }

    var bestTempo: Double {
        swingData.map(\.tempoSeconds).min() ?? 0
    }

    // MARK: - Init

    init(holeNumber: Int, par: Int) {
        self.id = UUID()
        self.holeNumber = holeNumber
        self.par = par
        self.shots = 0
        self.isComplete = false
    }

    func incrementShot() {
        shots += 1
    }

    func decrementShot() {
        if shots > 0 {
            shots -= 1
        }
    }
}
