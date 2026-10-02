import Foundation

actor JournalStore {
    static let shared = JournalStore()

    private let fileURL: URL
    private var cache: [JournalEntry]?

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
        if let c = cache { return c }
        return reload()
    }

    // Bypasses the in-process cache to pick up entries written by another
    // process — scheduled snapshots run as a separate `--background-snapshot`
    // launch, so a long-running foreground app's cache goes stale as soon as
    // one completes.
    @discardableResult
    func reload() -> [JournalEntry] {
        guard let data = try? Data(contentsOf: fileURL) else {
            cache = []
            return []
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let entries = (try? decoder.decode([JournalEntry].self, from: data)) ?? []
        let deduped = deduplicated(entries)
        if deduped.count != entries.count { save(deduped) }
        cache = deduped
        return deduped
    }

    /// Drops an entry that repeats the previous entry for the same setting.
    ///
    /// Comparisons overlap -- 1 against 2, then 1 against 3 -- so the same change
    /// can be recognized from more than one After snapshot. Those copies sit next to
    /// each other in the setting's history and collapse to the earliest. A setting
    /// that genuinely goes A → B, back to A, then to B again has B → A between the
    /// two A → B entries, so both are kept. Deduplicating on the values alone, across
    /// all history, dropped every return to a state the journal had seen before.
    private func deduplicated(_ entries: [JournalEntry]) -> [JournalEntry] {
        var previous: [String: String] = [:]   // domain|key → normalized old|new
        var result: [JournalEntry] = []
        // Oldest After snapshot first, so the earliest occurrence is the one kept.
        for e in entries.sorted(by: { $0.afterSnapshotDate < $1.afterSnapshotDate }) {
            let setting = "\(e.domain)|\(e.key)"
            let change = "\(normalizeBool(e.oldValue))|\(normalizeBool(e.newValue))"
            if previous[setting] == change { continue }
            previous[setting] = change
            result.append(e)
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
        cache = entries
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    @discardableResult
    func add(recognized: [(entry: KBEntry, diff: DiffLine)], afterSnapshot: StoredSnapshot, fromBaseline: Bool = false) -> [JournalEntry] {
        var entries = load()
        // Re-running a comparison offers the same changes for the same After snapshot.
        // Repeats from other snapshots are settled by deduplicated(_:) below, which
        // can tell an overlapping comparison from a setting changed back and again.
        let existingKeys = Set(entries.filter { $0.afterSnapshotId == afterSnapshot.id }
            .map { dedupKey(domain: $0.domain, key: $0.key, old: $0.oldValue, new: $0.newValue) })
        let now = Date()
        for item in recognized {
            let before = item.diff.beforeValue
            let after = item.diff.afterValue
            let key = dedupKey(domain: item.diff.domain, key: item.diff.key, old: before, new: after)
            guard !existingKeys.contains(key) else { continue }

            // A key appearing from nothing or vanishing to nothing may be half of a
            // round-trip (X → ∅ → X) caused by a preference domain being temporarily
            // deleted — typically during an app auto-update. If the journal already
            // holds the exact opposite change for the same domain+key, cancel both:
            // neither half represents a real user-driven change.
            if before.isEmpty || after.isEmpty,
               let reverseIdx = entries.firstIndex(where: {
                   $0.domain == item.diff.domain &&
                   $0.key == item.diff.key &&
                   $0.oldValue == after &&
                   $0.newValue == before
               }) {
                entries.remove(at: reverseIdx)
                continue
            }

            entries.append(JournalEntry(
                id: UUID(),
                afterSnapshotId: afterSnapshot.id,
                afterSnapshotDate: afterSnapshot.date,
                afterSnapshotName: afterSnapshot.displayName,
                domain: item.diff.domain,
                key: item.diff.key,
                entryDescription: rowDescription(entry: item.entry, key: item.diff.key),
                uiLocation: item.entry.uiLocation,
                settingsURL: item.entry.settingsURL,
                oldValue: before,
                newValue: after,
                addedAt: now,
                fromBaseline: fromBaseline
            ))
        }
        entries = deduplicated(entries)
        save(entries)
        return entries
    }

    @discardableResult
    func updateNote(for entryID: UUID, note: String?) -> [JournalEntry] {
        var entries = load()
        if let idx = entries.firstIndex(where: { $0.id == entryID }) {
            let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines)
            entries[idx].userNote = (trimmed?.isEmpty == false) ? trimmed : nil
            save(entries)
        }
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
