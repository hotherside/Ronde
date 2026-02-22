import SwiftUI

struct StartView: View {
    @Environment(\.modelContext) private var modelContext

    // Navigation
    @State private var path = NavigationPath()

    // Round config accumulated across steps
    @State private var date = Date.now
    @State private var numberOfHoles: Int = 18
    @State private var pars: [Int] = Array(repeating: 4, count: 18)
    @State private var courseName: String?

    let onStartRound: (Round) -> Void

    // Typed destinations for the navigation stack.
    private enum Dest: Hashable {
        case manualHoleSelect
        case parSetup
    }

    var body: some View {
        NavigationStack(path: $path) {
            // Root: GPS course detection.
            CourseDetectView(
                onCourseSelected: { course in
                    courseName = course.name
                    numberOfHoles = course.numberOfHoles
                    pars = course.pars
                    path.append(Dest.parSetup)
                },
                onManual: {
                    courseName = nil
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
                        numberOfHoles: numberOfHoles,
                        date: $date,
                        pars: $pars,
                        onStart: startRound
                    )
                }
            }
        }
    }

    // MARK: - Manual hole-count selection

    private var manualHoleSelectView: some View {
        VStack(spacing: 14) {
            Text("How many holes?")
                .font(.headline)

            Button {
                numberOfHoles = 9
                pars = Array(repeating: 4, count: 9)
                path.append(Dest.parSetup)
            } label: {
                Text("9 Holes")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            Button {
                numberOfHoles = 18
                pars = Array(repeating: 4, count: 18)
                path.append(Dest.parSetup)
            } label: {
                Text("18 Holes")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .navigationTitle("Manual Setup")
    }

    // MARK: - Round creation

    private func startRound() {
        let round = Round(
            date: date,
            courseName: courseName,
            numberOfHoles: numberOfHoles,
            pars: pars
        )
        modelContext.insert(round)
        onStartRound(round)
    }
}
