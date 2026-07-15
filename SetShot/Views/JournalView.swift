import SwiftUI
import AppKit

struct JournalView: View {
    var openSettings: () -> Void = {}
    @EnvironmentObject var appModel: AppModel
    @AppStorage("OldestFirst") private var oldestFirst = false
    @State private var searchQuery = ""
    @State private var showingClearConfirm = false
    @FocusState private var searchFocused: Bool

    private var filteredEntries: [JournalEntry] {
        guard !searchQuery.isEmpty else { return appModel.journal }
        let q = searchQuery.lowercased()
        return appModel.journal.filter {
            let valueMap = appModel.kb.entry(forDomain: $0.domain, key: $0.key)?.valueMap
            let oldFormatted = formatValue($0.oldValue, key: $0.key, valueMap: valueMap)
            let newFormatted = formatValue($0.newValue, key: $0.key, valueMap: valueMap)
            return $0.entryDescription.lowercased().contains(q) ||
                $0.key.lowercased().contains(q) ||
                ($0.uiLocation?.lowercased().contains(q) ?? false) ||
                $0.oldValue.lowercased().contains(q) ||
                $0.newValue.lowercased().contains(q) ||
                oldFormatted.lowercased().contains(q) ||
                newFormatted.lowercased().contains(q) ||
                ($0.userNote?.lowercased().contains(q) ?? false)
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
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 24) {
                            Color.clear.frame(height: 0).id("journal-top")
                            ForEach(sections, id: \.snapshotId) { section in
                                sectionBlock(section)
                            }
                        }
                        .padding(20)
                        .textSelection(.enabled)
                    }
                    .onChange(of: searchQuery) { _ in
                        proxy.scrollTo("journal-top", anchor: .top)
                    }
                }
            }
        }
        .overlay {
            Button("") { searchFocused = true }
                .keyboardShortcut("f", modifiers: .command)
                .opacity(0)
            Button("") { openSettings() }
                .keyboardShortcut(",", modifiers: .command)
                .opacity(0)
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search journal", text: $searchQuery)
                .textFieldStyle(.plain)
                .focused($searchFocused)
            if !searchQuery.isEmpty {
                Button { searchQuery = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            if !appModel.journal.isEmpty {
                Button("Export HTML…") { exportJournal() }
                Button("Clear All") {
                    showingClearConfirm = true
                }
                .foregroundStyle(.red)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .confirmationDialog("Clear the entire journal?", isPresented: $showingClearConfirm, titleVisibility: .visible) {
            Button("Clear Journal", role: .destructive) {
                Task { await appModel.clearJournal() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete all journal entries. This cannot be undone.")
        }
    }

    private func exportJournal() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.html]
        panel.nameFieldStringValue = "SetShot Journal.html"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let html = JournalHTMLExporter.export(journal: appModel.journal, oldestFirst: oldestFirst)
        try? html.data(using: .utf8)?.write(to: url, options: .atomic)
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
                JournalRow(entry: entry, kb: appModel.kb) { note in
                    Task { await appModel.setJournalNote(entryID: entry.id, note: note) }
                }
                .contextMenu {
                    Button("Delete Entry", role: .destructive) {
                        Task { await appModel.deleteJournalEntry(entry) }
                    }
                }
            }
        }
    }

    private func sectionHeader(_ section: JournalSection) -> some View {
        let count = section.entries.count
        let isFromBaseline = section.entries.allSatisfy(\.fromBaseline)
        let label = "\(count) change\(count == 1 ? "" : "s")\(isFromBaseline ? " from baseline" : "")"
        return HStack {
            Text(section.snapshotDate, format: .dateTime.weekday(.wide).month(.wide).day().year().hour().minute())
                .font(.headline)
            Spacer()
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .textSelection(.disabled)
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
    let onNoteChanged: (String?) -> Void

    @State private var feedbackSubmitted = false
    @State private var showFeedback = false
    @State private var noteText: String = ""
    @FocusState private var noteFocused: Bool

    init(entry: JournalEntry, kb: KnowledgeBase, onNoteChanged: @escaping (String?) -> Void) {
        self.entry = entry
        self.kb = kb
        self.onNoteChanged = onNoteChanged
    }

    private static let macOSVersion: String = {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }()

    private func makeDiffLine() -> DiffLine {
        DiffLine(domain: entry.domain, key: entry.key, source: "defaults",
                 beforeValue: entry.oldValue, afterValue: entry.newValue,
                 macOSVersion: Self.macOSVersion,
                 rawLine: "\(entry.domain) :: \(entry.key)")
    }

    var body: some View {
        let kbEntry = kb.entry(forDomain: entry.domain, key: entry.key)
        let description = kbEntry?.description ?? entry.entryDescription
        let location = kbEntry?.uiLocation ?? entry.uiLocation
        let settingsURL = validatedSettingsURL(kbEntry?.settingsURL ?? entry.settingsURL)
        let valueMap = kbEntry?.valueMap
        let oldFormatted = formatValue(entry.oldValue, key: entry.key, valueMap: valueMap)
        let newFormatted = formatValue(entry.newValue, key: entry.key, valueMap: valueMap)

        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 12) {
                SettingsPaneIcon(settingsURL: kbEntry?.settingsURL ?? entry.settingsURL, domain: entry.domain, iconBundleID: kbEntry?.iconBundleID)
                    .padding(.top, 2)
                HStack(alignment: .top, spacing: 8) {
                    recognizedRowText(
                        description: description,
                        location: location,
                        old: oldFormatted,
                        new: newFormatted
                    )
                    Spacer()
                    VStack(alignment: .center, spacing: 0) {
                        if let url = settingsURL {
                            Button("Open in Settings") {
                                NSWorkspace.shared.open(url)
                            }
                            .controlSize(.small)
                        }
                        Spacer(minLength: 8)
                        if let kbEntry {
                            if feedbackSubmitted {
                                Label("Feedback Sent", systemImage: "checkmark.circle.fill")
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                            } else {
                                Button("Submit Feedback") { showFeedback = true }
                                    .controlSize(.small)
                                    .sheet(isPresented: $showFeedback) {
                                        KBFeedbackView(entry: kbEntry, diff: makeDiffLine(),
                                                       isPresented: $showFeedback) {
                                            feedbackSubmitted = true
                                        }
                                    }
                            }
                        }
                    }
                }
            }

            // Note field — indented to align with text content (icon 32pt + spacing 12pt)
            HStack(spacing: 0) {
                Spacer().frame(width: 44)
                TextField("Add note…", text: $noteText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.callout)
                    .foregroundStyle(noteText.isEmpty ? Color.secondary.opacity(0.5) : Color.red)
                    .focused($noteFocused)
                    .onAppear { noteText = entry.userNote ?? "" }
                    .onChange(of: noteFocused) { isFocused in
                        guard !isFocused else { return }
                        let trimmed = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
                        let newNote: String? = trimmed.isEmpty ? nil : trimmed
                        if newNote != entry.userNote { onNoteChanged(newNote) }
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
