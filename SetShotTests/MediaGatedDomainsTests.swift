import XCTest
@testable import SetShot

/// The diff engine decides which domains Media & Apple Music gates so it can suppress
/// the rows that permission makes unreadable and leave everything else alone. The
/// capture makes the same decision from `_MUSIC_RE` in setshot.sh. Two copies of one
/// list, and the failure they invite is silent: a domain the script skips but the
/// engine does not know about reads as a settings change every time the permission is
/// toggled.
///
/// Rather than compare a Swift predicate against a shell regex directly, this runs
/// every domain in the bundled baselines past both and asserts they agree.
final class MediaGatedDomainsTests: XCTestCase {

    /// Lifted from setshot.sh, anchored the way _is_music_path applies it.
    private static let shellPattern = "/com\\.apple\\.(Music|iTunes|iTunesX|iCloud\\.Music|amp"
        + "|AMP[A-Za-z]+|itunes[a-z]*|media[A-Za-z]*|HomeSharing|CloudMusic"
        + "|AppleMediaServices|PersonalAudio|TV|Podcasts)"

    func testTheScriptsPatternIsStillWhatTheEngineMirrors() throws {
        let script = try String(contentsOf: TestSupport.scriptURL, encoding: .utf8)
        XCTAssertTrue(script.contains("_MUSIC_RE='" + Self.shellPattern.dropFirst() + "'"), """
            _MUSIC_RE in setshot.sh no longer matches the copy in this test. The diff \
            engine mirrors that list to decide what Media & Apple Music gates, so both \
            it and this test need updating together.
            """)
    }

    func testEngineAndScriptAgreeOnEveryDomainInTheBaselines() throws {
        let regex = try NSRegularExpression(pattern: Self.shellPattern, options: [.caseInsensitive])
        let bases = (try? FileManager.default.contentsOfDirectory(
            at: TestSupport.baseSnapshotsDir, includingPropertiesForKeys: nil)) ?? []
        var rawDomains: Set<String> = []
        for url in bases where url.pathExtension == "gz" {
            for line in try TestSupport.gunzip(url).split(separator: "\n") {
                guard let r = line.range(of: " :: ") else { continue }
                rawDomains.insert(String(line[line.startIndex..<r.lowerBound]))
            }
        }
        XCTAssertFalse(rawDomains.isEmpty, "No domains read from the baselines")

        var disagreements: [String] = []
        for raw in rawDomains.sorted() {
            let path = raw.hasPrefix("/") ? raw : "/" + raw
            let ns = path as NSString
            let shellGates = regex.firstMatch(
                in: path, range: NSRange(location: 0, length: ns.length)) != nil
            let engineGates = DiffEngine.mediaGatedDomainsInclude(normalizedDomain(raw))
            if shellGates != engineGates {
                disagreements.append("  \(raw)  script=\(shellGates) engine=\(engineGates)")
            }
        }
        XCTAssertTrue(disagreements.isEmpty, """
            \(disagreements.count) domain(s) where the capture and the diff engine \
            disagree about whether Media & Apple Music gates them:

            \(disagreements.prefix(15).joined(separator: "\n"))
            """)
    }

    /// The engine sees domains after normalization — basename, .plist and any ByHost
    /// UUID stripped — so the comparison has to use the same form.
    private func normalizedDomain(_ raw: String) -> String {
        var d = raw.contains("/") ? (raw as NSString).lastPathComponent : raw
        if d.hasSuffix(".plist") { d = String(d.dropLast(6)) }
        let ns = d as NSString
        let uuid = try! NSRegularExpression(
            pattern: #"\.[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$"#,
            options: .caseInsensitive)
        return uuid.stringByReplacingMatches(
            in: d, range: NSRange(location: 0, length: ns.length), withTemplate: "")
    }
}
