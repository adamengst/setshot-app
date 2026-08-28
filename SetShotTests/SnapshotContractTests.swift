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
        let raw: String
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
        return Analysis(name: name, raw: snapshot, isLive: isLive,
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
                if !analysis.isLive,
                   KnownIssues.reason(for: section.name, in: KnownIssues.legacyFixtureSections) != nil {
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

    // MARK: - Permission dialogs

    /// Reading a Music, TV or Apple Media Services preference domain wakes a media
    /// daemon and makes macOS put up the Media & Apple Music consent dialog. Those
    /// reads are gated behind an explicit opt-in, and a snapshot taken without it
    /// must not touch any of them — an unexpected consent dialog is alarming, and
    /// it is the user's decision whether SetShot ever asks.
    ///
    /// Full Disk Access has no equivalent risk: it cannot be requested, only granted
    /// by hand, so a denied read fails silently with no dialog. What is checked here
    /// is that a snapshot without it captures no privacy data rather than partial data.
    private static let musicDomainPattern = try! NSRegularExpression(
        pattern: #"/com\.apple\.(Music|iTunes|iTunesX|iCloud\.Music|amp|AMP[A-Za-z]+"#
              + #"|itunes[a-z]*|media[A-Za-z]*|HomeSharing|CloudMusic|AppleMediaServices"#
              + #"|TV|Podcasts)"#,
        options: .caseInsensitive
    )

    func testNoMusicDomainIsReadWithoutOptIn() throws {
        // takeLiveSnapshot inherits this process's environment, which does not set
        // SETSHOT_CHECK_MUSIC — the same state as a user who has not opted in.
        XCTAssertNil(ProcessInfo.processInfo.environment["SETSHOT_CHECK_MUSIC"],
                     "This test is only meaningful without the opt-in set")

        // Only the live snapshot, taken by this process with a known environment. The
        // base fixtures were captured with media access deliberately enabled, so they
        // contain those domains by design.
        for analysis in try allAnalyses() where analysis.isLive {
            for section in analysis.sections {
                for line in section.dataLines {
                    // Only the part before "::" is a path the script opened; a music
                    // bundle ID appearing as a value is another file's content.
                    guard let sep = line.range(of: " :: ") else { continue }
                    let source = String(line[line.startIndex..<sep.lowerBound])
                    let ns = source as NSString
                    XCTAssertNil(
                        Self.musicDomainPattern.firstMatch(
                            in: source, range: NSRange(location: 0, length: ns.length)),
                        """
                        [\(analysis.name)] \(section.name) read a media domain without \
                        the opt-in, which can trigger the Media & Apple Music dialog:
                        \(source)
                        """
                    )
                }
            }
        }
    }

    func testNoPrivacyDataIsCapturedWithoutFullDiskAccess() throws {
        for analysis in try allAnalyses() where analysis.raw.contains("TCC :: available = 0") {
            let leaked = analysis.raw
                .components(separatedBy: "\n")
                .filter { $0.hasPrefix("TCC-user ::") || $0.hasPrefix("TCC-system ::") }
            XCTAssertTrue(leaked.isEmpty, """
                [\(analysis.name)] reports the privacy databases as unreadable but still \
                captured \(leaked.count) row(s) from them.
                """)
        }
    }

    // MARK: - Power profiles

    /// `pmset -g` reports only whichever power profile is live, so on a laptop every
    /// energy setting that differs between battery and the power adapter changed the
    /// moment the power cord came out. The script uses `pmset -g custom`, which lists
    /// both profiles and so does not move with the power source. This asserts the
    /// shape that guarantees it: every pmset line names its profile.
    func testEveryPmsetLineNamesItsPowerProfile() throws {
        for analysis in try allAnalyses() where analysis.isLive {
            let lines = analysis.raw
                .components(separatedBy: "\n")
                .filter { $0.hasPrefix("pmset :: ") }

            XCTAssertFalse(lines.isEmpty, "[\(analysis.name)] captured no pmset lines at all.")

            let unprefixed = lines.filter {
                !$0.hasPrefix("pmset :: AC Power.") && !$0.hasPrefix("pmset :: Battery Power.")
            }
            XCTAssertTrue(unprefixed.isEmpty, """
                [\(analysis.name)] \(unprefixed.count) pmset line(s) carry no power profile, \
                so they track whichever profile is live and will appear to change when the \
                Mac is plugged in or unplugged. Examples:
                \(unprefixed.prefix(3).map { "      \($0)" }.joined(separator: "\n"))
                """)

            XCTAssertTrue(lines.contains { $0.hasPrefix("pmset :: AC Power.") },
                          "[\(analysis.name)] captured no AC Power profile.")

            // Desktop Macs get no Battery Power section, which is the point: the keys
            // are absent rather than needing to be filtered out afterwards.
            let battery = lines.contains { $0.hasPrefix("pmset :: Battery Power.") }
            XCTAssertEqual(battery, SnapshotRunner.hasBattery, """
                [\(analysis.name)] pmset \(battery ? "reported" : "did not report") a Battery \
                Power profile on a Mac that \(SnapshotRunner.hasBattery ? "has" : "has no") battery.
                """)
        }
    }

    // MARK: - Network connection services

    /// A user installed Tailscale and saw nothing about the VPN it adds:
    /// `networksetup -listallnetworkservices` lists hardware services, so a VPN
    /// installed by software was invisible. A Mac with no services emits the
    /// empty-state sentinel instead, which is why this section is not in
    /// sectionsThatMustHaveData.
    func testNetworkConnectionServicesAreCapturedInAReadableShape() throws {
        for analysis in try allAnalyses() where analysis.isLive {
            let lines = analysis.raw
                .components(separatedBy: "\n")
                .filter { $0.hasPrefix("netconnection :: ") }

            XCTAssertFalse(lines.isEmpty,
                           "[\(analysis.name)] captured nothing for network connection "
                           + "services, not even the empty-state sentinel.")
            if lines == ["netconnection :: (none configured)"] { continue }

            for line in lines {
                XCTAssertTrue(TestSupport.isParseable(line), """
                    [\(analysis.name)] "\(line)" cannot be parsed, so a VPN appearing \
                    would never reach a comparison.
                    """)
                // "enabled" or "disabled", optionally followed by the kind in brackets.
                let value = line.components(separatedBy: " = ").last ?? ""
                let state = value.components(separatedBy: " (").first ?? ""
                XCTAssertTrue(["enabled", "disabled"].contains(state), """
                    [\(analysis.name)] "\(line)" starts its value with "\(state)". Only \
                    the name, the leading asterisk and the trailing bracket are meant to \
                    be read from scutil; anything else means the output format moved.
                    """)
            }
        }
    }

    /// scutil lists network connection services, of which VPNs are only a subset —
    /// a 2020 iMac reported an ESP32 dev board as "USB JTAG/serial debug unit"
    /// [PPP:Modem]. Calling every one of them a VPN raised a false security alarm,
    /// so the kind travels with the value.
    ///
    /// Runs the script's own awk program, lifted out of setshot.sh, against captured
    /// output from two Macs. A live Mac may have no services at all, so this is the
    /// only thing that exercises the parse.
    func testTheKindIsReadFromTheTrailingBracketNotTheTypeField() throws {
        let script = try String(contentsOf: TestSupport.scriptURL, encoding: .utf8)
        guard let open = script.range(of: "scutil --nc list 2>/dev/null | awk '"),
              let close = script.range(of: "')", range: open.upperBound..<script.endIndex)
        else { return XCTFail("Could not find the scutil awk program in setshot.sh") }
        let program = String(script[open.upperBound..<close.lowerBound])

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let programURL = dir.appendingPathComponent("nc.awk")
        let sampleURL = dir.appendingPathComponent("nc.txt")
        try program.write(to: programURL, atomically: true, encoding: .utf8)

        // Line 2 is verbatim from a 2020 iMac on macOS 15.7. The type field before the
        // name is prose and repeats the device name, which is why the kind has to come
        // from the trailing bracket.
        try """
            Available network connection services in the current set (*=enabled):
            * (Disconnected)   B44D65CF-5842-4E0A-BBD3-32BC90572082 PPP --> USB JTAG/serial debug unit "USB JTAG/serial debug unit"     [PPP:Modem]
            * (Connected)      9E7F1A2B-1234-4567-89AB-CDEF012345AB VPN "Tailscale"     [VPN:com.tailscale.ipn.macsys]
              (Connected)      1A2B3C4D-1234-4567-89AB-CDEF012345AB IPSec "Home"     [IPSec]
            * (Disconnected)   5555AAAA-1234-4567-89AB-CDEF012345AB PPP --> Ethernet "No Bracket"
            """.write(to: sampleURL, atomically: true, encoding: .utf8)

        let result = try TestSupport.run("/usr/bin/awk", ["-f", programURL.path, sampleURL.path])
        XCTAssertEqual(result.output.trimmingCharacters(in: .whitespacesAndNewlines), """
            netconnection :: USB JTAG/serial debug unit = enabled (PPP:Modem)
            netconnection :: Tailscale = enabled (VPN:com.tailscale.ipn.macsys)
            netconnection :: Home = disabled (IPSec)
            netconnection :: No Bracket = enabled
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

        // legacyFixtureSections exempts the fixtures and nothing else, so unlike the
        // two lists above it has to be judged against the fixtures. `judged` drops
        // them whenever a live snapshot exists, and the live snapshot is never
        // exempted by this list, so judging it there would call every entry stale.
        //
        // An entry earns its place only while some fixture section still trips one of
        // the three checks it waives, so all three are re-evaluated here.
        for (prefix, _) in KnownIssues.legacyFixtureSections {
            var present = false
            var stillNeeded = false
            for analysis in analyses where !analysis.isLive {
                for section in analysis.sections where section.name.hasPrefix(prefix) {
                    present = true
                    let mustHaveData = KnownIssues.sectionsThatMustHaveData
                        .contains { section.name.hasPrefix($0) }
                    let unparseable = !analysis.unparseableLines(in: section).isEmpty
                    let invisible = !section.dataLines.isEmpty
                        && analysis.visibleLines(in: section).isEmpty
                    let missingData = mustHaveData && section.dataLines.isEmpty
                    if unparseable || invisible || missingData { stillNeeded = true }
                }
            }
            // A prefix matching no fixture section cannot be judged either way.
            if present && !stillNeeded {
                stale.append("""
                    KnownIssues.legacyFixtureSections["\(prefix)"] — the fixtures now pass \
                    every check it exempts.
                    """)
            }
        }

        XCTAssertTrue(stale.isEmpty, """
            Fixed bugs still listed in KnownIssues. Delete these lines:

            \(stale.joined(separator: "\n"))
            """)
    }
}
