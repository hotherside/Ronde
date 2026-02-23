import SwiftUI

/// Placeholder for the pre-round review screen.
/// Will show course name, hole count, total par, date before starting.
/// Currently the ParSetupView handles the "Start Round" action directly.
/// This view will become relevant when auto-detect flow is added (Session 5)
/// to confirm auto-filled course data before starting.
struct ReviewStartView: View {
    let courseName: String?
    let numberOfHoles: Int
    let totalPar: Int
    let date: Date
    let onStart: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Text(courseName ?? "Custom Round")
                .font(.system(size: 16, weight: .bold, design: .rounded))

            HStack {
                Label("\(numberOfHoles) holes", systemImage: "flag.fill")
                Spacer()
                Label("Par \(totalPar)", systemImage: "number")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Text(date, format: .dateTime.month(.abbreviated).day())
                .font(.caption2)
                .foregroundStyle(.secondary)

            Button(action: onStart) {
                Text("Start Round")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(.green))
            }
            .buttonStyle(.plain)
        }
        .padding()
    }
}
