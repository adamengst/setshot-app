import SwiftUI

struct SnapshotLibraryView: View {
    @EnvironmentObject var appModel: AppModel
    @Environment(\.openWindow) private var openWindow
    @State private var selectedIDs: Set<String> = []
    @State private var isTakingSnapshot = false
    @State private var isComparing = false
    @State private var errorMessage: String?
    @AppStorage("OldestFirst") private var oldestFirst = false
    private enum Tab { case snapshots, journal, settings, about }
    @State private var activeTab: Tab = UserDefaults.standard.bool(forKey: "HasSeenAbout") ? .snapshots : .about

    private let currentMacOSMajor = ProcessInfo.processInfo.operatingSystemVersion.majorVersion

    private var allSnapshots: [StoredSnapshot] {
        let base = appModel.baseSnapshots.filter { $0.baseMacOSMajor == currentMacOSMajor }
        return (appModel.snapshots + base)
            .sorted { oldestFirst ? $0.date < $1.date : $0.date > $1.date }
    }

    private var descriptionsBySnapshotID: [String: [String]] {
        var result: [String: [String]] = [:]
        for entry in appModel.journal {
            var list = result[entry.afterSnapshotId, default: []]
            if list.count < 3 {
                list.append(entry.entryDescription)
                result[entry.afterSnapshotId] = list
            }
        }
        return result
    }

    private var selectedSorted: [StoredSnapshot] {
        allSnapshots.filter { selectedIDs.contains($0.id) }
    }

    private var effectiveAfter:  StoredSnapshot? { selectedSorted.first }
    private var effectiveBefore: StoredSnapshot? { selectedSorted.last }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            switch activeTab {
            case .snapshots:
                if allSnapshots.isEmpty { emptyState } else { snapshotList }
            case .journal:
                JournalView(openSettings: { activeTab = .settings })
            case .settings:
                SettingsView()
            case .about:
                AboutView(openSettings: { activeTab = .settings })
            }
            if activeTab == .snapshots {
                Divider()
                footer
            }
        }
        .task {
            async let snapshots: Void = appModel.loadSnapshots()
            async let kb: Void = appModel.loadKB()
            _ = await (snapshots, kb)
            checkPendingComparison()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await appModel.loadSnapshots() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .setshotOpenComparison)) { notification in
            guard let info = notification.userInfo,
                  let beforeID = info["beforeID"] as? String,
                  let afterID = info["afterID"] as? String else { return }
            UserDefaults.standard.removeObject(forKey: "PendingComparisonBeforeID")
            UserDefaults.standard.removeObject(forKey: "PendingComparisonAfterID")
            openComparison(beforeID: beforeID, afterID: afterID)
        }
        .onChange(of: activeTab) { newTab in
            if newTab != .about {
                UserDefaults.standard.set(true, forKey: "HasSeenAbout")
            }
        }
        .overlay {
            Button("") { activeTab = .settings }
                .keyboardShortcut(",", modifiers: .command)
                .opacity(0)
        }
        .alert("Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Subviews

    private var header: some View {
        HStack {
            Spacer()
            Picker("", selection: $activeTab) {
                Text("Snapshots").tag(Tab.snapshots)
                Text("Journal").tag(Tab.journal)
                Text("Settings").tag(Tab.settings)
                Text("About").tag(Tab.about)
            }
            .pickerStyle(.segmented)
            .frame(width: 320)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("No snapshots yet.")
                .font(.headline)
            Text("Use Take Snapshot below before and after making changes to compare what shifted.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var snapshotList: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(allSnapshots) { snapshot in
                    SnapshotRow(
                        snapshot: snapshot,
                        isSelected: selectedIDs.contains(snapshot.id),
                        role: roleLabel(for: snapshot),
                        changeDescriptions: descriptionsBySnapshotID[snapshot.id] ?? []
                    ) { flags in
                        toggleSelection(snapshot, modifiers: flags)
                    } onRename: { newName in
                        Task { await appModel.renameSnapshot(snapshot, to: newName) }
                    } onDelete: {
                        deleteSnapshot(snapshot)
                    }
                    Divider()
                }
            }
        }
    }

    private func roleLabel(for snapshot: StoredSnapshot) -> String? {
        guard selectedSorted.count >= 2 else { return nil }
        if snapshot.id == effectiveAfter?.id  { return "After" }
        if snapshot.id == effectiveBefore?.id { return "Before" }
        return nil
    }

    private var footer: some View {
        HStack {
            if isTakingSnapshot {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Capturing…").foregroundStyle(.secondary).font(.callout)
                }
            } else {
                Button("Take Snapshot") { takeSnapshot() }
                    .buttonStyle(.borderedProminent)
            }
            Spacer()
            if selectedIDs.count < 2 {
                Text("Select snapshots to compare. Command-click explicitly selects Before; Shift-click selects After.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else if let before = effectiveBefore, let after = effectiveAfter, before.id != after.id {
                Text("\(before.displayName)  →  \(after.displayName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isComparing {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Comparing…").foregroundStyle(.secondary).font(.callout)
                }
            } else {
                Button("Compare") { compare() }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedSorted.count < 2)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - Actions

    private func toggleSelection(_ snapshot: StoredSnapshot, modifiers: NSEvent.ModifierFlags = []) {
        if modifiers.contains(.shift) {
            // Shift-click: force this snapshot as After, keep current Before
            var next: Set<String> = [snapshot.id]
            if let before = effectiveBefore, before.id != snapshot.id { next.insert(before.id) }
            selectedIDs = next
        } else if modifiers.contains(.command) {
            // Command-click: force this snapshot as Before, keep current After
            var next: Set<String> = [snapshot.id]
            if let after = effectiveAfter, after.id != snapshot.id { next.insert(after.id) }
            selectedIDs = next
        } else if selectedIDs.contains(snapshot.id) {
            selectedIDs.remove(snapshot.id)
        } else if selectedIDs.count < 2 {
            selectedIDs.insert(snapshot.id)
        } else {
            // Two already selected: deselect both and start fresh with the clicked one.
            // The next click will become After (if above) or Before (if below) naturally.
            selectedIDs = [snapshot.id]
        }
    }

    private func takeSnapshot() {
        isTakingSnapshot = true
        Task {
            do {
                _ = try await appModel.takeSnapshot()
            } catch {
                errorMessage = error.localizedDescription
            }
            isTakingSnapshot = false
        }
    }

    private func deleteSnapshot(_ snapshot: StoredSnapshot) {
        selectedIDs.remove(snapshot.id)
        Task { await appModel.deleteSnapshot(snapshot) }
    }

    private func compare() {
        guard let before = effectiveBefore, let after = effectiveAfter, before.id != after.id else { return }
        runComparison(before: before, after: after)
    }

    private func checkPendingComparison() {
        guard let beforeID = UserDefaults.standard.string(forKey: "PendingComparisonBeforeID"),
              let afterID = UserDefaults.standard.string(forKey: "PendingComparisonAfterID") else { return }
        UserDefaults.standard.removeObject(forKey: "PendingComparisonBeforeID")
        UserDefaults.standard.removeObject(forKey: "PendingComparisonAfterID")
        openComparison(beforeID: beforeID, afterID: afterID)
    }

    private func openComparison(beforeID: String, afterID: String) {
        Task {
            await appModel.loadSnapshots()
            let all = appModel.snapshots + appModel.baseSnapshots
            guard let before = all.first(where: { $0.id == beforeID }),
                  let after = all.first(where: { $0.id == afterID }) else { return }
            runComparison(before: before, after: after)
        }
    }

    private func runComparison(before: StoredSnapshot, after: StoredSnapshot) {
        isComparing = true
        Task {
            do {
                let id = try await appModel.compareForWindow(before: before, after: after)
                openWindow(value: id)
            } catch {
                errorMessage = error.localizedDescription
            }
            isComparing = false
        }
    }
}

private struct SnapshotRow: View {
    let snapshot: StoredSnapshot
    let isSelected: Bool
    let role: String?
    let changeDescriptions: [String]
    let onTap: (NSEvent.ModifierFlags) -> Void
    let onRename: (String) -> Void
    let onDelete: () -> Void

    @State private var isEditing = false
    @State private var editText = ""

    private var descriptionSummary: String {
        if !changeDescriptions.isEmpty { return changeDescriptions.joined(separator: " · ") }
        guard let r = snapshot.recognizedCount else { return "" }
        if r > 0 { return "" }
        let u = snapshot.unrecognizedCount ?? 0
        return u > 0 ? "\(u) unrecognized \(u == 1 ? "change" : "changes")" : "No recognized changes"
    }

    var body: some View {
        HStack {
            if isEditing {
                RenameTextField(
                    text: $editText,
                    onCommit: commitRename,
                    onCancel: { isEditing = false }
                )
                Spacer()
            } else {
                Text(snapshot.displayName)
                    .foregroundStyle(.primary)
                    .font(.body)
                Text(descriptionSummary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if !isEditing {
                changeCountLabel
                Text(snapshot.formattedFileSize)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            if isSelected && !isEditing {
                if let role {
                    Text(role)
                        .font(.caption.bold())
                        .foregroundStyle(Color.accentColor)
                } else {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                        .font(.caption.bold())
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture(count: 1) { if !isEditing { onTap(NSApp.currentEvent?.modifierFlags ?? []) } }
        .contextMenu {
            if !snapshot.isBaseSnapshot {
                Button("Rename") {
                    editText = snapshot.displayName
                    isEditing = true
                }
                Divider()
                Button("Delete", role: .destructive) { onDelete() }
            }
        }
    }

    @ViewBuilder
    private var changeCountLabel: some View {
        if snapshot.fromBaseline {
            Text("First snapshot")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.trailing, 4)
        } else if let r = snapshot.recognizedCount, r > 0 {
            Text("\(r) change\(r == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.trailing, 4)
        }
    }

    private func commitRename() {
        let trimmed = editText.trimmingCharacters(in: .whitespaces)
        isEditing = false
        onRename(trimmed)
    }
}

private struct RenameTextField: NSViewRepresentable {
    @Binding var text: String
    var onCommit: () -> Void
    var onCancel: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(string: text)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: NSFont.systemFontSize)
        field.delegate = context.coordinator
        DispatchQueue.main.async {
            field.window?.makeFirstResponder(field)
            field.currentEditor()?.selectAll(nil)
            context.coordinator.startMonitoring(field: field)
        }
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.onCommit = onCommit
        context.coordinator.onCancel = onCancel
        if field.currentEditor() == nil {
            field.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    class Coordinator: NSObject, NSTextFieldDelegate {
        @Binding var text: String
        var onCommit: () -> Void = {}
        var onCancel: () -> Void = {}
        private var committed = false
        private var monitor: Any?

        init(text: Binding<String>) { _text = text }

        func startMonitoring(field: NSTextField) {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak field] event in
                guard let field, let window = field.window else { return event }
                let locationInWindow = event.locationInWindow
                let fieldFrameInWindow = field.convert(field.bounds, to: nil)
                if !fieldFrameInWindow.contains(locationInWindow) {
                    window.makeFirstResponder(nil)
                }
                return event
            }
        }

        func stopMonitoring() {
            if let m = monitor { NSEvent.removeMonitor(m) }
            monitor = nil
        }

        func controlTextDidChange(_ obj: Notification) {
            text = (obj.object as? NSTextField)?.stringValue ?? text
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            stopMonitoring()
            guard !committed else { return }
            committed = true
            text = (obj.object as? NSTextField)?.stringValue ?? text
            onCommit()
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                committed = true
                stopMonitoring()
                control.window?.makeFirstResponder(nil)
                onCancel()
                return true
            }
            return false
        }
    }
}
