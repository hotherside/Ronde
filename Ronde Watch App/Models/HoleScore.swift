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

    var scoreToPar: Int {
        shots - par
    }

    var scoreLabel: String {
        if shots == 0 { return "—" }
        let diff = scoreToPar
        if diff == 0 { return "E" }
        return diff > 0 ? "+\(diff)" : "\(diff)"
    }

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
