import SwiftUI
import WatchKit

struct ParSetupView: View {
    let courseName: String?
    @Binding var date: Date
    @Binding var pars: [Int]
    let onStart: () -> Void

    private var numberOfHoles: Int { pars.count }

    private var totalPar: Int {
        pars.reduce(0, +)
    }

    var body: some View {
        List {
            // Course header
            Section {
                VStack(spacing: 6) {
                    if let name = courseName {
                        HStack(spacing: 5) {
                            Image(systemName: Theme.Symbol.course)
                                .font(.system(size: 10))
                                .foregroundStyle(Theme.fairwayBright)
                            Text(name)
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .lineLimit(1)
                        }
                    }

                    HStack(spacing: 0) {
                        statColumn(value: "\(numberOfHoles)", label: "HOLES")
                        Rectangle().fill(.white.opacity(0.10)).frame(width: 1, height: 24)
                        statColumn(value: "\(totalPar)", label: "PAR")
                    }
                    .padding(.top, 2)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(numberOfHoles) holes, total par \(totalPar)")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)

                DatePicker(
                    "Date",
                    selection: $date,
                    in: ...Date.now,
                    displayedComponents: .date
                )
                .font(.system(size: 12, weight: .semibold, design: .rounded))
            }

            Section("Par per hole") {
                ForEach(pars.indices, id: \.self) { index in
                    HoleParRow(
                        holeNumber: index + 1,
                        par: $pars[index]
                    )
                }
            }

            Section {
                Button(action: onStart) {
                    HStack(spacing: 6) {
                        Image(systemName: Theme.Symbol.golfer)
                            .font(.system(size: 13, weight: .bold))
                        Text("Tee Off")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(Theme.fairway))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Start round with \(numberOfHoles) holes, total par \(totalPar)")
                .listRowBackground(Color.clear)
            }
        }
        .navigationTitle(courseName != nil ? "Adjust Par" : "\(numberOfHoles) Holes")
    }

    private func statColumn(value: String, label: String) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.scoreNumeral(size: 22))
                .foregroundStyle(.white)
            Text(label)
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.dimText)
                .tracking(0.8)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct HoleParRow: View {
    let holeNumber: Int
    @Binding var par: Int

    var body: some View {
        HStack(spacing: 8) {
            Text("\(holeNumber)")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Theme.mutedText)
                .frame(width: 18, alignment: .leading)

            Spacer()

            Button {
                if par > 3 { par -= 1 }
                WKInterfaceDevice.current().play(.click)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(par > 3 ? Theme.sky : Theme.faintText)
            }
            .buttonStyle(.plain)
            .disabled(par <= 3)
            .accessibilityLabel("Decrease par for hole \(holeNumber)")

            Text("P\(par)")
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .frame(width: 30, alignment: .center)
                .accessibilityLabel("Par \(par)")

            Button {
                if par < 5 { par += 1 }
                WKInterfaceDevice.current().play(.click)
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(par < 5 ? Theme.sky : Theme.faintText)
            }
            .buttonStyle(.plain)
            .disabled(par >= 5)
            .accessibilityLabel("Increase par for hole \(holeNumber)")
        }
        .accessibilityElement(children: .contain)
    }
}
