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

    private var headerTitle: String {
        courseName != nil ? "Adjust Par" : "\(numberOfHoles) Holes"
    }

    var body: some View {
        VStack(spacing: 0) {
            NavHeader(title: headerTitle, leading: .back)

            List {
                // Course header card
                Section {
                    VStack(spacing: 6) {
                        if let name = courseName {
                            HStack(spacing: 5) {
                                Image(systemName: Theme.Symbol.course)
                                    .font(.system(size: 10))
                                    .foregroundStyle(Theme.fairwayBright)
                                Text(name)
                                    .font(.bodyEmphasized)
                                    .foregroundStyle(Theme.textPrimary)
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.9)
                                    .multilineTextAlignment(.center)
                            }
                        }

                        StatPair(
                            leading: .init(value: "\(numberOfHoles)", label: "Holes"),
                            trailing: .init(value: "\(totalPar)", label: "Par")
                        )
                        .padding(.top, 2)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .listRowBackground(Theme.cardSurfaceShape)

                    NavigationLink {
                        DatePickerDetailView(date: $date)
                    } label: {
                        DateRow(date: date)
                    }
                    .buttonStyle(CardRowButtonStyle())
                    .listRowBackground(Theme.cardSurfaceShape)
                }

                Section {
                    ForEach(pars.indices, id: \.self) { index in
                        HoleParRow(
                            holeNumber: index + 1,
                            par: $pars[index]
                        )
                        .listRowBackground(Theme.cardSurfaceShape)
                    }
                } header: {
                    Text("Par per hole").sectionHeaderStyle()
                }

                Section {
                    PrimaryButton(title: "Tee Off", icon: Theme.Symbol.golfer, action: onStart)
                        .padding(.vertical, 2)
                        .accessibilityLabel("Start round with \(numberOfHoles) holes, total par \(totalPar)")
                        .listRowBackground(Color.clear)
                }
            }
            .scrollContentBackground(.hidden)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.surface)
        .fairwayContainerBackground()
        .toolbar(.hidden, for: .navigationBar)
    }
}

private struct HoleParRow: View {
    let holeNumber: Int
    @Binding var par: Int

    var body: some View {
        HStack(spacing: 8) {
            Text("\(holeNumber)")
                .font(.body)
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
                .foregroundStyle(Theme.textPrimary)
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
