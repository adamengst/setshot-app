import Foundation

struct HTMLExporter {
    static func export(
        result: DiffResult,
        beforeName: String,
        afterName: String,
        macOSMajor: Int
    ) -> String {
        let title = "SetShot — \(beforeName) vs \(afterName)"
        let rows = result.recognized.map { item in
            row(entry: item.entry, diff: item.diff, macOSMajor: macOSMajor)
        }.joined(separator: "\n")

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
        .subtitle { color: #666; font-size: 13px; margin-bottom: 28px; }
        .item { display: flex; gap: 14px; align-items: flex-start; padding: 14px; background: #f5f5f7; border-radius: 10px; margin-bottom: 10px; }
        .checkbox-col { padding-top: 2px; flex-shrink: 0; }
        input[type=checkbox] { width: 18px; height: 18px; cursor: pointer; accent-color: #007aff; }
        .content { flex: 1; }
        .description { font-weight: 600; margin-bottom: 3px; }
        .location { font-size: 13px; color: #666; margin-bottom: 8px; }
        .values { font-family: ui-monospace, monospace; font-size: 13px; display: flex; align-items: center; gap: 8px; flex-wrap: wrap; }
        .before { color: #c25b00; }
        .after { color: #0055cc; }
        .arrow { color: #999; }
        .open-btn { font-size: 12px; color: #007aff; text-decoration: none; border: 1px solid #007aff; border-radius: 5px; padding: 3px 9px; white-space: nowrap; flex-shrink: 0; align-self: flex-start; }
        .open-btn:hover { background: #007aff; color: #fff; }
        @media print { .open-btn { display: none; } }
        </style>
        </head>
        <body>
        <h1>\(htmlEscape(title))</h1>
        <p class="subtitle">\(result.recognized.count) recognized change\(result.recognized.count == 1 ? "" : "s")</p>
        \(rows)
        </body>
        </html>
        """
    }

    private static func row(entry: KBEntry, diff: DiffLine, macOSMajor: Int) -> String {
        let desc = htmlEscape(entry.description ?? diff.key)
        let location = entry.effectiveUILocation(macOSMajor: macOSMajor).map { "<div class=\"location\">\(htmlEscape($0))</div>" } ?? ""
        let before = htmlEscape(diff.beforeValue.isEmpty ? "(none)" : formatValue(diff.beforeValue, key: diff.key, valueMap: entry.valueMap))
        let after = htmlEscape(diff.afterValue.isEmpty ? "(none)" : formatValue(diff.afterValue, key: diff.key, valueMap: entry.valueMap))
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
