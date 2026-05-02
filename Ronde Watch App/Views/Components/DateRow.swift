import SwiftUI

/// Tappable card row showing the round date in a readable, single-line format.
/// Replaces the inline `DatePicker` whose Day/Month/Year focus pills overlapped
/// the date numbers at watch width.
struct DateRow: View {
    let date: Date

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(Theme.fairway.opacity(0.18))
                    .frame(width: 26, height: 26)
                Image(systemName: Theme.Symbol.calendar)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.fairwayBright)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text("Date")
                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.dimText)
                    .tracking(0.8)
                    .textCase(.uppercase)
                Text(date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).year()))
                    .font(.bodyEmphasized)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Theme.textFaint)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Date, \(date.formatted(date: .complete, time: .omitted))")
    }
}
