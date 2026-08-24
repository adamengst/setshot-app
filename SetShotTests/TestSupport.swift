import Foundation
import XCTest
@testable import SetShot

/// Shared helpers for the tests that exercise the real setshot.sh script and the
/// real knowledge base, rather than hand-built fixtures.
enum TestSupport {

    // MARK: - Locations

    /// Repo root, derived from this file's own path so the tests work regardless
    /// of where DerivedData puts the test bundle.
    static let repoRoot: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // SetShotTests/
        .deletingLastPathComponent()   // repo root

    static let scriptURL = repoRoot
        .appendingPathComponent("SetShot/Resources/setshot.sh")

    static let baseSnapshotsDir = repoRoot
        .appendingPathComponent("SetShot/Resources/BaseSnapshots")

    /// The knowledge base lives in a sibling repo (adamengst/setshot-kb) and is
    /// fetched over the network at runtime, so it is not guaranteed to be present.
    /// Tests that need it call `requireKnowledgeBase()` and skip when it is absent.
    static var knowledgeBaseURL: URL? {
        if let override = ProcessInfo.processInfo.environment["SETSHOT_KB_PATH"] {
            let url = URL(fileURLWithPath: override)
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }
        let sibling = repoRoot
            .deletingLastPathComponent()
            .appendingPathComponent("setshot-kb/settings-kb.json")
        return FileManager.default.fileExists(atPath: sibling.path) ? sibling : nil
    }

    static func requireKnowledgeBase() throws -> [KBEntry] {
        guard let url = knowledgeBaseURL else {
            throw XCTSkip("""
                settings-kb.json not found. Clone adamengst/setshot-kb next to this \
                repo, or set SETSHOT_KB_PATH to its settings-kb.json.
                """)
        }
        return try JSONDecoder().decode([KBEntry].self, from: try Data(contentsOf: url))
    }

    // MARK: - Processes

    @discardableResult
    static func run(_ executable: String, _ arguments: [String]) throws -> (status: Int32, output: String) {
        // Write stdout to a file rather than a Pipe: diff output over the 64 KB
        // pipe buffer would block the child before it exits. Same reason DiffEngine
        // does it this way.
        let outURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".out")
        FileManager.default.createFile(atPath: outURL.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: outURL) }

        let handle = try FileHandle(forWritingTo: outURL)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = handle
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        try? handle.close()

        let text = (try? String(contentsOf: outURL, encoding: .utf8)) ?? ""
        return (process.terminationStatus, text)
    }

    static func gunzip(_ url: URL) throws -> String {
        try run("/usr/bin/gzip", ["-dc", url.path]).output
    }

    /// Runs `setshot.sh diff` exactly the way DiffEngine does, so the tests see the
    /// same noise filtering the app sees.
    static func runScriptDiff(before: String, after: String) throws -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let beforeURL = dir.appendingPathComponent("before.txt")
        let afterURL = dir.appendingPathComponent("after.txt")
        try before.write(to: beforeURL, atomically: true, encoding: .utf8)
        try after.write(to: afterURL, atomically: true, encoding: .utf8)

        return try run("/bin/bash", [scriptURL.path, "diff", beforeURL.path, afterURL.path]).output
    }

    // MARK: - Snapshot structure

    struct Section {
        let name: String
        /// Lines carrying settings data: headers, banners, comments, blanks and
        /// empty-state sentinels removed.
        var dataLines: [String] = []
        /// Sentinels like `X :: (not found)` — informational, not settings.
        var sentinelLines: [String] = []
    }

    private static let sectionHeader = try! NSRegularExpression(pattern: #"^#{10} (.*) #{10}$"#)
    /// `X :: (…)` with no `=` — an empty-state marker the script emits when a
    /// source is missing or unreadable.
    private static let sentinel = try! NSRegularExpression(pattern: #"^[^=]*::\s*\(.*\)\s*$"#)
    /// The banner block at the top of every snapshot, and the footer.
    private static let banner = try! NSRegularExpression(
        pattern: #"^(={10,}|macOS Settings Snapshot|Date:|macOS:|Host:|User:|Mode:|Snapshot complete:)"#
    )

    static func sections(of snapshot: String) -> [Section] {
        var result: [Section] = []
        var current: Section?

        for rawLine in snapshot.components(separatedBy: "\n") {
            let line = rawLine
            let ns = line as NSString
            let full = NSRange(location: 0, length: ns.length)

            if let m = sectionHeader.firstMatch(in: line, range: full) {
                if let c = current { result.append(c) }
                current = Section(name: ns.substring(with: m.range(at: 1)))
                continue
            }
            guard current != nil else { continue }
            if line.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            if line.hasPrefix("#") { continue }
            if banner.firstMatch(in: line, range: full) != nil { continue }

            if sentinel.firstMatch(in: line, range: full) != nil {
                current?.sentinelLines.append(line)
            } else {
                current?.dataLines.append(line)
            }
        }
        if let c = current { result.append(c) }
        return result
    }

    /// The parser DiffEngine applies to every diff line. A snapshot line that does
    /// not match this (once prefixed with + or -) can never reach the UI.
    private static let diffLineRegex = try! NSRegularExpression(
        pattern: #"^([+-])(.*?)\s*::\s*(.*?)\s*=\s*(.*)$"#
    )

    static func isParseable(_ snapshotLine: String) -> Bool {
        let line = "+" + snapshotLine
        let ns = line as NSString
        return diffLineRegex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) != nil
    }

    // MARK: - Fixtures

    static func baseSnapshotFixtures() throws -> [(name: String, text: String)] {
        let urls = try FileManager.default
            .contentsOfDirectory(at: baseSnapshotsDir, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("base_") && $0.lastPathComponent.hasSuffix(".txt.gz") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        XCTAssertFalse(urls.isEmpty, "No base snapshots found in \(baseSnapshotsDir.path)")
        return try urls.map { ($0.lastPathComponent, try gunzip($0)) }
    }
}
