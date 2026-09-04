import XCTest
@testable import SetShot

/// Does turning Media & Apple Music access off hide rows that have nothing to do with
/// it? A user comparing the same Mac against the same baseline two minutes apart, with
/// only that permission changed, saw 332 recognized changes become 38.
///
/// The two inputs here differ in exactly one line — `Music :: available` — so anything
/// that differs between the two results is caused by that marker and nothing else. Both
/// go through the path the app uses: setshot.sh diff, then DiffEngine.parse.
final class MediaMarkerScopeTests: XCTestCase {

    /// Rows a reader would not connect to Media & Apple Music.
    private static let unrelated = ["Wi-Fi", "Hot corner", "Dock", "Trackpad", "Smart Quotes"]

    private func newestUserSnapshot() -> URL? {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/SetShot/snapshots")
        let files = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return files.filter { $0.pathExtension == "gz" }
            .sorted {
                let a = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? .distantPast
                let b = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? .distantPast
                return a > b
            }.first
    }

    func testTheMediaMarkerDoesNotHideUnrelatedSettings() throws {
        let kb = KnowledgeBase(entries: try TestSupport.requireKnowledgeBase(),
                               version: 0, updatedAt: nil)
        let bases = (try? FileManager.default.contentsOfDirectory(
            at: TestSupport.baseSnapshotsDir, includingPropertiesForKeys: nil)) ?? []
        let baseURL = try XCTUnwrap(bases.first { $0.pathExtension == "gz" }, "no bundled baseline")
        let base = try TestSupport.gunzip(baseURL)

        guard let userURL = newestUserSnapshot() else {
            throw XCTSkip("No snapshot in the library to compare against")
        }
        let mediaOn = try TestSupport.gunzip(userURL)
        guard mediaOn.contains("Music :: available = 1") else {
            throw XCTSkip("The newest snapshot was taken without Media & Apple Music access")
        }
        // The only difference between the two inputs.
        let mediaOff = mediaOn.replacingOccurrences(of: "Music :: available = 1",
                                                    with: "Music :: available = 0")

        func recognized(_ after: String) throws -> [String] {
            let diff = try TestSupport.runScriptDiff(before: base, after: after)
            let result = DiffEngine().parse(diffOutput: diff, kb: kb,
                                            beforeSnapshot: base, afterSnapshot: after)
            return result.recognized.map { "\($0.diff.domain) :: \($0.diff.key)\t" + rowDescription(entry: $0.entry, key: $0.diff.key) }
        }

        let withAccess = try recognized(mediaOn)
        let withoutAccess = try recognized(mediaOff)
        let lost = Set(withAccess).subtracting(withoutAccess)
        let lostUnrelated = lost.filter { row in
            Self.unrelated.contains { row.localizedCaseInsensitiveContains($0) }
        }

        XCTAssertTrue(lostUnrelated.isEmpty, """
            Flipping Music :: available removed \(lost.count) recognized rows, \
            \(lostUnrelated.count) of which have nothing to do with Media & Apple Music. \
            That permission gates the Music and TV settings; the suppression should not \
            reach past them.

            with access: \(withAccess.count) rows, without: \(withoutAccess.count)

            \(lostUnrelated.sorted().prefix(12).joined(separator: "\n"))
            """)
    }

    // MARK: - The same thing, on two captures from another Mac

    /// The test above changes one line in a copy, which isolates the marker but is
    /// synthetic. This uses two captures taken minutes apart on a different Mac running
    /// Tahoe, with only the permission toggled between them, and compares each against
    /// the Tahoe baseline the app would pick. Paths come from the environment so this is
    /// not tied to one machine.
    func testTwoRealCapturesDifferingOnlyInTheMediaPermission() throws {
        let env = ProcessInfo.processInfo.environment
        guard let onPath = env["SETSHOT_MEDIA_ON"], let offPath = env["SETSHOT_MEDIA_OFF"] else {
            throw XCTSkip("Set SETSHOT_MEDIA_ON and SETSHOT_MEDIA_OFF to two snapshot paths")
        }
        let kb = KnowledgeBase(entries: try TestSupport.requireKnowledgeBase(),
                               version: 0, updatedAt: nil)
        let mediaOn = try TestSupport.gunzip(URL(fileURLWithPath: onPath))
        let mediaOff = try TestSupport.gunzip(URL(fileURLWithPath: offPath))

        // The baseline the app would choose: matched on macOS major version.
        let major = mediaOn.contains("macOS: 26.") ? "Tahoe" : "Sequoia"
        let bases = (try? FileManager.default.contentsOfDirectory(
            at: TestSupport.baseSnapshotsDir, includingPropertiesForKeys: nil)) ?? []
        let baseURL = try XCTUnwrap(bases.first { $0.lastPathComponent.contains(major) },
                                    "no \(major) baseline")
        let base = try TestSupport.gunzip(baseURL)

        func recognized(_ after: String) throws -> [String] {
            let diff = try TestSupport.runScriptDiff(before: base, after: after)
            let result = DiffEngine().parse(diffOutput: diff, kb: kb,
                                            beforeSnapshot: base, afterSnapshot: after)
            return result.recognized.map { "\($0.diff.domain) :: \($0.diff.key)\t" + rowDescription(entry: $0.entry, key: $0.diff.key) }
        }

        let withAccess = try recognized(mediaOn)
        let withoutAccess = try recognized(mediaOff)
        let lost = Set(withAccess).subtracting(withoutAccess)
        let lostUnrelated = lost.filter { row in
            Self.unrelated.contains { row.localizedCaseInsensitiveContains($0) }
        }

        XCTAssertTrue(lostUnrelated.isEmpty, """
            Against the \(major) baseline: \(withAccess.count) recognized rows with the             permission on, \(withoutAccess.count) with it off. \(lost.count) rows vanished,             \(lostUnrelated.count) of them unrelated to Media & Apple Music.

            \(lostUnrelated.sorted().prefix(12).joined(separator: "\n"))
            """)
    }

    // MARK: - Full Disk Access

    /// The same check for the other permission, against two captures taken with it
    /// granted and revoked and nothing else changed.
    func testTheFullDiskAccessMarkerDoesNotHideUnrelatedSettings() throws {
        let env = ProcessInfo.processInfo.environment
        guard let onPath = env["SETSHOT_FDA_ON"], let offPath = env["SETSHOT_FDA_OFF"] else {
            throw XCTSkip("Set SETSHOT_FDA_ON and SETSHOT_FDA_OFF to two snapshot paths")
        }
        let kb = KnowledgeBase(entries: try TestSupport.requireKnowledgeBase(),
                               version: 0, updatedAt: nil)
        let fdaOn = try TestSupport.gunzip(URL(fileURLWithPath: onPath))
        let fdaOff = try TestSupport.gunzip(URL(fileURLWithPath: offPath))
        let major = fdaOn.contains("macOS: 26.") ? "Tahoe" : "Sequoia"
        let bases = (try? FileManager.default.contentsOfDirectory(
            at: TestSupport.baseSnapshotsDir, includingPropertiesForKeys: nil)) ?? []
        let baseURL = try XCTUnwrap(bases.first { $0.lastPathComponent.contains(major) })
        let base = try TestSupport.gunzip(baseURL)

        func rows(_ after: String) throws -> [(domain: String, text: String)] {
            let diff = try TestSupport.runScriptDiff(before: base, after: after)
            let result = DiffEngine().parse(diffOutput: diff, kb: kb,
                                            beforeSnapshot: base, afterSnapshot: after)
            return result.recognized.map {
                ($0.diff.domain, "\($0.diff.domain) :: \($0.diff.key)")
            }
        }

        let withAccess = try rows(fdaOn)
        let withoutAccess = try rows(fdaOff)
        let keptKeys = Set(withoutAccess.map(\.text))
        // A row that vanished in a domain the permission does not gate is the bug.
        let wronglyLost = withAccess.filter {
            !keptKeys.contains($0.text)
                && !$0.domain.hasPrefix("TCC-")
                && !DiffEngine.fullDiskAccessGatedDomainsInclude($0.domain)
        }

        XCTAssertTrue(wronglyLost.isEmpty, """
            \(withAccess.count) recognized rows with Full Disk Access, \(withoutAccess.count) \
            without. \(wronglyLost.count) that vanished are in domains the permission does \
            not gate.

            \(Set(wronglyLost.map(\.domain)).sorted().prefix(12).joined(separator: "\n"))
            """)
    }

    // MARK: - Diagnostic

    /// Prints what the engine makes of one comparison. Not an assertion about
    /// behaviour — it fails on purpose so the numbers reach the log.
    func testReportOneComparison() throws {
        let env = ProcessInfo.processInfo.environment
        guard let beforePath = env["SETSHOT_BEFORE"], let afterPath = env["SETSHOT_AFTER"] else {
            throw XCTSkip("Set SETSHOT_BEFORE and SETSHOT_AFTER")
        }
        let kb = KnowledgeBase(entries: try TestSupport.requireKnowledgeBase(),
                               version: 0, updatedAt: nil)
        func read(_ p: String) throws -> String {
            p.hasSuffix(".gz") ? try TestSupport.gunzip(URL(fileURLWithPath: p))
                               : try String(contentsOfFile: p, encoding: .utf8)
        }
        let before = try read(beforePath), after = try read(afterPath)
        let diff = try TestSupport.runScriptDiff(before: before, after: after)
        let r = DiffEngine().parse(diffOutput: diff, kb: kb,
                                   beforeSnapshot: before, afterSnapshot: after)
        var byDomain: [String: Int] = [:]
        for u in r.unrecognized { byDomain[u.domain, default: 0] += 1 }
        let top = byDomain.sorted { $0.value > $1.value }.prefix(15)
            .map { "  \($0.value)\t\($0.key)" }.joined(separator: "\n")
        let keys = r.unrecognized.map { "  \($0.domain) :: \($0.key) = \($0.beforeValue)|\($0.afterValue)" }
            .sorted().joined(separator: "\n")
        let rec = r.recognized.map {
            "  [\($0.entry.id)] \($0.diff.domain) :: \($0.diff.key)\n     "
                + rowDescription(entry: $0.entry, key: $0.diff.key)
                + "\n     " + formatValue($0.diff.beforeValue, key: $0.diff.key, valueMap: $0.entry.valueMap, detail: $0.diff.beforeDetail)
                + "  ->  " + formatValue($0.diff.afterValue, key: $0.diff.key, valueMap: $0.entry.valueMap, detail: $0.diff.afterDetail)
        }.sorted().joined(separator: "\n")
        let oneSided = r.unrecognized.filter { $0.beforeValue.isEmpty || $0.afterValue.isEmpty }
        XCTFail("""
            REPORT
            recognized:   \(r.recognized.count)
            unrecognized: \(r.unrecognized.count) (overflow \(r.unrecognizedOverflow))
            noise:        \(r.noise.count)
            one-sided among unrecognized: \(oneSided.count)

            unrecognized by domain:
            \(top)

            KEYS
            \(keys)

            RECOGNIZED
            \(rec)
            """)
    }
}
