import SwiftUI

struct ResultsView: View {
    let diff: DiffResult
    @Binding var appState: AppState
    @State private var showNoise = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                recognisedSection
                unrecognisedSection
                noiseSection
            }
            .padding(32)
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Start Over") { appState = .ready }
            }
        }
        .frame(minWidth: 600, minHeight: 400)
    }

    private var recognisedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recognised Changes")
                .font(.headline)
            if diff.recognised.isEmpty {
                Text("None").foregroundStyle(.secondary)
            } else {
                ForEach(diff.recognised, id: \.diff.id) { item in
                    RecognisedRow(entry: item.entry, diff: item.diff)
                }
            }
        }
    }

    private var unrecognisedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Unrecognised Changes")
                .font(.headline)
            if diff.unrecognised.isEmpty {
                Text("None").foregroundStyle(.secondary)
            } else {
                ForEach(diff.unrecognised) { line in
                    UnrecognisedRow(diff: line)
                }
            }
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
                ForEach(diff.noise, id: \.diff.id) { item in
                    Text(item.diff.rawLine)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct RecognisedRow: View {
    let entry: KBEntry
    let diff: DiffLine

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.description)
                .fontWeight(.medium)
            if let location = entry.uiLocation {
                Text(location)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text("\(diff.beforeValue) → \(diff.afterValue)")
                    .font(.system(.caption, design: .monospaced))
                Spacer()
                if validatedSettingsURL(entry.settingsURL) != nil {
                    Button("Open in Settings") {
                        if let url = validatedSettingsURL(entry.settingsURL) {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .controlSize(.small)
                }
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
    @State private var submitted = false
    @State private var showSheet = false

    var body: some View {
        HStack {
            Text(diff.rawLine)
                .font(.system(.body, design: .monospaced))
            Spacer()
            if submitted {
                Label("Submitted", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .controlSize(.small)
            } else {
                Button("Submit") { showSheet = true }
                    .controlSize(.small)
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.08))
        .cornerRadius(8)
        .sheet(isPresented: $showSheet) {
            SubmitView(diff: diff, isPresented: $showSheet, onSubmitted: {
                submitted = true
            })
        }
    }
}
