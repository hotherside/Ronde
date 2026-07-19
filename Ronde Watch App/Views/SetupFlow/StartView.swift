import SwiftUI
import os

private let setupLog = Logger(subsystem: "com.ronde.Ronde", category: "RoundSetup")

struct StartView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var path = NavigationPath()
    @State private var pars: [Int] = Array(repeating: 4, count: 18)
    @State private var courseName: String?
    @State private var courseDistanceDisplay: String?

    let onStartRound: (Round) -> Void

    private enum Dest: Hashable {
        case ready
        case parSetup
    }

    var body: some View {
        NavigationStack(path: $path) {
            CourseDetectView(
                onCourseSelected: { course in
                    courseName = course.name
                    pars = course.pars
                    courseDistanceDisplay = course.totalDistanceDisplay
                    path.append(Dest.ready)
                },
                onQuickStart: { holes in
                    courseName = nil
                    courseDistanceDisplay = nil
                    pars = Array(repeating: 4, count: holes)
                    startRound()
                }
            )
            .navigationDestination(for: Dest.self) { destination in
                switch destination {
                case .ready:
                    ReadyView(
                        courseName: courseName,
                        numberOfHoles: pars.count,
                        totalPar: pars.reduce(0, +),
                        courseDistanceDisplay: courseDistanceDisplay,
                        onEditPars: { path.append(Dest.parSetup) },
                        onStart: startRound
                    )
                case .parSetup:
                    ParSetupView(
                        courseName: courseName,
                        courseDistanceDisplay: courseDistanceDisplay,
                        pars: $pars,
                        onStart: startRound
                    )
                }
            }
        }
    }

    private func startRound() {
        UserDefaults.standard.set(pars.count, forKey: "preferredHoleCount")
        let round = Round(
            date: .now,
            courseName: courseName,
            numberOfHoles: pars.count,
            pars: pars
        )
        modelContext.insert(round)
        do {
            try modelContext.save()
        } catch {
            setupLog.error("Round save failed at start: \(error.localizedDescription)")
        }
        onStartRound(round)
    }
}
