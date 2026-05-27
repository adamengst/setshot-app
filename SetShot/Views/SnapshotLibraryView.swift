import SwiftUI

struct SnapshotLibraryView: View {
    @EnvironmentObject var appModel: AppModel
    @Environment(\.openWindow) private var openWindow
    @State private var selectedBefore: StoredSnapshot?
    @State private var selectedAfter: StoredSnapshot?
    @State private var isTakingSnapshot = false
    @State private var isComparing = false
    @State private var errorMessage: String?
    @State private var showSettings = false
    @State private var showingJournal = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if showingJournal {
                JournalView()
            } else if appModel.snapshots.isEmpty {
                emptyState
            } else {
                pickerColumns
            }
            if !showingJournal {
                Divider()
                footer
            }
        }
        .task { await appModel.loadSnapshots() }
        .sheet(isPresented: $showSettings) {
            SchedulerSettingsView()
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
        HStack(spacing: 12) {
            Text("SetShot").font(.headline)
            Picker("", selection: $showingJournal) {
                Text("Snapshots").tag(false)
                Text("Journal").tag(true)
            }
            .pickerStyle(.segmented)
            .frame(width: 160)
            Spacer()
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gear")
            }
            .buttonStyle(.plain)
            .focusable(false)
            .help("Snapshot settings")

            if isTakingSnapshot {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Capturing…").foregroundStyle(.secondary).font(.callout)
                }
            } else {
                Button("Take Snapshot") { takeSnapshot() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Text("No snapshots yet.")
                .font(.headline)
            Text("Take a snapshot before and after making changes to compare what shifted.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)

            VStack(alignment: .leading, spacing: 6) {
                Text("On your first snapshot, macOS will ask for permission twice — click Allow each time:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(alignment: .top, spacing: 4) {
                    Text("•").font(.caption).foregroundStyle(.secondary)
                    Text("\"SetShot.app\" would like to access data from other apps.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack(alignment: .top, spacing: 4) {
                    Text("•").font(.caption).foregroundStyle(.secondary)
                    Text("\"SetShot.app\" would like to access Apple Music, your music and video activity, and your media library.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: 420)
            .padding(12)
            .background(Color.secondary.opacity(0.07))
            .cornerRadius(8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var pickerColumns: some View {
        HStack(spacing: 0) {
            snapshotColumn(label: "Before", selected: $selectedBefore) { snapshot in
                selectedAfter.map { snapshot.date >= $0.date } ?? false
            }
            Divider()
            snapshotColumn(label: "After", selected: $selectedAfter) { snapshot in
                selectedBefore.map { snapshot.date <= $0.date } ?? false
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
            Divider()
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(appModel.snapshots) { snapshot in
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
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var footer: some View {
        HStack {
            if let before = selectedBefore, let after = selectedAfter {
                Text("\(before.displayName)  →  \(after.displayName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isComparing {
                ProgressView().controlSize(.small)
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
