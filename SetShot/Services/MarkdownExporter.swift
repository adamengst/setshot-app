import Foundation

/// Plain-text exports, for reading in any editor and for diffing.
///
/// Comparing two Macs means putting two exports side by side, so the format has to
/// survive `diff`: one change per line group, no alignment padding, and values
/// quoted so a stray Markdown character in a path does not reformat the line.
/// The checkboxes mirror the HTML export's, which are there to tick off as you
/// reconcile — Markdown task lists render the same way in most viewers.
struct MarkdownExporter {

    static func export(result: DiffResult, beforeName: String, afterName: String,
                       macOSMajor: Int) -> String {
        var out = "# SetShot — \(StoredSnapshot.exportComputerName)\n\n"
        out += "\(beforeName) → \(afterName)\n\n"
        let n = result.recognized.count
        out += "\(n) recognized change\(n == 1 ? "" : "s")\n"
        if let warning = result.limitedAccessWarning {
            out += "\n> \(warning)\n"
        }
        out += "\n"
        for item in result.recognized {
            out += row(description: rowDescription(entry: item.entry, key: item.diff.key),
                       location: item.entry.effectiveUILocation(macOSMajor: macOSMajor),
                       before: item.diff.beforeValue.isEmpty ? "(none)"
                           : formatValue(item.diff.beforeValue, key: item.diff.key,
                                         valueMap: item.entry.valueMap,
                                         detail: item.diff.beforeDetail),
                       after: item.diff.afterValue.isEmpty ? "(none)"
                           : formatValue(item.diff.afterValue, key: item.diff.key,
                                         valueMap: item.entry.valueMap,
                                         detail: item.diff.afterDetail),
                       note: nil)
        }
        return out
    }

    static func export(journal: [JournalEntry], oldestFirst: Bool) -> String {
        let exportDate = Date().formatted(.dateTime.month(.wide).day().year())
        var out = "# SetShot Journal — \(StoredSnapshot.exportComputerName) — \(exportDate)\n\n"
        out += "\(journal.count) change\(journal.count == 1 ? "" : "s")\n\n"

        let grouped = Dictionary(grouping: journal) { $0.afterSnapshotId }
        var sections: [(date: Date, entries: [JournalEntry])] = grouped.map { _, entries in
            (date: entries[0].afterSnapshotDate, entries: entries)
        }
        sections.sort { oldestFirst ? $0.date < $1.date : $0.date > $1.date }

        for section in sections {
            let when = section.date.formatted(
                .dateTime.weekday(.wide).month(.wide).day().year().hour().minute())
            let count = section.entries.count
            out += "## \(when) — \(count) change\(count == 1 ? "" : "s")\n\n"
            for entry in section.entries {
                out += row(description: entry.entryDescription.isEmpty ? entry.key
                                                                       : entry.entryDescription,
                           location: entry.uiLocation,
                           before: entry.oldValue.isEmpty ? "(none)"
                               : formatValue(entry.oldValue, key: entry.key, valueMap: nil),
                           after: entry.newValue.isEmpty ? "(none)"
                               : formatValue(entry.newValue, key: entry.key, valueMap: nil),
                           note: entry.userNote)
            }
        }
        return out
    }

    private static func row(description: String, location: String?,
                            before: String, after: String, note: String?) -> String {
        var out = "- [ ] \(escape(description))\n"
        if let location, !location.isEmpty { out += "  - \(escape(location))\n" }
        out += "  - `\(before)` → `\(after)`\n"
        if let note, !note.isEmpty { out += "  - Note: \(escape(note))\n" }
        return out + "\n"
    }

    /// Only the characters that would break the list structure. Escaping more would
    /// litter the text with backslashes for a reader who is not rendering it.
    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\n", with: " ")
         .replacingOccurrences(of: "[", with: "\\[")
         .replacingOccurrences(of: "]", with: "\\]")
    }
}
