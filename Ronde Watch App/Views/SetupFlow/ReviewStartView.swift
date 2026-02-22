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
                .font(.headline)

            HStack {
                Label("\(numberOfHoles) holes", systemImage: "flag.fill")
                Spacer()
                Label("Par \(totalPar)", systemImage: "number")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Text(date, style: .date)
                .font(.caption2)
                .foregroundStyle(.secondary)

            Button("Start Round", action: onStart)
                .buttonStyle(.borderedProminent)
                .tint(.green)
        }
        .padding()
    }
}
