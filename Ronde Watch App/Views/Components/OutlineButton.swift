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
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(Theme.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(
                Capsule().stroke(Theme.textPrimary.opacity(0.18), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
