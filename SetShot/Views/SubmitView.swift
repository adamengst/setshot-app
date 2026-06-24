import SwiftUI

struct SubmitView: View {
    let diff: DiffLine
    @Binding var isPresented: Bool
    let onSubmitted: () -> Void

    @State private var feedbackCategory: FeedbackCategory? = nil
    @State private var feedbackNotes: String = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Submit Unknown Setting")
                .font(.headline)
            Text("This data will be sent to the developer to help identify similar changes in the future. Submitted data is transmitted securely and stored privately. No personally identifying information is collected or stored.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 8) {
                GridRow {
                    Text("Domain").foregroundStyle(.secondary)
                    Text(diff.domain).font(.system(.body, design: .monospaced))
                }
                GridRow {
                    Text("Key").foregroundStyle(.secondary)
                    Text(diff.key).font(.system(.body, design: .monospaced))
                }
                GridRow {
                    Text("Source").foregroundStyle(.secondary)
                    Text(diff.source).font(.system(.body, design: .monospaced))
                }
                GridRow {
                    Text("Before").foregroundStyle(.secondary)
                    Text(diff.beforeValue).font(.system(.body, design: .monospaced))
                }
                GridRow {
                    Text("After").foregroundStyle(.secondary)
                    Text(diff.afterValue).font(.system(.body, design: .monospaced))
                }
                GridRow {
                    Text("macOS").foregroundStyle(.secondary)
                    Text(diff.macOSVersion).font(.system(.body, design: .monospaced))
                }
            }
            .padding(12)
            .background(Color.secondary.opacity(0.08))
            .cornerRadius(8)
            .textSelection(.enabled)

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text("Feedback (optional)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 6) {
                    feedbackRadio(.expectedChange, label: "Expected settings change")
                    feedbackRadio(.likelyNoise,    label: "Likely macOS noise")
                }

                TextField("Additional context…", text: $feedbackNotes, axis: .vertical)
                    .lineLimit(3, reservesSpace: true)
                    .textFieldStyle(.plain)
                    .padding(10)
                    .background(Color.secondary.opacity(0.08))
                    .cornerRadius(6)
            }

            if let error = errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            HStack {
                Button(errorMessage != nil ? "Dismiss" : "Cancel") { isPresented = false }
                    .disabled(isSubmitting)
                Spacer()
                if isSubmitting {
                    ProgressView().controlSize(.small)
                }
                Button(errorMessage != nil ? "Retry" : "Submit") {
                    Task { await submit() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSubmitting)
            }
        }
        .padding(28)
        .frame(width: 440)
    }

    private func feedbackRadio(_ category: FeedbackCategory, label: String) -> some View {
        Button {
            feedbackCategory = feedbackCategory == category ? nil : category
        } label: {
            HStack(spacing: 6) {
                Image(systemName: feedbackCategory == category ? "circle.inset.filled" : "circle")
                    .foregroundStyle(feedbackCategory == category ? Color.accentColor : .secondary)
                Text(label)
                    .foregroundStyle(.primary)
            }
        }
        .buttonStyle(.plain)
        .focusable(false)
    }

    private func submit() async {
        isSubmitting = true
        errorMessage = nil
        do {
            let feedback = UserFeedback(category: feedbackCategory, notes: feedbackNotes)
            try await SubmissionService.shared.submit(diff, feedback: feedback)
            onSubmitted()
            isPresented = false
        } catch {
            errorMessage = "Submission failed. Please try again."
        }
        isSubmitting = false
    }
}
