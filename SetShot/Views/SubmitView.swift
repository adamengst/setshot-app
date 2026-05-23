import SwiftUI

struct SubmitView: View {
    let diff: DiffLine
    @Binding var isPresented: Bool
    let onSubmitted: () -> Void

    @State private var isSubmitting = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Submit Unknown Setting")
                .font(.headline)
            Text("The following data will be sent to the SetShot knowledge base for review. No other information is collected.")
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

    private func submit() async {
        isSubmitting = true
        errorMessage = nil
        do {
            try await SubmissionService.shared.submit(diff)
            onSubmitted()
            isPresented = false
        } catch {
            errorMessage = "Submission failed. Please try again."
        }
        isSubmitting = false
    }
}
