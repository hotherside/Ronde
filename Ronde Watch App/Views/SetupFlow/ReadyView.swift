import SwiftUI

struct ReadyView: View {
    let courseName: String?
    let numberOfHoles: Int
    let totalPar: Int
    let courseDistanceDisplay: String?
    let onEditPars: () -> Void
    let onStart: () -> Void

    private var displayName: String { courseName ?? "Quick Round" }

    var body: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 2)

            Image(systemName: Theme.Symbol.course)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Theme.fairway)
                .frame(width: 48, height: 48)
                .background(Theme.fairway.opacity(0.12), in: RoundedRectangle(cornerRadius: 15))

            VStack(spacing: 3) {
                Text(displayName)
                    .font(.titleSmall)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
                    .multilineTextAlignment(.center)
                HStack(spacing: 5) {
                    Text("\(numberOfHoles) holes")
                    Text("·")
                    Text("Par \(totalPar)")
                    if let courseDistanceDisplay {
                        Text("·")
                        Text(courseDistanceDisplay)
                    }
                }
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
            }

            Spacer(minLength: 2)

            PrimaryButton(title: "Start Round", icon: Theme.Symbol.golfer, action: onStart)
            OutlineButton(title: "Review Pars", icon: "slider.horizontal.3", action: onEditPars)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .fairwayBackground()
        .fairwayContainerBackground()
        .navigationTitle("Ready")
        .navigationBarTitleDisplayMode(.inline)
    }
}
