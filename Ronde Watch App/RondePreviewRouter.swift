#if DEBUG
import SwiftUI

/// Simulator-only visual QA entry points. Launch with
/// `RONDE_PREVIEW_SCREEN=round`, `transition`, `summary`, or `setup` to inspect
/// key Watch layouts without walking the entire flow.
struct RondePreviewRouter: View {
    let screen: String
    private let sampleRound: Round

    init(screen: String) {
        self.screen = screen
        self.sampleRound = Self.makeSampleRound(completed: screen == "summary")
    }

    var body: some View {
        switch screen {
        case "round":
            NavigationStack {
                ShotCounterView(
                    round: sampleRound,
                    onEndRound: {},
                    onDiscard: {},
                    startsTracking: false
                )
            }
        case "transition":
            if let hole = sampleRound.currentHole {
                HoleTransitionView(hole: hole, isLastHole: false, onContinue: {})
            }
        case "summary":
            NavigationStack {
                RoundSummaryView(round: sampleRound, onDone: nil)
            }
        case "setup":
            StartView { _ in }
        default:
            ContentView()
        }
    }

    private static func makeSampleRound(completed: Bool) -> Round {
        let pars = [4, 4, 3, 5, 4, 4, 3, 5, 4]
        let round = Round(
            date: .now,
            courseName: "The Australian Golf Club",
            numberOfHoles: pars.count,
            pars: pars
        )
        let holes = round.sortedHoleScores
        let sampleShots = [4, 3, 4, 5, 3, 5, 3, 4, 4]

        if completed {
            for index in holes.indices {
                holes[index].shots = sampleShots[index]
                holes[index].isComplete = true
                holes[index].distanceMeters = Double(340 + (index * 38))
            }
            round.currentHoleIndex = holes.count - 1
            round.isComplete = true
            round.totalSteps = 10_842
            round.totalDistanceMeters = 7_420
        } else {
            for index in 0..<min(4, holes.count) {
                holes[index].shots = sampleShots[index]
                holes[index].isComplete = true
            }
            round.currentHoleIndex = min(4, holes.count - 1)
            round.currentHole?.shots = 2
        }

        return round
    }
}
#endif
