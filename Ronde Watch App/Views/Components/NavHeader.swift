import SwiftUI

/// Custom inline navigation header — replaces `.navigationTitle(...)` across
/// the setup flow. The system title rendered against the green container
/// background was producing a heavy, inconsistent chrome; this matches the
/// sage canvas, keeps the leading control the same shape and weight on every
/// screen, and gives titles room to breathe.
///
/// Pair with `.toolbar(.hidden, for: .navigationBar)` on the host screen to
/// suppress the system chrome. Edge-swipe-back continues to work on watchOS.
struct NavHeader: View {
    enum Leading {
        case back
        case close
        case none
    }

    let title: String
    var leading: Leading = .back
    var leadingAction: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Text(title)
                .font(.titleSmall)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .padding(.horizontal, 36)

            HStack {
                leadingControl
                Spacer()
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 28)
        .padding(.horizontal, 4)
        .padding(.top, 2)
    }

    @ViewBuilder
    private var leadingControl: some View {
        switch leading {
        case .none:
            Color.clear.frame(width: 26, height: 26)
        case .back, .close:
            Button {
                if let leadingAction {
                    leadingAction()
                } else {
                    dismiss()
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.92))
                        .overlay(
                            Circle().stroke(Theme.textPrimary.opacity(0.06), lineWidth: 1)
                        )
                        .frame(width: 26, height: 26)
                    Image(systemName: leading == .back ? "chevron.backward" : "xmark")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(Theme.fairway)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(leading == .back ? "Back" : "Close")
        }
    }
}
