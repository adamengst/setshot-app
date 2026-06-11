import Foundation

// Invoked by setshot.sh as: SetShot --explain-diff <before> <after>
// Loads the cached KB from UserDefaults, diffs the two snapshot files,
// and prints a human-readable summary to stdout.
enum DiffExplainer {
    static func run() {
        let args = CommandLine.arguments
        guard args.count >= 4 else {
            fputs("Usage: SetShot --explain-diff <before-snapshot> <after-snapshot>\n", stderr)
            exit(1)
        }
        let beforePath = args[2]
        let afterPath  = args[3]

        for path in [beforePath, afterPath] {
            guard FileManager.default.fileExists(atPath: path) else {
                fputs("Error: file not found: \(path)\n", stderr)
                exit(1)
            }
        }

        let kb: KnowledgeBase
        if let data = UserDefaults.standard.data(forKey: "kb_entries"),
           let entries = try? JSONDecoder().decode([KBEntry].self, from: data) {
            kb = KnowledgeBase(entries: entries,
                               version: UserDefaults.standard.integer(forKey: "kb_version"),
                               updatedAt: nil)
        } else {
            fputs("Warning: KB cache not found — run SetShot.app once to populate it.\n", stderr)
            kb = .empty
        }

        let beforeText = readSnapshot(path: beforePath)
        let afterText  = readSnapshot(path: afterPath)

        let tmp = FileManager.default.temporaryDirectory
        let beforeTmp = tmp.appendingPathComponent(UUID().uuidString + ".txt")
        let afterTmp  = tmp.appendingPathComponent(UUID().uuidString + ".txt")
        defer {
            try? FileManager.default.removeItem(at: beforeTmp)
            try? FileManager.default.removeItem(at: afterTmp)
        }

        guard (try? beforeText.write(to: beforeTmp, atomically: true, encoding: .utf8)) != nil,
              (try? afterText.write(to: afterTmp,  atomically: true, encoding: .utf8)) != nil else {
            fputs("Error: could not write temp files\n", stderr)
            exit(1)
        }

        let diffOutput = runDiff(before: beforeTmp.path, after: afterTmp.path)
        let result = DiffEngine().parse(diffOutput: diffOutput, kb: kb)

        let total = result.recognized.count + result.unrecognized.count
        print("\(total) \(total == 1 ? "change" : "changes") detected:\n")

        if !result.recognized.isEmpty {
            let maxLen = result.recognized
                .map { ($0.entry.description ?? $0.diff.key).count }
                .max() ?? 0
            for item in result.recognized {
                let label = item.entry.description ?? item.diff.key
                let bvf = formatValue(item.diff.beforeValue, key: item.diff.key, valueMap: item.entry.valueMap)
                let avf = formatValue(item.diff.afterValue, key: item.diff.key, valueMap: item.entry.valueMap)
                let bv = bvf.isEmpty ? "(none)" : bvf
                let av = avf.isEmpty ? "(none)" : avf
                print("  \(label.padding(toLength: maxLen, withPad: " ", startingAt: 0))  \(bv) → \(av)")
            }
            if !result.unrecognized.isEmpty { print() }
        }

        if !result.unrecognized.isEmpty {
            let labels = result.unrecognized.map { "\($0.domain) :: \($0.key)" }
            let maxLen = labels.map(\.count).max() ?? 0
            for (item, label) in zip(result.unrecognized, labels) {
                let padded = label.padding(toLength: maxLen, withPad: " ", startingAt: 0)
                if item.beforeValue.isEmpty {
                    print("  \(padded)  (added) \(item.afterValue.prefix(100))")
                } else if item.afterValue.isEmpty {
                    print("  \(padded)  (removed) \(item.beforeValue.prefix(100))")
                } else {
                    print("  \(padded)  \(item.beforeValue.prefix(100)) → \(item.afterValue.prefix(100))")
                }
            }
        }

        exit(0)
    }

    private static func readSnapshot(path: String) -> String {
        if path.hasSuffix(".gz") {
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            FileManager.default.createFile(atPath: tmp.path, contents: nil)
            defer { try? FileManager.default.removeItem(at: tmp) }
            guard let out = try? FileHandle(forWritingTo: tmp) else { return "" }
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/gzip")
            p.arguments = ["-dc", path]
            p.standardOutput = out
            p.standardError = FileHandle.nullDevice
            try? p.run(); p.waitUntilExit(); try? out.close()
            return (try? String(contentsOf: tmp, encoding: .utf8)) ?? ""
        }
        return (try? String(contentsOf: URL(fileURLWithPath: path), encoding: .utf8)) ?? ""
    }

    private static func runDiff(before: String, after: String) -> String {
        let outURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
        FileManager.default.createFile(atPath: outURL.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: outURL) }
        guard let out = try? FileHandle(forWritingTo: outURL) else { return "" }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/diff")
        p.arguments = ["--unified=0", before, after]
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        try? p.run(); p.waitUntilExit(); try? out.close()
        return (try? String(contentsOf: outURL, encoding: .utf8)) ?? ""
    }
}
