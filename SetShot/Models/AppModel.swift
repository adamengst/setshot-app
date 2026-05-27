import Foundation

struct ComparisonRecord {
    let before: StoredSnapshot
    let after: StoredSnapshot
    let diff: DiffResult
}

@MainActor
class AppModel: ObservableObject {
    @Published var kb: KnowledgeBase = .empty
    @Published var kbUnavailable = false
    @Published var snapshots: [StoredSnapshot] = []
    @Published var journal: [JournalEntry] = []
    @Published var comparisons: [UUID: ComparisonRecord] = [:]

    private let store = SnapshotStore.shared
    private let journalStore = JournalStore.shared

    // Called once at launch: load everything, then refresh journal if needed.
    func start() async {
        async let kbLoad: Void = loadKB()
        async let snapshotsLoad: Void = loadSnapshots()
        _ = await (kbLoad, snapshotsLoad)
        await loadJournal()
        await refreshJournalIfNeeded()
    }

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
        let previous = snapshots.sorted { $0.date < $1.date }.last
        let snapshot = try await SnapshotRunner().run()
        let stored = try await store.save(snapshot.rawOutput, takenAt: snapshot.takenAt)
        snapshots = (try? await store.list()) ?? []
        if let previous {
            Task { await updateJournal(before: previous, after: stored) }
        }
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

    func compareForWindow(before: StoredSnapshot, after: StoredSnapshot) async throws -> UUID {
        let result = try await diff(before: before, after: after)
        let id = UUID()
        comparisons[id] = ComparisonRecord(before: before, after: after, diff: result)
        return id
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

    // MARK: - Journal auto-building

    // Re-runs all adjacent snapshot diffs when the KB version advances.
    // The initial lastKBVersion=0 in UserDefaults means this also fires once
    // on first launch with any real KB, bootstrapping existing snapshots.
    private func refreshJournalIfNeeded() async {
        let currentVersion = kb.version
        guard currentVersion > 0 else { return }
        let lastVersion = UserDefaults.standard.integer(forKey: "JournalLastKBVersion")
        guard currentVersion > lastVersion else { return }
        await buildJournalFromAdjacentSnapshots()
        UserDefaults.standard.set(currentVersion, forKey: "JournalLastKBVersion")
    }

    private func buildJournalFromAdjacentSnapshots() async {
        let sorted = snapshots.sorted { $0.date < $1.date }
        for i in 0..<(sorted.count - 1) {
            await updateJournal(before: sorted[i], after: sorted[i + 1])
        }
    }

    private func updateJournal(before: StoredSnapshot, after: StoredSnapshot) async {
        guard let recognized = try? await diffRecognized(before: before, after: after) else { return }
        journal = await journalStore.add(recognized: recognized, afterSnapshot: after)
    }

    private func diffRecognized(before: StoredSnapshot, after: StoredSnapshot) async throws -> [(entry: KBEntry, diff: DiffLine)] {
        async let beforeText = store.load(before)
        async let afterText = store.load(after)
        let (b, a) = try await (beforeText, afterText)
        let result = try await DiffEngine().diff(
            before: Snapshot(takenAt: before.date, rawOutput: b),
            after: Snapshot(takenAt: after.date, rawOutput: a),
            kb: kb
        )
        return result.recognized
    }
}
