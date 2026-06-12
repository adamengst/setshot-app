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
            if seen.insert(dedupKey(domain: e.domain, key: e.key, old: e.oldValue, new: e.newValue)).inserted {
                result.append(e)
            }
        }
        return result
    }

    // Normalize boolean representations so "True"/"1" and "False"/"0" match each other.
    private func normalizeBool(_ v: String) -> String {
        switch v.lowercased() {
        case "true", "yes", "1": return "1"
        case "false", "no", "0": return "0"
        default: return v
        }
    }

    private func dedupKey(domain: String, key: String, old: String, new: String) -> String {
        "\(domain)|\(key)|\(normalizeBool(old))|\(normalizeBool(new))"
    }

    private func save(_ entries: [JournalEntry]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    @discardableResult
    func add(recognized: [(entry: KBEntry, diff: DiffLine)], afterSnapshot: StoredSnapshot, fromBaseline: Bool = false) -> [JournalEntry] {
        var entries = load()
        let existingKeys = Set(entries.map { dedupKey(domain: $0.domain, key: $0.key, old: $0.oldValue, new: $0.newValue) })
        let now = Date()
        for item in recognized {
            let key = dedupKey(domain: item.diff.domain, key: item.diff.key, old: item.diff.beforeValue, new: item.diff.afterValue)
            guard !existingKeys.contains(key) else { continue }
            entries.append(JournalEntry(
                id: UUID(),
                afterSnapshotId: afterSnapshot.id,
                afterSnapshotDate: afterSnapshot.date,
                afterSnapshotName: afterSnapshot.displayName,
                domain: item.diff.domain,
                key: item.diff.key,
                entryDescription: item.entry.description ?? "",
                uiLocation: item.entry.uiLocation,
                settingsURL: item.entry.settingsURL,
                oldValue: item.diff.beforeValue,
                newValue: item.diff.afterValue,
                addedAt: now,
                fromBaseline: fromBaseline
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

    func deleteAll() {
        save([])
    }
}
