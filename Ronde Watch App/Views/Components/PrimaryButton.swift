import SwiftUI

/// High-contrast primary action sized for hurried, one-handed Watch use.
struct PrimaryButton: View {
    let title: String
    var icon: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .bold))
                }
                Text(title)
                    .font(.system(size: 14, weight: .bold))
            }
            .foregroundStyle(Color.black.opacity(0.88))
            .frame(maxWidth: .infinity)
            .frame(minHeight: 48)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Theme.fairway)
            )
        }
        .buttonStyle(RondePressStyle())
    }
}
