import SwiftUI

/// Hairline-stroked capsule for secondary actions — pairs with `PrimaryButton`
/// in CTA stacks (e.g. "Browse Courses" + "Custom Round").
struct OutlineButton: View {
    let title: String
    var icon: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(Theme.textPrimary)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 44)
            .background(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(Theme.cardSurface)
                    .overlay {
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .stroke(Theme.separator, lineWidth: 1)
                    }
            )
        }
        .buttonStyle(RondePressStyle())
    }
}
