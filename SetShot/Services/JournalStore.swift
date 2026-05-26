import Foundation

actor JournalStore {
    static let shared = JournalStore()

    private let fileURL: URL

    private static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SetShot")
            .appendingPathComponent("journal.json")
    }

    init(fileURL: URL = JournalStore.defaultURL) {
        self.fileURL = fileURL
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }

    func load() -> [JournalEntry] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let entries = (try? decoder.decode([JournalEntry].self, from: data)) ?? []
        let deduped = deduplicated(entries)
        if deduped.count != entries.count { save(deduped) }
        return deduped
    }

    private func deduplicated(_ entries: [JournalEntry]) -> [JournalEntry] {
        var seen = Set<String>()
        var result: [JournalEntry] = []
        // Sort oldest After snapshot first so we always keep the earliest occurrence.
        for e in entries.sorted(by: { $0.afterSnapshotDate < $1.afterSnapshotDate }) {
            if seen.insert("\(e.domain)|\(e.key)|\(e.oldValue)|\(e.newValue)").inserted {
                result.append(e)
            }
        }
        return result
    }

    private func save(_ entries: [JournalEntry]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    @discardableResult
    func add(recognized: [(entry: KBEntry, diff: DiffLine)], afterSnapshot: StoredSnapshot) -> [JournalEntry] {
        var entries = load()
        let existingKeys = Set(entries.map { "\($0.domain)|\($0.key)|\($0.oldValue)|\($0.newValue)" })
        let now = Date()
        for item in recognized {
            let dedupKey = "\(item.diff.domain)|\(item.diff.key)|\(item.diff.beforeValue)|\(item.diff.afterValue)"
            guard !existingKeys.contains(dedupKey) else { continue }
            entries.append(JournalEntry(
                id: UUID(),
                afterSnapshotId: afterSnapshot.id,
                afterSnapshotDate: afterSnapshot.date,
                afterSnapshotName: afterSnapshot.displayName,
                domain: item.diff.domain,
                key: item.diff.key,
                entryDescription: item.entry.description,
                uiLocation: item.entry.uiLocation,
                settingsURL: item.entry.settingsURL,
                oldValue: item.diff.beforeValue,
                newValue: item.diff.afterValue,
                addedAt: now
            ))
        }
        save(entries)
        return entries
    }

    @discardableResult
    func delete(entryID: UUID) -> [JournalEntry] {
        var entries = load()
        entries.removeAll { $0.id == entryID }
        save(entries)
        return entries
    }

    @discardableResult
    func delete(afterSnapshotId: String) -> [JournalEntry] {
        var entries = load()
        entries.removeAll { $0.afterSnapshotId == afterSnapshotId }
        save(entries)
        return entries
    }
}
