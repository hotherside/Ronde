import SwiftUI

/// Final confirmation step after par setup. Recaps the round (course, holes,
/// par, total distance) and waits for an explicit "Start Round" tap before
/// the workout, pedometer, and shot counter come alive. Inserts the `Round`
/// into SwiftData only on confirmation, so backing out leaves no orphan.
struct ReadyView: View {
    let courseName: String?
    let numberOfHoles: Int
    let totalPar: Int
    let courseDistanceDisplay: String?
    let onStart: () -> Void

    private var displayName: String {
        courseName ?? "Custom Round"
    }

    var body: some View {
        VStack(spacing: 10) {
            VStack(spacing: 6) {
                HStack(spacing: 5) {
                    Image(systemName: courseName == nil ? Theme.Symbol.pin : Theme.Symbol.course)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.fairwayBright)
                    Text(displayName)
                        .font(.titleSmall)
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                        .multilineTextAlignment(.center)
                }

                StatPair(
                    leading: .init(value: "\(numberOfHoles)", label: "Holes"),
                    trailing: .init(value: "\(totalPar)", label: "Par")
                )
                .padding(.top, 2)

                if let distance = courseDistanceDisplay {
                    Label(distance, systemImage: Theme.Symbol.walking)
                        .font(.caption)
                        .foregroundStyle(Theme.dimText)
                        .accessibilityLabel("Total course distance \(distance)")
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .background(Theme.cardSurfaceShape)

            Spacer(minLength: 4)

            PrimaryButton(title: "Start Round", icon: Theme.Symbol.golfer, action: onStart)
                .accessibilityLabel("Start round and begin tracking")
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .fairwayBackground()
        .fairwayContainerBackground()
        .navigationTitle("Ready?")
    }
}
