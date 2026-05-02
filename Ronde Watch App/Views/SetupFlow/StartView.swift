import SwiftUI

struct StartView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var path = NavigationPath()

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
        VStack(spacing: 12) {
            Spacer()

            Text("How many holes?")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)

            holeCountButton(holes: 9)
            holeCountButton(holes: 18)

            Spacer()
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .fairwayBackground()
        .containerBackground(Theme.surface.gradient, for: .navigation)
        .navigationTitle("")
    }

    private func holeCountButton(holes: Int) -> some View {
        Button {
            pars = Array(repeating: 4, count: holes)
            path.append(Dest.parSetup)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: Theme.Symbol.pin)
                    .font(.system(size: 11, weight: .bold))
                Text("\(holes) Holes")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Capsule().fill(Theme.fairway))
        }
        .buttonStyle(.plain)
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
