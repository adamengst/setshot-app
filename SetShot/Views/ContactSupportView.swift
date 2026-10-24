import SwiftUI

/// Help → Contact Support. Sends a question, bug report or suggestion to the
/// developer, with an optional address for a reply.
struct ContactSupportView: View {
    /// Closes the window and discards the form, after Cancel or a successful send.
    /// Closing with the window's close button instead keeps what was typed for the
    /// next Contact Support.
    let onDone: () -> Void

    @State private var kind: SupportKind = .question
    @State private var message = ""
    @State private var name = ""
    @State private var email = ""
    @State private var includeDiagnostics = true
    @State private var diagnostics: SupportDiagnostics?
    @State private var isSending = false
    @State private var errorMessage: String?
    /// Whether the last attempt reached the network and failed, as opposed to being
    /// stopped by a check here, which Try Again would not get past.
    @State private var sendFailed = false

    private var canSend: Bool {
        !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isSending
            && (!includeDiagnostics || diagnostics != nil)
    }

    var body: some View {
        form
        .padding(28)
        .frame(width: 480)
        .task {
            diagnostics = await Task.detached(priority: .userInitiated) {
                SupportDiagnostics.current()
            }.value
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Ask a question, report a problem, or suggest an improvement. Your message goes to SetShot’s developer over a secure connection and is stored privately.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            Picker("Type", selection: $kind) {
                ForEach(SupportKind.allCases, id: \.self) { kind in
                    Text(kind.label).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            TextField(placeholder, text: $message, axis: .vertical)
                .lineLimit(8, reservesSpace: true)
                .textFieldStyle(.plain)
                .padding(10)
                .background(Color.secondary.opacity(0.08))
                .cornerRadius(6)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    TextField("Name (optional)", text: $name)
                    TextField("Email address (optional)", text: $email)
                }
                .textFieldStyle(.roundedBorder)
                Text("Include an address if you’d like a reply. Your name and address are used only to answer this message.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 8) {
                Toggle("Include information about this Mac", isOn: $includeDiagnostics)
                if includeDiagnostics {
                    diagnosticsGrid
                }
            }

            if let error = errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button("Cancel") { onDone() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(isSending)
                Spacer()
                if isSending {
                    ProgressView().controlSize(.small)
                }
                Button(sendFailed ? "Try Again" : "Send") {
                    Task { await send() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSend)
            }
        }
    }

    private var placeholder: String {
        switch kind {
        case .bug:        return "What happened, and what did you expect instead?"
        case .question:   return "What would you like to know?"
        case .suggestion: return "What would make SetShot more useful?"
        }
    }

    @ViewBuilder
    private var diagnosticsGrid: some View {
        Group {
            if let diagnostics {
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 6) {
                    ForEach(diagnostics.rows, id: \.label) { row in
                        GridRow {
                            Text(row.label).foregroundStyle(.secondary)
                            Text(row.value)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            } else {
                ProgressView().controlSize(.small)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .font(.callout)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08))
        .cornerRadius(8)
        .textSelection(.enabled)
    }

    private func send() async {
        if let problem = SubmissionValidator.problem(withSupportMessage: message)
            ?? SubmissionValidator.problem(withName: name)
            ?? SubmissionValidator.problem(withEmail: email) {
            errorMessage = problem
            sendFailed = false
            return
        }
        let request = SupportRequest(kind: kind, message: message, name: name, email: email,
                                     diagnostics: includeDiagnostics ? diagnostics : nil)
        isSending = true
        errorMessage = nil
        do {
            try await SubmissionService.shared.submitSupportRequest(request)
            onDone()
            return
        } catch {
            sendFailed = true
            errorMessage = (error as? SubmissionError)?.errorDescription
                ?? "Your message couldn’t be sent. Check your Internet connection and try again."
        }
        isSending = false
    }
}
