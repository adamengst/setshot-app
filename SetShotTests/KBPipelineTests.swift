import XCTest
@testable import SetShot

/// Drives every knowledge base entry through the real pipeline — setshot.sh's own
/// noise filter, then DiffEngine's parser, then KB lookup — and asserts it comes
/// out the far end as a recognized change.
///
/// The KB and the shell noise filter are edited independently and have no shared
/// source of truth, so an entry can be written up with a description, a UI
/// location and a Settings URL while a `grep -vE` pattern quietly deletes the line
/// it describes. That is invisible until someone changes the setting and notices
/// SetShot said nothing.
final class KBPipelineTests: XCTestCase {

    private struct Probe {
        let entry: KBEntry
        let key: String
        let line: String
        var index: String { "\(entry.domain)::\(key)" }
    }

    /// Mirrors how each source actually appears in a snapshot: `defaults` and
    /// `plist` entries surface as flattened file paths, everything else as
    /// `<source> :: <key> = <value>`.
    private func probes(for entries: [KBEntry]) -> [Probe] {
        var seen = Set<String>()
        var probes: [Probe] = []

        for entry in entries where !entry.noise {
            let key: String
            if !entry.key.isEmpty {
                key = entry.key
            } else if let prefix = entry.keyPrefix, !prefix.isEmpty {
                key = prefix + "0"
            } else {
                continue   // unmatchable by construction — see testEveryEntryIsMatchable
            }

            let probe = Probe(entry: entry, key: key, line: "")
            guard seen.insert(probe.index).inserted else { continue }

            let prefix: String
            switch entry.source {
            case "defaults", "plist":
                prefix = "/Users/test/Library/Preferences/\(entry.domain).plist"
            default:
                prefix = entry.domain
            }
            probes.append(Probe(entry: entry, key: key, line: "\(prefix) :: \(key)"))
        }
        return probes
    }

    /// `context` lines appear unchanged in both snapshots, for probes that need
    /// surrounding state to be read correctly.
    private func runPipeline(_ probes: [Probe], kb: KnowledgeBase,
                             context: [String] = []) throws -> DiffResult {
        let fixed = context.joined(separator: "\n")
        let before = (probes.map { "\($0.line) = setshot-probe-before" } + [fixed])
            .joined(separator: "\n")
        let after = (probes.map { "\($0.line) = setshot-probe-after" } + [fixed])
            .joined(separator: "\n")
        let diff = try TestSupport.runScriptDiff(before: before, after: after)
        return DiffEngine().parse(diffOutput: diff, kb: kb)
    }

    // MARK: - Tests

    func testEveryNonNoiseEntryReachesTheUI() throws {
        let entries = try TestSupport.requireKnowledgeBase()
        let kb = KnowledgeBase(entries: entries, version: 0, updatedAt: nil)
        let probes = probes(for: entries)
        XCTAssertFalse(probes.isEmpty, "No probes built — is the KB empty?")

        // Privacy permission rows have to be probed separately, with `TCC :: available`
        // held steady. DiffEngine drops those rows when availability changes, since a
        // Full Disk Access grant makes every one of them appear at once — and the probe
        // set, which changes every value it touches, would otherwise trigger exactly that.
        let tccRows = probes.filter { $0.entry.domain.hasPrefix("TCC-") }
        let rest = probes.filter { !$0.entry.domain.hasPrefix("TCC-") }

        let results = [
            try runPipeline(rest, kb: kb),
            try runPipeline(tccRows, kb: kb, context: ["TCC :: available = 1"]),
        ]

        var recognized: [String: String] = [:]   // index -> matched entry id
        var classifiedNoise: [String: String] = [:]
        var unrecognized = Set<String>()
        for result in results {
            for (entry, diff) in result.recognized { recognized["\(diff.domain)::\(diff.key)"] = entry.id }
            for (entry, diff) in result.noise { classifiedNoise["\(diff.domain)::\(diff.key)"] = entry.id }
            unrecognized.formUnion(result.unrecognized.map { "\($0.domain)::\($0.key)" })
        }

        var failures: [String] = []
        var stale: [String] = []

        for probe in probes {
            let known = KnownIssues.kbEntriesShadowedByNoiseFilter[probe.entry.id]

            if let matchedID = recognized[probe.index] {
                if known != nil {
                    stale.append("""
                        KnownIssues.kbEntriesShadowedByNoiseFilter["\(probe.entry.id)"] — \
                        this entry is reported now. Delete the line.
                        """)
                }
                if matchedID != probe.entry.id {
                    failures.append("""
                        \(probe.entry.id): matched the wrong KB entry (\(matchedID)). \
                        KnowledgeBase.entry(forDomain:key:) returns the first match, so an \
                        earlier entry in the same domain with a broader key_prefix wins.
                        """)
                }
                continue
            }

            guard known == nil else { continue }   // known bug, already catalogued

            if let noiseID = classifiedNoise[probe.index] {
                failures.append("""
                    \(probe.entry.id) (\(probe.entry.domain) :: \(probe.key)): described as a \
                    setting but classified as noise by KB entry \(noiseID).
                    """)
            } else if unrecognized.contains(probe.index) {
                failures.append("""
                    \(probe.entry.id) (\(probe.entry.domain) :: \(probe.key)): survived the \
                    noise filter but KB lookup missed it — check domain and key spelling.
                    """)
            } else {
                failures.append("""
                    \(probe.entry.id) (\(probe.entry.domain) :: \(probe.key)): removed by \
                    setshot.sh's NOISE_PATTERN before DiffEngine saw it. The entry has a \
                    description and a UI location but can never be reported.
                    """)
            }
        }

        XCTAssertTrue(failures.isEmpty, """
            KB entries that cannot reach the UI (\(failures.count) of \(probes.count)):

            \(failures.joined(separator: "\n\n"))
            """)

        XCTAssertTrue(stale.isEmpty, """
            Fixed bugs still listed in KnownIssues:

            \(stale.joined(separator: "\n"))
            """)
    }

    func testEveryEntryIsMatchable() throws {
        let entries = try TestSupport.requireKnowledgeBase()

        // KnowledgeBase matches on an exact key or a keyPrefix. An empty key with a
        // nil keyPrefix satisfies neither: "" never equals a real key, and there is
        // no prefix to test. `key_prefix: ""` is the working form for a domain-wide
        // rule — hasPrefix("") is true for every key.
        let unmatchable = entries
            .filter { $0.key.isEmpty && $0.keyPrefix == nil }
            .map(\.id)
            .sorted()

        XCTAssertTrue(unmatchable.isEmpty, """
            KB entries that can never match anything — empty key and null key_prefix. \
            Set "key_prefix": "" to make them domain-wide rules:

            \(unmatchable.joined(separator: "\n"))
            """)
    }

    func testNoEntryIsBothKeySpecificAndDomainWide() throws {
        let entries = try TestSupport.requireKnowledgeBase()

        // An entry naming a specific key while also carrying `key_prefix: ""` reads
        // as a single-key rule and behaves as a domain-wide one. Lookup now prefers
        // exact matches, so this no longer hides described settings outright — but it
        // still makes the entry silently govern every unlisted key in its domain,
        // which for com.apple.finder, com.apple.dock and NSGlobalDomain means any
        // newly added setting in those domains inherits the wrong classification.
        let confused = entries
            .filter { !$0.key.isEmpty && $0.keyPrefix == "" }
            .map { "\($0.id) (\($0.domain) :: \($0.key))" }
            .sorted()

        XCTAssertTrue(confused.isEmpty, """
            KB entries that name a key but also claim the whole domain. Set \
            "key_prefix": null to make them apply to their key alone:

            \(confused.joined(separator: "\n"))
            """)
    }

    func testSpecificEntriesOutrankDomainWideRules() throws {
        let entries = try TestSupport.requireKnowledgeBase()
        let kb = KnowledgeBase(entries: entries, version: 0, updatedAt: nil)

        // Every described setting must win its own lookup, whatever else covers its
        // domain and wherever it sits in the file.
        var wrong: [String] = []
        for entry in entries where !entry.noise && !entry.key.isEmpty {
            let matched = kb.entry(forDomain: entry.domain, key: entry.key)
            guard matched?.id != entry.id else { continue }
            wrong.append("""
                \(entry.id) (\(entry.domain) :: \(entry.key)) resolves to \
                \(matched?.id ?? "no entry")\(matched?.noise == true ? " — reported as noise" : "").
                """)
        }

        XCTAssertTrue(wrong.isEmpty, """
            Described settings that lose their own lookup (\(wrong.count)):

            \(wrong.joined(separator: "\n\n"))
            """)
    }

    func testNoiseFilterPatternsAreValidRegexes() throws {
        // A malformed alternative in NOISE_PATTERN would make grep -E reject the whole
        // filter, and `|| true` in do_diff would swallow the error — every noise line
        // would flood the results with no indication why.
        let result = try TestSupport.run("/bin/bash", ["-c", """
            set -o pipefail
            printf 'probe :: key = value\\n' | grep -vE "$(
              sed -n '/^NOISE_PATTERN=/,/^)'"'"'$/p' '\(TestSupport.scriptURL.path)' \
              | sed "s/^NOISE_PATTERN='//; s/^[[:space:]]*//" \
              | grep -v '^#' | tr -d '\\n' | sed "s/|)/)/g; s/'$//"
            )" >/dev/null
            echo OK
            """])
        XCTAssertTrue(result.output.contains("OK"),
                      "NOISE_PATTERN did not compile as a POSIX ERE:\n\(result.output)")
    }
}
