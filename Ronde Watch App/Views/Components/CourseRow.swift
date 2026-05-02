import SwiftUI

/// Course row used in nearby-results and the alphabetical browse list.
/// Allows two lines for the course name with mild down-scaling so long names
/// like "Bardwell Valley Golf Club" no longer truncate to "Bardwell Valley
/// Golf C…".
struct CourseRow: View {
    let course: CourseData

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(Theme.fairway.opacity(0.18))
                    .frame(width: 26, height: 26)
                Image(systemName: Theme.Symbol.pin)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.fairwayBright)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(course.name)
                    .font(.bodyEmphasized)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.9)
                    .allowsTightening(true)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 4) {
                    Text("\(course.numberOfHoles) holes")
                    Text("·")
                    Text("Par \(course.totalPar)")
                }
                .font(.caption)
                .foregroundStyle(Theme.dimText)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(course.name), \(course.numberOfHoles) holes, par \(course.totalPar)")
    }
}
