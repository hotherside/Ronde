import SwiftUI

/// Two-up stat block — used in setup ("HOLES | PAR") and reusable for the
/// round-summary header. Hairline divider in the middle, matching the
/// scorecard aesthetic.
struct StatPair: View {
    struct Stat {
        let value: String
        let label: String
    }

    let leading: Stat
    let trailing: Stat

    var body: some View {
        HStack(spacing: 0) {
            column(leading)
            Rectangle()
                .fill(Theme.textPrimary.opacity(0.12))
                .frame(width: 1, height: 24)
            column(trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(leading.label) \(leading.value), \(trailing.label) \(trailing.value)")
    }

    private func column(_ stat: Stat) -> some View {
        VStack(spacing: 1) {
            Text(stat.value)
                .font(.scoreNumeral(size: 22))
                .foregroundStyle(Theme.textPrimary)
            Text(stat.label)
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.dimText)
                .tracking(0.8)
                .textCase(.uppercase)
        }
        .frame(maxWidth: .infinity)
    }
}
