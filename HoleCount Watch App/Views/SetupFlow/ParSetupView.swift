import SwiftUI

struct ParSetupView: View {
    let numberOfHoles: Int
    @Binding var date: Date
    @Binding var pars: [Int]
    let onStart: () -> Void
    let onBack: () -> Void

    private var totalPar: Int {
        pars.reduce(0, +)
    }

    var body: some View {
        List {
            Section {
                HStack {
                    Text("Total Par")
                        .font(.headline)
                    Spacer()
                    Text("\(totalPar)")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Set Par Per Hole") {
                ForEach(0..<numberOfHoles, id: \.self) { index in
                    HoleParRow(
                        holeNumber: index + 1,
                        par: $pars[index]
                    )
                }
            }

            Section {
                Button(action: onStart) {
                    Text("Start Round")
                        .frame(maxWidth: .infinity)
                        .fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }
        }
        .navigationTitle("\(numberOfHoles) Holes")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Back", action: onBack)
            }
        }
    }
}

private struct HoleParRow: View {
    let holeNumber: Int
    @Binding var par: Int

    var body: some View {
        HStack {
            Text("Hole \(holeNumber)")
                .font(.body)

            Spacer()

            Button {
                if par > 3 { par -= 1 }
                WKInterfaceDevice.current().play(.click)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(par > 3 ? .blue : .gray)
            }
            .buttonStyle(.plain)
            .disabled(par <= 3)

            Text("\(par)")
                .font(.body.monospacedDigit().bold())
                .frame(width: 24, alignment: .center)

            Button {
                if par < 5 { par += 1 }
                WKInterfaceDevice.current().play(.click)
            } label: {
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(par < 5 ? .blue : .gray)
            }
            .buttonStyle(.plain)
            .disabled(par >= 5)
        }
    }
}
