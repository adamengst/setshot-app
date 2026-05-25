import SwiftUI

struct ResultsView: View {
    let diff: DiffResult
    let before: StoredSnapshot
    let after: StoredSnapshot
    @Binding var appState: AppState
    @EnvironmentObject var appModel: AppModel
    @State private var showNoise = false
    @State private var isRechecking = false
    @State private var submittedIDs: Set<UUID> = []
    @State private var isSubmittingAll = false
    @State private var submitAllProgress = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                recognisedSection
                unrecognisedSection
                if !diff.noise.isEmpty {
                    noiseSection
                }
            }
            .padding(32)
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Back to Library") { appState = .library }
            }
            ToolbarItem(placement: .primaryAction) {
                if isRechecking {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Recheck") { recheck() }
                        .help("Re-fetch the knowledge base and re-run the diff on the same snapshot pair")
                }
            }
        }
        .frame(minWidth: 600, minHeight: 400)
    }

    private func recheck() {
        isRechecking = true
        Task {
            await appModel.refreshKB()
            if let newDiff = try? await appModel.diff(before: before, after: after) {
                appState = .results(newDiff, before: before, after: after)
            }
            isRechecking = false
        }
    }

    private var recognisedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Recognised Changes", count: diff.recognised.count)
            if diff.recognised.isEmpty {
                Text("No recognised changes.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(diff.recognised, id: \.diff.id) { item in
                    RecognisedRow(entry: item.entry, diff: item.diff)
                }
            }
        }
    }

    private var unrecognisedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                SectionHeader("Unrecognised Changes", count: diff.unrecognised.count)
                Spacer()
                submitAllButton
            }
            if diff.unrecognised.isEmpty {
                Text("All changes were identified.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(diff.unrecognised) { line in
                    UnrecognisedRow(
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
        let unsubmitted = diff.unrecognised.filter { !submittedIDs.contains($0.id) }
        if !unsubmitted.isEmpty {
            if isSubmittingAll {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text("Submitting \(submitAllProgress) / \(unsubmitted.count)")
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
        submitAllProgress = 0
        Task {
            for item in items {
                try? await SubmissionService.shared.submit(item)
                submittedIDs.insert(item.id)
                submitAllProgress += 1
            }
            isSubmittingAll = false
        }
    }

    private var noiseSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                showNoise.toggle()
            } label: {
                Label(
                    "Suppressed Noise (\(diff.noise.count))",
                    systemImage: showNoise ? "chevron.down" : "chevron.right"
                )
                .font(.headline)
            }
            .buttonStyle(.plain)

            if showNoise {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(diff.noise, id: \.diff.id) { item in
                        NoiseRow(entry: item.entry, diff: item.diff)
                    }
                }
            }
        }
    }
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

private struct RecognisedRow: View {
    let entry: KBEntry
    let diff: DiffLine

    var body: some View {
        let settingsURL = validatedSettingsURL(entry.settingsURL)

        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.description)
                        .fontWeight(.medium)
                    if let location = entry.uiLocation {
                        Text(location)
                            .font(.caption)
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
            HStack(alignment: .firstTextBaseline) {
                Text(diff.rawLine)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.tertiary)
                Spacer()
                HStack(spacing: 4) {
                    Text(diff.beforeValue.isEmpty ? "(none)" : diff.beforeValue)
                        .foregroundStyle(.red.opacity(0.8))
                    Text("→")
                        .foregroundStyle(.secondary)
                    Text(diff.afterValue.isEmpty ? "(none)" : diff.afterValue)
                        .foregroundStyle(.green.opacity(0.9))
                }
                .font(.system(.caption, design: .monospaced))
            }
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

private struct UnrecognisedRow: View {
    let diff: DiffLine
    let isSubmitted: Bool
    let onMarkSubmitted: () -> Void
    @State private var showSheet = false

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(diff.rawLine)
                    .font(.system(.body, design: .monospaced))
                HStack(spacing: 4) {
                    Text(diff.beforeValue.isEmpty ? "(none)" : diff.beforeValue)
                        .foregroundStyle(.red.opacity(0.8))
                    Text("→")
                        .foregroundStyle(.secondary)
                    Text(diff.afterValue.isEmpty ? "(none)" : diff.afterValue)
                        .foregroundStyle(.green.opacity(0.9))
                }
                .font(.system(.caption, design: .monospaced))
            }
            Spacer()
            if isSubmitted {
                Label("Submitted", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
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

private struct NoiseRow: View {
    let entry: KBEntry
    let diff: DiffLine

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(diff.rawLine)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                if let reason = entry.noiseReason {
                    Text(reason)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}
