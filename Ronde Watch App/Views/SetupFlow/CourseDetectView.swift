import SwiftUI

/// Placeholder for Session 5: Auto-detect course via GPS + API.
/// Will show a loading spinner while detecting location, then either:
/// - Show matched course for confirmation
/// - Fall through to manual setup on timeout/failure
struct CourseDetectView: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Finding your course...")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
