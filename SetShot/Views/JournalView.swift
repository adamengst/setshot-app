import SwiftUI
import AppKit

struct JournalView: View {
    var openSettings: () -> Void = {}
    @EnvironmentObject var appModel: AppModel
    @AppStorage("OldestFirst") private var oldestFirst = false
    @State private var searchQuery = ""
    @State private var showingClearConfirm = false
    @FocusState private var searchFocused: Bool

    /// The journal less any settings ignored in Settings. Entries are hidden, not
    /// deleted, so they come back if the switch is turned off. Settings is another tab
    /// of this window, so the view is rebuilt — and this re-read — on the way back.
    private var journal: [JournalEntry] {
        let ignored = IgnoredChanges.current()
        guard !ignored.isEmpty else { return appModel.journal }
        return appModel.journal.filter { !ignored.covers(domain: $0.domain, key: $0.key) }
    }

    private func filteredEntries(_ journal: [JournalEntry]) -> [JournalEntry] {
        guard !searchQuery.isEmpty else { return journal }
        let q = searchQuery.lowercased()
        return journal.filter {
            let kbEntry = appModel.kb.entry(forDomain: $0.domain, key: $0.key)
            let valueMap = kbEntry?.valueMap
            let oldFormatted = formatValue($0.oldValue, key: $0.key, valueMap: valueMap,
                                           valueType: kbEntry?.valueType, counterpart: $0.newValue)
            let newFormatted = formatValue($0.newValue, key: $0.key, valueMap: valueMap,
                                           valueType: kbEntry?.valueType, counterpart: $0.oldValue)
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

    private func sections(_ entries: [JournalEntry]) -> [JournalSection] {
        let grouped = Dictionary(grouping: entries) { $0.afterSnapshotId }
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
        // Each of these walks the whole journal, so they are worked out once per pass
        // rather than read as computed properties at every place that needs them.
        let journal = self.journal
        let sections = sections(filteredEntries(journal))
        VStack(spacing: 0) {
            searchField(hasEntries: !journal.isEmpty)
            Divider()
            if journal.isEmpty {
                emptyState
            } else if sections.isEmpty {
                noResults
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        // Headers and rows are direct children of the stack, so only the
                        // ones near the visible area are built. With each section in a
                        // VStack of its own, the stack had to build and measure every row
                        // of a section before placing it, and one comparison can record
                        // hundreds of changes.
                        LazyVStack(alignment: .leading, spacing: 0) {
                            Color.clear.frame(height: 0).id("journal-top")
                            ForEach(sections, id: \.snapshotId) { section in
                                sectionHeader(section)
                                    .padding(.top, section.snapshotId == sections.first?.snapshotId ? 0 : 24)
                                ForEach(section.entries) { entry in
                                    journalRow(entry)
                                        .padding(.top, 8)
                                }
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

    private func searchField(hasEntries: Bool) -> some View {
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
            if hasEntries {
                // Inline, SwiftUI draws a Menu's indicator as a filled badge in the
                // accent colour whatever the menu or button style — borderless only
                // removes it by removing the frame too. The comparison window's copy
                // looks plain because it sits in a toolbar, not because of any modifier.
                // So the indicator is suppressed and the chevron drawn in the label,
                // which keeps it the same colour as the text.
                Menu {
                    Button("HTML…") { exportJournal(.html) }
                    Button("Markdown…") { exportJournal(.markdown) }
                } label: {
                    // The chevron has to live inside the text run. Given a label built
                    // from separate views, SwiftUI hands the image and the title to an
                    // NSButton, which draws the image on the leading side whatever order
                    // they were written in.
                    Text("Export\u{2005}\u{2005}")   // two four-per-em spaces, ~6pt total
                        + Text(Image(systemName: "chevron.down"))
                            .font(.system(size: 9, weight: .semibold))
                }
                .menuIndicator(.hidden)
                .fixedSize()
                Button("Clear All") {
                    showingClearConfirm = true
                }
                .foregroundStyle(.red)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        // Escape clears the field, the same as the x button beside it. Guarded so an
        // empty field does not swallow Escape from anything else that wants it.
        .onExitCommand { if !searchQuery.isEmpty { searchQuery = "" } }
        .confirmationDialog("Clear the entire journal?", isPresented: $showingClearConfirm, titleVisibility: .visible) {
            Button("Clear Journal", role: .destructive) {
                Task { await appModel.clearJournal() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete all journal entries. This cannot be undone.")
        }
    }

    private func exportJournal(_ format: ExportFormat) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [format.contentType]
        panel.nameFieldStringValue = "SetShot Journal — \(StoredSnapshot.exportComputerName) — "
            + "\(StoredSnapshot.exportDateStamp).\(format.fileExtension)"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let text: String
        switch format {
        case .html:
            text = JournalHTMLExporter.export(journal: journal, oldestFirst: oldestFirst)
        case .markdown:
            text = MarkdownExporter.export(journal: journal, oldestFirst: oldestFirst)
        }
        try? text.data(using: .utf8)?.write(to: url, options: .atomic)
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

    private func journalRow(_ entry: JournalEntry) -> some View {
        JournalRow(entry: entry, kb: appModel.kb) { note in
            Task { await appModel.setJournalNote(entryID: entry.id, note: note) }
        }
        .contextMenu {
            Button("Delete Entry", role: .destructive) {
                Task { await appModel.deleteJournalEntry(entry) }
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
        let description = rowDescription(domain: entry.domain, key: entry.key, kb: kb)
            ?? entry.entryDescription
        let location = kbEntry?.uiLocation ?? entry.uiLocation
        let settingsURL = validatedSettingsURL(kbEntry?.settingsURL ?? entry.settingsURL)
        let valueMap = kbEntry?.valueMap
        let oldFormatted = formatValue(entry.oldValue, key: entry.key, valueMap: valueMap,
                                       valueType: kbEntry?.valueType, counterpart: entry.newValue)
        let newFormatted = formatValue(entry.newValue, key: entry.key, valueMap: valueMap,
                                       valueType: kbEntry?.valueType, counterpart: entry.oldValue)

        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 12) {
                SettingsPaneIcon(settingsURL: kbEntry?.settingsURL ?? entry.settingsURL,
                                 domain: entry.domain,
                                 iconBundleID: handlerIconBundleID(key: entry.key,
                                                                   before: entry.oldValue,
                                                                   after: entry.newValue)
                                     ?? kbEntry?.iconBundleID)
                    .padding(.top, 2)
                HStack(alignment: .top, spacing: 8) {
                    recognizedRowText(
                        description: description,
                        location: location,
                        old: oldFormatted,
                        new: newFormatted,
                        domain: entry.domain
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
