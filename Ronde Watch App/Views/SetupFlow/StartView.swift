import SwiftUI

struct StartView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var path = NavigationPath()

    @State private var date = Date.now
    @State private var pars: [Int] = Array(repeating: 4, count: 18)
    @State private var courseName: String?
    @State private var courseDistanceDisplay: String?

    let onStartRound: (Round) -> Void

    private enum Dest: Hashable {
        case manualHoleSelect
        case parSetup
        case ready
    }

    var body: some View {
        NavigationStack(path: $path) {
            CourseDetectView(
                onCourseSelected: { course in
                    courseName = course.name
                    pars = course.pars
                    courseDistanceDisplay = course.totalDistanceDisplay
                    path.append(Dest.parSetup)
                },
                onManual: {
                    courseName = nil
                    courseDistanceDisplay = nil
                    path.append(Dest.manualHoleSelect)
                }
            )
            .navigationDestination(for: Dest.self) { dest in
                switch dest {
                case .manualHoleSelect:
                    manualHoleSelectView
                case .parSetup:
                    ParSetupView(
                        courseName: courseName,
                        courseDistanceDisplay: courseDistanceDisplay,
                        date: $date,
                        pars: $pars,
                        onStart: { path.append(Dest.ready) }
                    )
                case .ready:
                    ReadyView(
                        courseName: courseName,
                        numberOfHoles: pars.count,
                        totalPar: pars.reduce(0, +),
                        courseDistanceDisplay: courseDistanceDisplay,
                        onStart: startRound
                    )
                }
            }
        }
    }

    // MARK: - Manual hole-count selection

    private var manualHoleSelectView: some View {
        VStack(spacing: 12) {
            Spacer()

            Text("How many holes?")
                .font(.titleSmall)
                .foregroundStyle(Theme.textPrimary)

            holeCountButton(holes: 9)
            holeCountButton(holes: 18)

            Spacer()
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .fairwayBackground()
        .fairwayContainerBackground()
        .navigationTitle("Custom Round")
    }

    private func holeCountButton(holes: Int) -> some View {
        PrimaryButton(title: "\(holes) Holes", icon: Theme.Symbol.pin) {
            pars = Array(repeating: 4, count: holes)
            path.append(Dest.parSetup)
        }
    }

    // MARK: - Round creation

    private func startRound() {
        let round = Round(
            date: date,
            courseName: courseName,
            numberOfHoles: pars.count,
            pars: pars
        )
        modelContext.insert(round)
        onStartRound(round)
    }
}
