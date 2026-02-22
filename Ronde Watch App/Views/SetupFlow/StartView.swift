import SwiftUI

struct StartView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var numberOfHoles: Int?
    @State private var date = Date.now
    @State private var pars: [Int] = []

    let onStartRound: (Round) -> Void

    var body: some View {
        NavigationStack {
            if let holes = numberOfHoles {
                ParSetupView(
                    numberOfHoles: holes,
                    date: $date,
                    pars: $pars,
                    onStart: startRound,
                    onBack: { numberOfHoles = nil }
                )
            } else {
                holeSelection
            }
        }
    }

    private var holeSelection: some View {
        VStack(spacing: 12) {
            Text("New Round")
                .font(.headline)

            DatePicker("Date", selection: $date, displayedComponents: .date)
                .padding(.bottom, 4)

            Button {
                numberOfHoles = 9
                pars = Array(repeating: 4, count: 9)
            } label: {
                Text("9 Holes")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            Button {
                numberOfHoles = 18
                pars = Array(repeating: 4, count: 18)
            } label: {
                Text("18 Holes")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    private func startRound() {
        guard let holes = numberOfHoles else { return }
        let round = Round(
            date: date,
            numberOfHoles: holes,
            pars: pars
        )
        modelContext.insert(round)
        onStartRound(round)
    }
}
