import SwiftUI

struct SnapshotLibraryView: View {
    @EnvironmentObject var appModel: AppModel
    @Environment(\.openWindow) private var openWindow
    @State private var selectedBefore: StoredSnapshot?
    @State private var selectedAfter: StoredSnapshot?
    @State private var isTakingSnapshot = false
    @State private var isComparing = false
    @State private var errorMessage: String?
    @AppStorage("OldestFirst") private var oldestFirst = false
    private enum Tab { case snapshots, journal, settings, about }
    @State private var activeTab: Tab = UserDefaults.standard.bool(forKey: "HasSeenAbout") ? .snapshots : .about

    private let currentMacOSMajor = ProcessInfo.processInfo.operatingSystemVersion.majorVersion

    private var displaySnapshots: [StoredSnapshot] {
        oldestFirst ? appModel.snapshots.reversed() : appModel.snapshots
    }

    private var matchingBaseSnapshots: [StoredSnapshot] {
        appModel.baseSnapshots.filter { $0.baseMacOSMajor == currentMacOSMajor }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            switch activeTab {
            case .snapshots:
                if appModel.snapshots.isEmpty && matchingBaseSnapshots.isEmpty { emptyState } else { pickerColumns }
            case .journal:
                JournalView()
            case .settings:
                SettingsView()
            case .about:
                AboutView()
            }
            if activeTab == .snapshots {
                Divider()
                footer
            }
        }
        .task {
            await appModel.loadSnapshots()
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

    private var pickerColumns: some View {
        HStack(spacing: 0) {
            snapshotColumn(label: "Before", selected: $selectedBefore) { snapshot in
                guard !snapshot.isBaseSnapshot else { return false }
                return selectedAfter.map { snapshot.date >= $0.date } ?? false
            }
            Divider()
            snapshotColumn(label: "After", selected: $selectedAfter) { snapshot in
                guard !snapshot.isBaseSnapshot else { return false }
                return selectedBefore.map { snapshot.date <= $0.date } ?? false
            }
        }
    }

    private func snapshotColumn(
        label: String,
        selected: Binding<StoredSnapshot?>,
        isDisabled: @escaping (StoredSnapshot) -> Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label)
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
            Divider()
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(displaySnapshots) { snapshot in
                        let isSelected = selected.wrappedValue?.id == snapshot.id
                        let isExcluded = isDisabled(snapshot)
                        SnapshotRow(
                            snapshot: snapshot,
                            isSelected: isSelected,
                            isExcluded: isExcluded
                        ) {
                            selected.wrappedValue = isSelected ? nil : snapshot
                        } onRename: { newName in
                            Task { await appModel.renameSnapshot(snapshot, to: newName) }
                        } onDelete: {
                            deleteSnapshot(snapshot, selected: selected)
                        }
                        .id("\(label)-\(snapshot.id)")
                    }
                    if !matchingBaseSnapshots.isEmpty {
                        Divider()
                            .padding(.top, 4)
                        Text("Baselines")
                            .font(.subheadline.bold())
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                        Divider()
                        ForEach(matchingBaseSnapshots) { snapshot in
                            let isSelected = selected.wrappedValue?.id == snapshot.id
                            BaseSnapshotRow(snapshot: snapshot, isSelected: isSelected) {
                                selected.wrappedValue = isSelected ? nil : snapshot
                            }
                            .id("\(label)-\(snapshot.id)")
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
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
            if let before = selectedBefore, let after = selectedAfter {
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
                    .disabled(selectedBefore == nil || selectedAfter == nil)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - Actions

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

    private func deleteSnapshot(_ snapshot: StoredSnapshot, selected: Binding<StoredSnapshot?>) {
        if selected.wrappedValue?.id == snapshot.id { selected.wrappedValue = nil }
        Task { await appModel.deleteSnapshot(snapshot) }
    }

    private func compare() {
        guard let before = selectedBefore, let after = selectedAfter else { return }
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
            let allSnapshots = appModel.snapshots + appModel.baseSnapshots
            guard let before = allSnapshots.first(where: { $0.id == beforeID }),
                  let after = allSnapshots.first(where: { $0.id == afterID }) else { return }
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
    let isExcluded: Bool
    let onTap: () -> Void
    let onRename: (String) -> Void
    let onDelete: () -> Void

    @State private var isEditing = false
    @State private var editText = ""

    var body: some View {
        HStack {
            if isEditing {
                RenameTextField(
                    text: $editText,
                    onCommit: commitRename,
                    onCancel: { isEditing = false }
                )
            } else {
                Text(snapshot.displayName)
                    .foregroundStyle(isExcluded ? .tertiary : .primary)
            }
            Spacer()
            if !isEditing {
                changeCountLabel
                Text(snapshot.formattedFileSize)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            if isSelected && !isEditing {
                Image(systemName: "checkmark")
                    .foregroundStyle(Color.accentColor)
                    .font(.caption.bold())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture(count: 1) { if !isExcluded && !isEditing { onTap() } }
        .contextMenu {
            Button("Rename") {
                editText = snapshot.displayName
                isEditing = true
            }
            Divider()
            Button("Delete", role: .destructive) { onDelete() }
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

private struct BaseSnapshotRow: View {
    let snapshot: StoredSnapshot
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        HStack {
            Text(snapshot.displayName)
                .foregroundStyle(.secondary)
                .font(.subheadline)
            Spacer()
            Text(snapshot.formattedFileSize)
                .font(.caption)
                .foregroundStyle(.tertiary)
            if isSelected {
                Image(systemName: "checkmark")
                    .foregroundStyle(Color.accentColor)
                    .font(.caption.bold())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
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
