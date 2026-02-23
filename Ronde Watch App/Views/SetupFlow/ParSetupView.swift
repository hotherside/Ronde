import SwiftUI
import WatchKit

struct ParSetupView: View {
    let courseName: String?
    @Binding var date: Date
    @Binding var pars: [Int]
    let onStart: () -> Void

    // Derived from the binding — can never diverge from pars.count.
    private var numberOfHoles: Int { pars.count }

    private var totalPar: Int {
        pars.reduce(0, +)
    }

    var body: some View {
        List {
            // Course + summary header
            Section {
                if let name = courseName {
                    Text(name)
                        .font(.headline)
                        .lineLimit(1)
                }
                HStack {
                    Text("Total Par")
                        .font(.headline)
                    Spacer()
                    Text("\(totalPar)")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Total par: \(totalPar)")

                DatePicker("Date", selection: $date, displayedComponents: .date)
            }

            Section("Set Par Per Hole") {
                // Use pars.indices so the subscript is always in bounds.
                ForEach(pars.indices, id: \.self) { index in
                    HoleParRow(
                        holeNumber: index + 1,
                        par: $pars[index]
                    )
                }
            }

            Section {
                Button(action: onStart) {
                    Text("Start Round")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(.green))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Start round with \(numberOfHoles) holes, total par \(totalPar)")
                .listRowBackground(Color.clear)
            }
        }
        .navigationTitle(courseName != nil ? "Adjust Par" : "\(numberOfHoles) Holes")
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
            .accessibilityLabel("Decrease par for hole \(holeNumber)")

            Text("\(par)")
                .font(.body.monospacedDigit().bold())
                .frame(width: 24, alignment: .center)
                .accessibilityLabel("Par \(par)")

            Button {
                if par < 5 { par += 1 }
                WKInterfaceDevice.current().play(.click)
            } label: {
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(par < 5 ? .blue : .gray)
            }
            .buttonStyle(.plain)
            .disabled(par >= 5)
            .accessibilityLabel("Increase par for hole \(holeNumber)")
        }
        .accessibilityElement(children: .contain)
    }
}
