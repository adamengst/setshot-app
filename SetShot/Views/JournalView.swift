import SwiftUI

struct JournalView: View {
    @EnvironmentObject var appModel: AppModel
    @AppStorage("OldestFirst") private var oldestFirst = false
    @State private var searchQuery = ""

    private var filteredEntries: [JournalEntry] {
        guard !searchQuery.isEmpty else { return appModel.journal }
        let q = searchQuery.lowercased()
        return appModel.journal.filter {
            $0.entryDescription.lowercased().contains(q) ||
            $0.key.lowercased().contains(q) ||
            ($0.uiLocation?.lowercased().contains(q) ?? false)
        }
    }

    private struct JournalSection {
        let snapshotId: String
        let snapshotDate: Date
        let snapshotName: String
        let entries: [JournalEntry]
    }

    private var sections: [JournalSection] {
        let grouped = Dictionary(grouping: filteredEntries) { $0.afterSnapshotId }
        return grouped.map { snapshotId, entries in
            JournalSection(
                snapshotId: snapshotId,
                snapshotDate: entries[0].afterSnapshotDate,
                snapshotName: entries[0].afterSnapshotName,
                entries: entries
            )
        }
        .sorted { oldestFirst ? $0.snapshotDate < $1.snapshotDate : $0.snapshotDate > $1.snapshotDate }
    }

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider()
            if appModel.journal.isEmpty {
                emptyState
            } else if sections.isEmpty {
                noResults
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        ForEach(sections, id: \.snapshotId) { section in
                            sectionBlock(section)
                        }
                    }
                    .padding(20)
                }
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search journal", text: $searchQuery)
                .textFieldStyle(.plain)
            if !searchQuery.isEmpty {
                Button { searchQuery = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("No journal entries yet.")
                .font(.headline)
            Text("Run a comparison to start recording recognized changes here.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var noResults: some View {
        Text("No results for \"\(searchQuery)\".")
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
    }

    private func sectionBlock(_ section: JournalSection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(section)
            ForEach(section.entries) { entry in
                JournalRow(entry: entry, kb: appModel.kb)
                    .contextMenu {
                        Button("Delete Entry", role: .destructive) {
                            Task { await appModel.deleteJournalEntry(entry) }
                        }
                    }
            }
        }
    }

    private func sectionHeader(_ section: JournalSection) -> some View {
        HStack {
            Text(section.snapshotDate, format: .dateTime.weekday(.wide).month(.wide).day().year().hour().minute())
                .font(.headline)
            Spacer()
            Text("\(section.entries.count) change\(section.entries.count == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .contextMenu {
            Button("Delete All from This Comparison", role: .destructive) {
                Task { await appModel.deleteJournalSection(afterSnapshotId: section.snapshotId) }
            }
        }
    }
}

private struct JournalRow: View {
    let entry: JournalEntry
    let kb: KnowledgeBase

    var body: some View {
        let kbEntry = kb.entry(forDomain: entry.domain, key: entry.key)
        let description = kbEntry?.description ?? entry.entryDescription
        let location = kbEntry?.uiLocation ?? entry.uiLocation
        let settingsURL = validatedSettingsURL(kbEntry?.settingsURL ?? entry.settingsURL)
        let valueMap = kbEntry?.valueMap
        let oldFormatted = formatValue(entry.oldValue, key: entry.key, valueMap: valueMap)
        let newFormatted = formatValue(entry.newValue, key: entry.key, valueMap: valueMap)

        HStack(alignment: .top, spacing: 12) {
            SettingsPaneIcon(settingsURL: kbEntry?.settingsURL ?? entry.settingsURL, domain: entry.domain, iconBundleID: kbEntry?.iconBundleID)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(description)
                            .fontWeight(.medium)
                        if let location {
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
                    Text(oldFormatted.isEmpty ? "(none)" : oldFormatted)
                        .foregroundStyle(.orange)
                    Text("→")
                        .foregroundStyle(.secondary)
                    Text(newFormatted.isEmpty ? "(none)" : newFormatted)
                        .foregroundStyle(.blue)
                }
                .font(.system(.callout, design: .monospaced))
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
