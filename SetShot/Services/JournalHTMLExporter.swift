import Foundation

struct JournalHTMLExporter {
    static func export(journal: [JournalEntry], oldestFirst: Bool) -> String {
        let exportDate = Date().formatted(.dateTime.month(.wide).day().year())
        let title = "SetShot Journal — \(exportDate)"

        let grouped = Dictionary(grouping: journal) { $0.afterSnapshotId }
        var sectionData: [(date: Date, name: String, entries: [JournalEntry])] = grouped.map { _, entries in
            (date: entries[0].afterSnapshotDate, name: entries[0].afterSnapshotName, entries: entries)
        }
        sectionData.sort { oldestFirst ? $0.date < $1.date : $0.date > $1.date }

        let sections = sectionData.map { section(date: $0.date, name: $0.name, entries: $0.entries) }.joined(separator: "\n")
        let total = journal.count

        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(htmlEscape(title))</title>
        <style>
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body { font-family: -apple-system, sans-serif; font-size: 15px; color: #1c1c1e; background: #fff; padding: 32px; max-width: 800px; margin: 0 auto; }
        h1 { font-size: 20px; font-weight: 700; margin-bottom: 6px; }
        .subtitle { color: #666; font-size: 13px; margin-bottom: 32px; }
        h2 { font-size: 15px; font-weight: 600; margin-bottom: 8px; padding-bottom: 4px; border-bottom: 1px solid #e0e0e0; }
        .section { margin-bottom: 28px; }
        .item { display: flex; gap: 14px; align-items: flex-start; padding: 14px; background: #f5f5f7; border-radius: 10px; margin-bottom: 8px; }
        .checkbox-col { padding-top: 2px; flex-shrink: 0; }
        input[type=checkbox] { width: 18px; height: 18px; cursor: pointer; accent-color: #007aff; }
        .content { flex: 1; }
        .description { font-weight: 600; margin-bottom: 3px; }
        .location { font-size: 13px; color: #666; margin-bottom: 8px; }
        .values { font-family: ui-monospace, monospace; font-size: 13px; display: flex; align-items: center; gap: 8px; flex-wrap: wrap; }
        .before { color: #c25b00; }
        .after { color: #0055cc; }
        .arrow { color: #999; }
        .note { margin-top: 8px; font-size: 13px; color: #555; font-style: italic; padding-left: 8px; border-left: 3px solid #ddd; }
        .open-btn { font-size: 12px; color: #007aff; text-decoration: none; border: 1px solid #007aff; border-radius: 5px; padding: 3px 9px; white-space: nowrap; flex-shrink: 0; align-self: flex-start; }
        .open-btn:hover { background: #007aff; color: #fff; }
        @media print { .open-btn { display: none; } }
        </style>
        </head>
        <body>
        <h1>\(htmlEscape(title))</h1>
        <p class="subtitle">\(total) change\(total == 1 ? "" : "s") across \(sectionData.count) comparison\(sectionData.count == 1 ? "" : "s")</p>
        \(sections)
        </body>
        </html>
        """
    }

    private static func section(date: Date, name: String, entries: [JournalEntry]) -> String {
        let dateStr = date.formatted(.dateTime.weekday(.wide).month(.wide).day().year().hour().minute())
        let count = entries.count
        let rows = entries.map { row($0) }.joined(separator: "\n")
        return """
        <div class="section">
        <h2>\(htmlEscape(dateStr)) &mdash; \(count) change\(count == 1 ? "" : "s")</h2>
        \(rows)
        </div>
        """
    }

    private static func row(_ entry: JournalEntry) -> String {
        let desc = htmlEscape(entry.entryDescription.isEmpty ? entry.key : entry.entryDescription)
        let location = entry.uiLocation.map { "<div class=\"location\">\(htmlEscape($0))</div>" } ?? ""
        let before = htmlEscape(entry.oldValue.isEmpty ? "(none)" : formatValue(entry.oldValue, key: entry.key, valueMap: nil))
        let after  = htmlEscape(entry.newValue.isEmpty ? "(none)" : formatValue(entry.newValue, key: entry.key, valueMap: nil))
        let noteHTML: String
        if let note = entry.userNote, !note.isEmpty {
            noteHTML = "<div class=\"note\">\(htmlEscape(note))</div>"
        } else {
            noteHTML = ""
        }
        let openBtn: String
        if let raw = entry.settingsURL,
           raw.hasPrefix("x-apple.systempreferences:"),
           !raw.contains("://"),
           !raw.contains(" ") {
            openBtn = "<a class=\"open-btn\" href=\"\(htmlEscape(raw))\">Open in Settings</a>"
        } else {
            openBtn = ""
        }
        return """
            <div class="item">
              <div class="checkbox-col"><input type="checkbox"></div>
              <div class="content">
                <div class="description">\(desc)</div>
                \(location)<div class="values"><span class="before">\(before)</span><span class="arrow">→</span><span class="after">\(after)</span></div>
                \(noteHTML)
              </div>
              \(openBtn)
            </div>
        """
    }

    private static func htmlEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
         .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
