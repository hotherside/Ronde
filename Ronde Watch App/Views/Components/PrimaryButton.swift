import SwiftUI

/// Filled fairway-green capsule — the main call-to-action used across setup
/// and history screens ("Tee Off", "Browse Courses", "New Round").
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
                    .font(.system(size: 13, weight: .bold, design: .rounded))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(Capsule().fill(Theme.fairway))
        }
        .buttonStyle(.plain)
    }
}
