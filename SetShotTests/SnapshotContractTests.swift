import XCTest
@testable import SetShot

/// Asserts that what setshot.sh captures can actually reach the UI.
///
/// Three of the classes of bug these cover were each invisible in isolation: the
/// capture works, the KB entry exists, and the emit format silently disagrees with
/// both. Nothing fails loudly, so a setting just never shows up.
///
/// Runs against the base snapshots checked into SetShot/Resources/BaseSnapshots,
/// which are real captures and therefore exercise the real emit formats.
///
/// A snapshot taken here and now is the only thing that tests the script as it
/// stands, so one is taken by default (~12s). The base snapshots are frozen
/// captures from older versions of the script, so a section whose emit format has
/// since changed is exempted for fixtures only, via KnownIssues.legacyFixtureSections.
///
/// To skip the live capture while iterating:
///
///     TEST_RUNNER_SETSHOT_SKIP_LIVE=1 xcodebuild test \
///       -project SetShot.xcodeproj -scheme SetShot -destination 'platform=macOS'
///
/// (xcodebuild only forwards environment variables prefixed with TEST_RUNNER_,
/// stripping the prefix before the test process sees them.)
final class SnapshotContractTests: XCTestCase {

    // MARK: - Fixtures

    private struct Analysis {
        let name: String
        /// True for a snapshot taken by the current script, false for the frozen
        /// base snapshots, which were captured by earlier versions of it.
        let isLive: Bool
        let sections: [TestSupport.Section]
        /// Snapshot lines that survive the script's own noise filter.
        let surviving: Set<String>

        func visibleLines(in section: TestSupport.Section) -> [String] {
            section.dataLines.filter { surviving.contains($0) && TestSupport.isParseable($0) }
        }
        func unparseableLines(in section: TestSupport.Section) -> [String] {
            section.dataLines.filter { !TestSupport.isParseable($0) }
        }
    }

    /// Diffs a snapshot against an empty one so every line appears as a deletion,
    /// then keeps whatever the script's noise filter did not remove. This uses the
    /// real grep and the real NOISE_PATTERN rather than reimplementing either.
    private func analyse(name: String, snapshot: String, isLive: Bool) throws -> Analysis {
        let diff = try TestSupport.runScriptDiff(before: snapshot, after: "")
        var surviving = Set<String>()
        for line in diff.components(separatedBy: "\n") where line.hasPrefix("-") {
            surviving.insert(String(line.dropFirst()))
        }
        return Analysis(name: name, isLive: isLive,
                        sections: TestSupport.sections(of: snapshot), surviving: surviving)
    }

    /// Each analysis shells out to setshot.sh (and optionally takes a fresh
    /// snapshot), so it is computed once per test process rather than per test.
    private static var cached: [Analysis]?

    private func allAnalyses() throws -> [Analysis] {
        if let cached = Self.cached { return cached }
        let results = try computeAnalyses()
        Self.cached = results
        return results
    }

    private func computeAnalyses() throws -> [Analysis] {
        var results = try TestSupport.baseSnapshotFixtures().map {
            try analyse(name: $0.name, snapshot: $0.text, isLive: false)
        }
        // The live snapshot is the only thing that tests the script as it stands
        // today, so it runs by default. Set TEST_RUNNER_SETSHOT_SKIP_LIVE=1 to skip
        // it and shave ~12s when iterating on the fixture-only checks.
        if ProcessInfo.processInfo.environment["SETSHOT_SKIP_LIVE"] != "1" {
            results.append(try analyse(name: "live snapshot",
                                       snapshot: try takeLiveSnapshot(), isLive: true))
        }
        return results
    }

    private func takeLiveSnapshot() throws -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let out = dir.appendingPathComponent("snapshot.txt")
        let result = try TestSupport.run(
            "/bin/bash", [TestSupport.scriptURL.path, "snapshot", out.path]
        )
        XCTAssertEqual(result.status, 0, "Live snapshot failed")
        return try String(contentsOf: out, encoding: .utf8)
    }

    // MARK: - Line format

    func testEveryCapturedLineCanBeParsed() throws {
        var failures: [String] = []

        for analysis in try allAnalyses() {
            for section in analysis.sections {
                let bad = analysis.unparseableLines(in: section)
                guard !bad.isEmpty else { continue }
                if KnownIssues.reason(for: section.name, in: KnownIssues.sectionsWithUnparseableLines) != nil {
                    continue
                }
                if !analysis.isLive,
                   KnownIssues.reason(for: section.name, in: KnownIssues.legacyFixtureSections) != nil {
                    continue
                }
                failures.append("""
                    [\(analysis.name)] \(section.name): \(bad.count) line(s) DiffEngine cannot parse.
                    A line needs `domain :: key = value`. Examples:
                    \(bad.prefix(3).map { "      \($0)" }.joined(separator: "\n"))
                    """)
            }
        }

        XCTAssertTrue(failures.isEmpty, """
            Captured settings that can never reach the UI:

            \(failures.joined(separator: "\n\n"))
            """)
    }

    // MARK: - Section visibility

    func testEverySectionContributesSomethingVisible() throws {
        var failures: [String] = []

        for analysis in try allAnalyses() {
            for section in analysis.sections where !section.dataLines.isEmpty {
                guard analysis.visibleLines(in: section).isEmpty else { continue }
                if KnownIssues.reason(for: section.name, in: KnownIssues.sectionsWithNoVisibleData) != nil {
                    continue
                }
                if !analysis.isLive,
                   KnownIssues.reason(for: section.name, in: KnownIssues.legacyFixtureSections) != nil {
                    continue
                }
                failures.append("""
                    [\(analysis.name)] \(section.name): captured \(section.dataLines.count) line(s), \
                    none of which survive both the noise filter and the parser.
                    """)
            }
        }

        XCTAssertTrue(failures.isEmpty, """
            Sections that can never contribute to a comparison:

            \(failures.joined(separator: "\n\n"))
            """)
    }

    func testSectionsThatMustHaveDataAreNotEmpty() throws {
        var failures: [String] = []

        for analysis in try allAnalyses() {
            for section in analysis.sections
            where KnownIssues.sectionsThatMustHaveData.contains(where: { section.name.hasPrefix($0) }) {
                guard section.dataLines.isEmpty else { continue }
                if KnownIssues.reason(for: section.name, in: KnownIssues.sectionsMissingTheirSource) != nil {
                    continue
                }
                let sentinel = section.sentinelLines.first ?? "(section entirely empty)"
                failures.append("""
                    [\(analysis.name)] \(section.name) produced no data, only: \(sentinel)
                    This section should yield settings on any Mac, so its source is \
                    missing or unreadable.
                    """)
            }
        }

        XCTAssertTrue(failures.isEmpty, """
            Sections whose source could not be read:

            \(failures.joined(separator: "\n\n"))
            """)
    }

    // MARK: - Allowlist hygiene

    func testKnownIssuesAreStillIssues() throws {
        let analyses = try allAnalyses()
        var stale: [String] = []

        // Staleness is judged against the current script, so when a live snapshot is
        // available the frozen fixtures are ignored — their older emit formats would
        // otherwise keep a fixed bug looking unfixed.
        let live = analyses.contains(where: \.isLive)
        let judged = live ? analyses.filter(\.isLive) : analyses

        func sectionsFailing(_ predicate: (Analysis, TestSupport.Section) -> Bool) -> Set<String> {
            var seen = Set<String>()
            for a in judged {
                for s in a.sections where !s.dataLines.isEmpty && predicate(a, s) {
                    seen.insert(s.name)
                }
            }
            return seen
        }

        let stillUnparseable = sectionsFailing { !$0.unparseableLines(in: $1).isEmpty }
        let stillInvisible = sectionsFailing { $0.visibleLines(in: $1).isEmpty }
        // Only judge sections we actually observed carrying data.
        let observed = Set(judged.flatMap { $0.sections }
            .filter { !$0.dataLines.isEmpty }.map(\.name))

        for (prefix, _) in KnownIssues.sectionsWithUnparseableLines {
            if KnownIssues.requiresLiveSnapshot.contains(prefix) && !live { continue }
            let matching = observed.filter { $0.hasPrefix(prefix) }
            guard !matching.isEmpty else { continue }
            if matching.allSatisfy({ !stillUnparseable.contains($0) }) {
                stale.append("KnownIssues.sectionsWithUnparseableLines[\"\(prefix)\"] — every line now parses.")
            }
        }

        for (prefix, _) in KnownIssues.sectionsWithNoVisibleData {
            if KnownIssues.requiresLiveSnapshot.contains(prefix) && !live { continue }
            let matching = observed.filter { $0.hasPrefix(prefix) }
            guard !matching.isEmpty else { continue }
            if matching.allSatisfy({ !stillInvisible.contains($0) }) {
                stale.append("KnownIssues.sectionsWithNoVisibleData[\"\(prefix)\"] — the section is visible now.")
            }
        }

        XCTAssertTrue(stale.isEmpty, """
            Fixed bugs still listed in KnownIssues. Delete these lines:

            \(stale.joined(separator: "\n"))
            """)
    }
}
