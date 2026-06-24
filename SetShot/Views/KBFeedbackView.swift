import SwiftUI

enum KBFeedbackIssue: String, CaseIterable {
    case noOrIncorrectIcon       = "no_or_incorrect_icon"
    case descriptionNeedsWork    = "description_needs_improvement"
    case pathIsWrong             = "path_is_wrong"
    case valuesNotReadable       = "values_not_human_readable"

    var label: String {
        switch self {
        case .noOrIncorrectIcon:    return "No or incorrect icon"
        case .descriptionNeedsWork: return "Description needs improvement"
        case .pathIsWrong:          return "Path is wrong"
        case .valuesNotReadable:    return "Values aren't human-readable"
        }
    }
}

struct KBFeedbackView: View {
    let entry: KBEntry
    let diff: DiffLine
    @Binding var isPresented: Bool
    let onSubmitted: () -> Void

    @State private var selectedIssues: Set<KBFeedbackIssue> = []
    @State private var notes: String = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    private var canSubmit: Bool {
        !selectedIssues.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Submit Feedback")
                .font(.headline)
            Text("This data will be sent to the developer to help improve SetShot's knowledge base. Submitted data is transmitted securely and stored privately. No personally identifying information is collected or stored.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 8) {
                GridRow {
                    Text("Setting").foregroundStyle(.secondary)
                    Text(entry.description ?? entry.key)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if let location = entry.uiLocation {
                    GridRow {
                        Text("Location").foregroundStyle(.secondary)
                        Text(location)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                GridRow {
                    Text("macOS").foregroundStyle(.secondary)
                    Text(diff.macOSVersion)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.08))
            .cornerRadius(8)
            .textSelection(.enabled)

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text("What needs improvement? (select at least one)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(KBFeedbackIssue.allCases, id: \.rawValue) { issue in
                        issueToggle(issue)
                    }
                }

                TextField("Additional details or suggestions…", text: $notes, axis: .vertical)
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
                .disabled(isSubmitting || !canSubmit)
            }
        }
        .padding(28)
        .frame(width: 440)
    }

    private func issueToggle(_ issue: KBFeedbackIssue) -> some View {
        Button {
            if selectedIssues.contains(issue) {
                selectedIssues.remove(issue)
            } else {
                selectedIssues.insert(issue)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: selectedIssues.contains(issue) ? "checkmark.square.fill" : "square")
                    .foregroundStyle(selectedIssues.contains(issue) ? Color.accentColor : .secondary)
                Text(issue.label)
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
            try await SubmissionService.shared.submitKBFeedback(
                entry: entry,
                diff: diff,
                issues: Array(selectedIssues),
                notes: notes
            )
            onSubmitted()
            isPresented = false
        } catch {
            errorMessage = "Submission failed. Please try again."
        }
        isSubmitting = false
    }
}
