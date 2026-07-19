import Foundation
import SwiftData

@Model
final class Round {
    var id: UUID
    var date: Date
    var courseName: String?
    var numberOfHoles: Int
    var isComplete: Bool
    var currentHoleIndex: Int
    var totalSteps: Int = 0
    var totalDistanceMeters: Double = 0.0

    @Relationship(deleteRule: .cascade, inverse: \HoleScore.round)
    var holeScores: [HoleScore]

    var totalPar: Int {
        holeScores.reduce(0) { $0 + $1.par }
    }

    var totalShots: Int {
        holeScores.reduce(0) { $0 + $1.shots }
    }

    /// Only holes with a recorded stroke participate in score-to-par. This
    /// prevents skipped or not-yet-played holes from reading as impossible
    /// under-par scores during and after a round.
    var scoredHoleScores: [HoleScore] {
        sortedHoleScores.filter { $0.shots > 0 }
    }

    var scoredPar: Int {
        scoredHoleScores.reduce(0) { $0 + $1.par }
    }

    var completedScoredHoleScores: [HoleScore] {
        scoredHoleScores.filter(\.isComplete)
    }

    var completedScoreToPar: Int {
        completedScoredHoleScores.reduce(0) { $0 + ($1.shots - $1.par) }
    }

    var hasCompletedScore: Bool {
        !completedScoredHoleScores.isEmpty
    }

    var scoreToPar: Int {
        totalShots - scoredPar
    }

    var completedHoleCount: Int {
        holeScores.filter(\.isComplete).count
    }

    var scoredHoleCount: Int {
        scoredHoleScores.count
    }

    var totalDistanceKm: Double {
        totalDistanceMeters / 1000.0
    }

    var currentHole: HoleScore? {
        let sorted = sortedHoleScores
        guard currentHoleIndex >= 0, currentHoleIndex < sorted.count else { return nil }
        return sorted[currentHoleIndex]
    }

    var sortedHoleScores: [HoleScore] {
        holeScores.sorted { $0.holeNumber < $1.holeNumber }
    }

    init(
        date: Date = .now,
        courseName: String? = nil,
        numberOfHoles: Int,
        pars: [Int]
    ) {
        self.id = UUID()
        self.date = date
        self.courseName = courseName
        self.numberOfHoles = numberOfHoles
        self.isComplete = false
        self.currentHoleIndex = 0
        self.totalSteps = 0
        self.totalDistanceMeters = 0.0
        self.holeScores = pars.enumerated().map { index, par in
            HoleScore(holeNumber: index + 1, par: par)
        }
    }

    func advanceToNextHole() {
        if let current = currentHole {
            current.isComplete = true
        }
        let actualHoleCount = sortedHoleScores.count
        if currentHoleIndex < actualHoleCount - 1 {
            currentHoleIndex += 1
        } else {
            isComplete = true
        }
    }
}
