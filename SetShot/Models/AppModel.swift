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
    @Published var baseSnapshots: [StoredSnapshot] = []
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
        // Probe the legacy FDA-protected path so SetShot appears in the Full
        // Disk Access list on older macOS. On macOS 15+, this file no longer
        // exists and the probe is a harmless no-op.
        Task.detached(priority: .background) {
            FileHandle(forReadingAtPath: "/var/db/TCC/TCC.db")?.closeFile()
        }
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
        baseSnapshots = store.listBaseSnapshots()
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
            await updateCountsAndJournal(before: previous, after: stored)
            snapshots = (try? await store.list()) ?? []
        } else if let baseline = matchingBaseline() {
            await updateCountsAndJournal(before: baseline, after: stored, fromBaseline: true)
            snapshots = (try? await store.list()) ?? []
        }
        return stored
    }

    private func matchingBaseline() -> StoredSnapshot? {
        let major = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        return baseSnapshots.first { $0.baseMacOSMajor == major }
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
            .filteringHardware(hasBattery: SnapshotRunner.hasBattery)
        journal = await journalStore.add(recognized: result.recognized, afterSnapshot: after)
        return result
    }

    func deleteJournalEntry(_ entry: JournalEntry) async {
        journal = await journalStore.delete(entryID: entry.id)
    }

    func deleteJournalSection(afterSnapshotId: String) async {
        journal = await journalStore.delete(afterSnapshotId: afterSnapshotId)
    }

    func clearJournal() async {
        await journalStore.deleteAll()
        journal = []
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
        for (before, after) in zip(sorted, sorted.dropFirst()) {
            await updateJournal(before: before, after: after)
        }
    }

    private func updateCountsAndJournal(before: StoredSnapshot, after: StoredSnapshot, fromBaseline: Bool = false) async {
        async let beforeText = try? store.load(before)
        async let afterText = try? store.load(after)
        guard let b = await beforeText, let a = await afterText else { return }
        guard let result = try? await DiffEngine().diff(
            before: Snapshot(takenAt: before.date, rawOutput: b),
            after: Snapshot(takenAt: after.date, rawOutput: a),
            kb: kb)
            .filteringHardware(hasBattery: SnapshotRunner.hasBattery) else { return }
        try? await store.saveMeta(for: after, recognized: result.recognized.count, unrecognized: result.unrecognized.count, scheduled: false, fromBaseline: fromBaseline)
        journal = await journalStore.add(recognized: result.recognized, afterSnapshot: after, fromBaseline: fromBaseline)
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
        ).filteringHardware(hasBattery: SnapshotRunner.hasBattery)
        return result.recognized
    }
}
