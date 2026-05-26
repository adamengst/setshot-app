import Foundation

@MainActor
class AppModel: ObservableObject {
    @Published var kb: KnowledgeBase = .empty
    @Published var kbUnavailable = false
    @Published var snapshots: [StoredSnapshot] = []
    @Published var journal: [JournalEntry] = []

    private let store = SnapshotStore.shared
    private let journalStore = JournalStore.shared

    func loadKB() async {
        let (kb, unavailable) = await KBFetcher.shared.fetchIfNeeded()
        self.kb = kb
        self.kbUnavailable = unavailable
    }

    func refreshKB() async {
        let (kb, unavailable) = await KBFetcher.shared.forceRefresh()
        self.kb = kb
        self.kbUnavailable = unavailable
    }

    func loadSnapshots() async {
        snapshots = (try? await store.list()) ?? []
    }

    func loadJournal() async {
        journal = await journalStore.load()
    }

    func takeSnapshot() async throws -> StoredSnapshot {
        let snapshot = try await SnapshotRunner().run()
        let stored = try await store.save(snapshot.rawOutput, takenAt: snapshot.takenAt)
        snapshots = (try? await store.list()) ?? []
        return stored
    }

    func deleteSnapshot(_ snapshot: StoredSnapshot) async {
        try? await store.delete(snapshot)
        snapshots = (try? await store.list()) ?? []
    }

    func renameSnapshot(_ snapshot: StoredSnapshot, to label: String) async {
        guard let renamed = try? await store.rename(snapshot, to: label) else { return }
        if let i = snapshots.firstIndex(where: { $0.id == snapshot.id }) {
            snapshots[i] = renamed
        }
    }

    func diff(before: StoredSnapshot, after: StoredSnapshot) async throws -> DiffResult {
        async let beforeText = store.load(before)
        async let afterText = store.load(after)
        let (b, a) = try await (beforeText, afterText)
        let bSnap = Snapshot(takenAt: before.date, rawOutput: b)
        let aSnap = Snapshot(takenAt: after.date, rawOutput: a)
        let result = try await DiffEngine().diff(before: bSnap, after: aSnap, kb: kb)
        journal = await journalStore.add(recognized: result.recognized, afterSnapshot: after)
        return result
    }

    func deleteJournalEntry(_ entry: JournalEntry) async {
        journal = await journalStore.delete(entryID: entry.id)
    }

    func deleteJournalSection(afterSnapshotId: String) async {
        journal = await journalStore.delete(afterSnapshotId: afterSnapshotId)
    }
}
