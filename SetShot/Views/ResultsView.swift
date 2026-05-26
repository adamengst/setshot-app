import SwiftUI

struct ResultsView: View {
    let diff: DiffResult
    let before: StoredSnapshot
    let after: StoredSnapshot
    @Binding var appState: AppState
    @EnvironmentObject var appModel: AppModel
    @State private var submittedIDs: Set<UUID> = []
    @State private var isSubmittingAll = false
    @State private var submitError: String? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                recognizedSection
                unrecognizedSection
            }
            .padding(32)
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Back to Snapshots") { appState = .library }
            }
        }
        .alert("Submission Failed", isPresented: Binding(
            get: { submitError != nil },
            set: { if !$0 { submitError = nil } }
        )) {
            Button("OK") { submitError = nil }
        } message: {
            Text(submitError ?? "")
        }
        .frame(minWidth: 600, minHeight: 400)
    }

    private var recognizedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Recognized Changes", count: diff.recognized.count)
            if diff.recognized.isEmpty {
                Text("No recognized changes.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(diff.recognized, id: \.diff.id) { item in
                    RecognizedRow(entry: item.entry, diff: item.diff)
                }
            }
        }
    }

    private var unrecognizedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                SectionHeader("Unrecognized Changes", count: diff.unrecognized.count)
                Spacer()
                submitAllButton
            }
            if diff.unrecognized.isEmpty {
                Text("All changes were identified.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(diff.unrecognized) { line in
                    UnrecognizedRow(
                        diff: line,
                        isSubmitted: submittedIDs.contains(line.id),
                        onMarkSubmitted: { submittedIDs.insert(line.id) }
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var submitAllButton: some View {
        let unsubmitted = diff.unrecognized.filter { !submittedIDs.contains($0.id) }
        if !unsubmitted.isEmpty {
            if isSubmittingAll {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text("Submitting…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Button("Submit All (\(unsubmitted.count))") {
                    submitAll(unsubmitted)
                }
                .controlSize(.small)
            }
        }
    }

    private func submitAll(_ items: [DiffLine]) {
        isSubmittingAll = true
        submitError = nil
        Task {
            do {
                try await SubmissionService.shared.submitBatch(items)
                for item in items { submittedIDs.insert(item.id) }
            } catch {
                submitError = error.localizedDescription
            }
            isSubmittingAll = false
        }
    }

}

func formatValue(_ raw: String, key: String = "", valueMap: [String: String]? = nil) -> String {
    if let map = valueMap {
        // Normalize True/False → 1/0 for value_map lookup since FLATTEN_PY
        // converts integer 0/1 to booleans, but value_map keys use integers.
        let lookupKey = raw == "True" ? "1" : raw == "False" ? "0" : raw
        if let label = map[lookupKey] { return label }
    }
    switch raw.lowercased() {
    case "true", "yes", "1": return "On"
    case "false", "no", "0": return "Off"
    default: break
    }
    if raw.hasPrefix("/"), let url = URL(string: "file://\(raw)") {
        return url.deletingPathExtension().lastPathComponent
    }
    if key.localizedCaseInsensitiveContains("volume"), let f = Double(raw) {
        return "\(Int((f * 100).rounded()))%"
    }
    return raw
}

private struct SectionHeader: View {
    let title: String
    let count: Int

    init(_ title: String, count: Int) {
        self.title = title
        self.count = count
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title).font(.headline)
            Text("(\(count))").font(.subheadline).foregroundStyle(.secondary)
        }
    }
}

private struct RecognizedRow: View {
    let entry: KBEntry
    let diff: DiffLine

    var body: some View {
        let settingsURL = validatedSettingsURL(entry.settingsURL)

        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.description)
                        .fontWeight(.medium)
                    if let location = entry.uiLocation {
                        Text(location)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if let url = settingsURL {
                    Button("Open in Settings") {
                        NSWorkspace.shared.open(url)
                    }
                    .controlSize(.small)
                }
            }
            HStack(spacing: 6) {
                Text(diff.beforeValue.isEmpty ? "(none)" : formatValue(diff.beforeValue, key: diff.key, valueMap: entry.valueMap))
                    .foregroundStyle(.orange)
                Text("→")
                    .foregroundStyle(.secondary)
                Text(diff.afterValue.isEmpty ? "(none)" : formatValue(diff.afterValue, key: diff.key, valueMap: entry.valueMap))
                    .foregroundStyle(.blue)
            }
            .font(.system(.callout, design: .monospaced))
        }
        .padding(12)
        .background(Color.secondary.opacity(0.08))
        .cornerRadius(8)
    }

    private func validatedSettingsURL(_ raw: String?) -> URL? {
        guard let raw,
              raw.hasPrefix("x-apple.systempreferences:"),
              !raw.contains("://"),
              !raw.contains(" ") else { return nil }
        return URL(string: raw)
    }
}

private struct UnrecognizedRow: View {
    let diff: DiffLine
    let isSubmitted: Bool
    let onMarkSubmitted: () -> Void
    @State private var showSheet = false

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(diff.rawLine)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    Text(diff.beforeValue.isEmpty ? "(none)" : formatValue(diff.beforeValue, key: diff.key))
                        .foregroundStyle(.orange)
                    Text("→")
                        .foregroundStyle(.secondary)
                    Text(diff.afterValue.isEmpty ? "(none)" : formatValue(diff.afterValue, key: diff.key))
                        .foregroundStyle(.blue)
                }
                .font(.system(.callout, design: .monospaced))
            }
            Spacer()
            if isSubmitted {
                Label("Submitted", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            } else {
                Button("Submit") { showSheet = true }
                    .controlSize(.small)
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.08))
        .cornerRadius(8)
        .sheet(isPresented: $showSheet) {
            SubmitView(diff: diff, isPresented: $showSheet, onSubmitted: onMarkSubmitted)
        }
    }
}

