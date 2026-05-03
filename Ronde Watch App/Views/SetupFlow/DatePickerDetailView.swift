import SwiftUI

/// Detail screen for editing the round date — pushed from the `DateRow` in
/// `ParSetupView`. The native `DatePicker` collapses badly at watch width
/// when inlined; given the full screen it lays out cleanly.
struct DatePickerDetailView: View {
    @Binding var date: Date
    var title: String = "Date"
    var range: PartialRangeThrough<Date> = ...Date.now

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 6) {
            DatePicker(
                "",
                selection: $date,
                in: range,
                displayedComponents: .date
            )
            .labelsHidden()
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            PrimaryButton(title: "Done", icon: "checkmark") {
                dismiss()
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .fairwayBackground()
        .fairwayContainerBackground()
        .navigationTitle(title)
    }
}
