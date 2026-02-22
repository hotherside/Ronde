import SwiftUI

struct StartView: View {
    @Environment(\.modelContext) private var modelContext

    // Navigation
    @State private var path = NavigationPath()

    // Round config accumulated across steps.
    // numberOfHoles is always pars.count — there is no separate state for it.
    @State private var date = Date.now
    @State private var pars: [Int] = Array(repeating: 4, count: 18)
    @State private var courseName: String?

    let onStartRound: (Round) -> Void

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
                pars = Array(repeating: 4, count: 9)
                path.append(Dest.parSetup)
            } label: {
                Text("9 Holes")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            Button {
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
            numberOfHoles: pars.count,
            pars: pars
        )
        modelContext.insert(round)
        onStartRound(round)
    }
}
