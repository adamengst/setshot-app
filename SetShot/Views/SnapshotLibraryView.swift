import SwiftUI

struct SnapshotLibraryView: View {
    @EnvironmentObject var appModel: AppModel
    @Binding var appState: AppState
    @State private var selectedBefore: StoredSnapshot?
    @State private var selectedAfter: StoredSnapshot?
    @State private var isTakingSnapshot = false
    @State private var isComparing = false
    @State private var errorMessage: String?
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if appModel.snapshots.isEmpty {
                emptyState
            } else {
                pickerColumns
            }
            Divider()
            footer
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
            snapshotColumn(label: "Before", selected: $selectedBefore, exclude: selectedAfter)
            Divider()
            snapshotColumn(label: "After", selected: $selectedAfter, exclude: selectedBefore)
        }
    }

    private func snapshotColumn(
        label: String,
        selected: Binding<StoredSnapshot?>,
        exclude: StoredSnapshot?
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
                        let isExcluded = exclude?.id == snapshot.id
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
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var footer: some View {
        HStack {
            if let before = selectedBefore, let after = selectedAfter {
                let reversed = after.date <= before.date
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(before.displayName)  →  \(after.displayName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if reversed {
                        Text("Note: the After snapshot predates the Before snapshot — the diff direction may be unexpected.")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
            }
            Spacer()
            if isComparing {
                ProgressView().controlSize(.small)
            } else {
                Button("Compare") { compare() }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedBefore == nil || selectedAfter == nil || selectedBefore?.id == selectedAfter?.id)
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
                let diff = try await appModel.diff(before: before, after: after)
                appState = .results(diff, before: before, after: after)
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
                TextField("", text: $editText)
                    .textFieldStyle(.plain)
                    .onSubmit { commitRename() }
                    .onExitCommand { isEditing = false }
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
        .onTapGesture(count: 2) {
            guard !isExcluded else { return }
            editText = snapshot.customLabel ?? ""
            isEditing = true
        }
        .onTapGesture(count: 1) { if !isExcluded && !isEditing { onTap() } }
        .contextMenu {
            Button("Rename") {
                editText = snapshot.customLabel ?? ""
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
