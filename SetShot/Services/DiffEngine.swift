import Foundation

struct DiffEngine {
    private static let diffLineRegex = try! NSRegularExpression(
        pattern: #"^([+-])(.*?)\s*::\s*(.*?)\s*=\s*(.*)$"#
    )
    private static let uuidSuffixRegex = try! NSRegularExpression(
        pattern: #"\.[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$"#,
        options: .caseInsensitive
    )
    // Matches CFKeyedArchiverUID values emitted by old snapshots (before PlistFlattener
    // suppressed $-prefixed keys). These are process-local memory addresses, not settings.
    private static let uidValueRegex = try! NSRegularExpression(
        pattern: #"^<CFKeyedArchiverUID "#
    )

    func diff(before: Snapshot, after: Snapshot, kb: KnowledgeBase) async throws -> DiffResult {
        guard let bundledScript = Bundle.main.url(forResource: "setshot", withExtension: "sh") else {
            throw SnapshotError.scriptNotFound
        }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let scriptCopy = tempDir.appendingPathComponent("setshot.sh")
        let beforeFile = tempDir.appendingPathComponent("before.txt")
        let afterFile = tempDir.appendingPathComponent("after.txt")

        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try FileManager.default.copyItem(at: bundledScript, to: scriptCopy)
        try before.rawOutput.write(to: beforeFile, atomically: true, encoding: .utf8)
        try after.rawOutput.write(to: afterFile, atomically: true, encoding: .utf8)

        let diffOutput = try await captureProcess(
            executable: "/bin/bash",
            arguments: [scriptCopy.path, "diff", beforeFile.path, afterFile.path]
        )

        let parsed = parse(diffOutput: diffOutput, kb: kb,
                           beforeSnapshot: before.rawOutput, afterSnapshot: after.rawOutput)

        // `TCC :: available = 0` marks a snapshot taken without Full Disk Access. The
        // previous check looked for a "grant Full Disk Access to SetShot" string that
        // the script only wrote when it already had access, so it never fired.
        let beforeLimited = before.rawOutput.contains("TCC :: available = 0")
        let afterLimited = after.rawOutput.contains("TCC :: available = 0")
        // A format change alters what is captured, so a comparison across one shows
        // renamed and restructured keys as though they were settings that changed.
        // This has to outrank the Full Disk Access warning below, which it explains:
        // an older snapshot has no `TCC :: available` line, and its absence otherwise
        // reads as access having been lost.
        let beforeFormat = Self.snapshotFormat(of: before.rawOutput)
        let afterFormat = Self.snapshotFormat(of: after.rawOutput)

        let warning: String?
        if beforeFormat != afterFormat {
            let older = min(beforeFormat, afterFormat) == beforeFormat ? "before" : "after"
            warning = "These snapshots were taken by different versions of SetShot, which "
                + "capture settings differently (format \(beforeFormat) and \(afterFormat)). "
                + "Some of the changes below are the \(older) snapshot recording the same "
                + "settings in an older way rather than anything on this Mac changing. For a "
                + "clean comparison, use two snapshots taken by the same version."
        } else if let visibilityChange = parsed.limitedAccessWarning {
            warning = visibilityChange
        } else if beforeLimited && afterLimited {
            warning = "Both snapshots were taken without Full Disk Access for SetShot \u{2014} privacy permission data and some app preferences are missing from both."
        } else if beforeLimited {
            warning = "The before snapshot was taken without Full Disk Access for SetShot. Settings from some apps (Music, TV, Messages, etc.) and privacy permissions are absent, which may cause false added changes in the results. Grant SetShot Full Disk Access in System Settings \u{2192} Privacy & Security \u{2192} Full Disk Access, then retake the snapshot."
        } else if afterLimited {
            warning = "The after snapshot was taken without Full Disk Access for SetShot. Settings from some apps (Music, TV, Messages, etc.) and privacy permissions are absent, which may cause false deleted changes in the results. Grant SetShot Full Disk Access in System Settings \u{2192} Privacy & Security \u{2192} Full Disk Access, then retake the snapshot."
        } else {
            // Detect snapshots where many plist files were briefly locked or unavailable,
            // causing recognized settings to appear deleted. Threshold: 5+ deletions and
            // more than half of all recognized changes are values disappearing.
            let deletedCount = parsed.recognized.filter { $0.diff.afterValue.isEmpty }.count
            let total = parsed.recognized.count
            if deletedCount >= 5 && total > 0 && deletedCount * 2 > total {
                warning = "The after snapshot appears incomplete \u{2014} \(deletedCount) of \(total) recognized settings show a value disappearing. This can happen when preferences files are briefly locked or unavailable during a snapshot (for example, right after a reboot). Consider retaking the snapshot."
            } else {
                warning = nil
            }
        }

        return DiffResult(recognized: parsed.recognized, unrecognized: parsed.unrecognized,
                          noise: parsed.noise, unrecognizedOverflow: parsed.unrecognizedOverflow,
                          limitedAccessWarning: warning)
    }

    // Caps to prevent UI hangs when comparing snapshots across major version
    // boundaries (e.g. a snapshot taken before a domain filter change vs. after).
    private static let maxValueLength = 500
    private static let maxUnrecognized = 500


    /// The capture format a snapshot was written in. Snapshots taken before the
    /// header carried one are format 1.
    static func snapshotFormat(of snapshot: String) -> Int {
        for line in snapshot.components(separatedBy: "\n").prefix(12) {
            guard line.hasPrefix("Format:") else { continue }
            let digits = line.dropFirst("Format:".count)
                .drop(while: { !$0.isNumber })
                .prefix(while: { $0.isNumber })
            return Int(digits) ?? 1
        }
        return 1
    }

    /// Reads a key's value straight out of a snapshot, for values the display needs
    /// even when they did not change and so never appear in the diff.
    private static func value(ofKey key: String, inDomain domain: String,
                              from snapshot: String) -> String? {
        guard !snapshot.isEmpty else { return nil }
        for line in snapshot.components(separatedBy: "\n") {
            guard line.contains(domain), let range = line.range(of: " :: \(key) = ") else { continue }
            return String(line[range.upperBound...])
        }
        return nil
    }

    func parse(diffOutput: String, kb: KnowledgeBase,
               beforeSnapshot: String = "", afterSnapshot: String = "") -> DiffResult {
        let beforeFinderTarget = Self.value(ofKey: "NewWindowTargetPath",
                                            inDomain: "com.apple.finder", from: beforeSnapshot)
        let afterFinderTarget = Self.value(ofKey: "NewWindowTargetPath",
                                           inDomain: "com.apple.finder", from: afterSnapshot)

        let macOSVersion: String = {
            let v = ProcessInfo.processInfo.operatingSystemVersion
            return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
        }()

        struct Pair {
            var domain: String
            var key: String
            var rawDomain: String
            var before: String?
            var after: String?
        }
        var pairs: [Pair] = []
        var index: [String: Int] = [:]

        for line in diffOutput.components(separatedBy: "\n") {
            let ns = line as NSString
            guard let match = Self.diffLineRegex.firstMatch(
                in: line, range: NSRange(location: 0, length: ns.length)
            ) else { continue }

            func capture(_ i: Int) -> String { ns.substring(with: match.range(at: i)) }

            let sign = capture(1)
            let rawDomain = capture(2)
            let key = capture(3)
            let rawValue = capture(4)
            let value = rawValue.count > Self.maxValueLength
                ? String(rawValue.prefix(Self.maxValueLength)) + "…"
                : rawValue
            let normDomain = normalizeDomain(rawDomain)
            let pairKey = "\(normDomain)::\(key)"

            if let idx = index[pairKey] {
                if sign == "+" {
                    pairs[idx].after = value
                } else {
                    pairs[idx].before = value
                }
            } else {
                index[pairKey] = pairs.count
                var p = Pair(domain: normDomain, key: key, rawDomain: rawDomain)
                if sign == "-" { p.before = value } else { p.after = value }
                pairs.append(p)
            }
        }

        var recognized: [(entry: KBEntry, diff: DiffLine)] = []
        var unrecognized: [DiffLine] = []
        var noise: [(entry: KBEntry, diff: DiffLine)] = []

        // Reading the privacy databases requires Full Disk Access, so granting or
        // revoking it changes what SetShot can see rather than what is set. Every
        // grant on the Mac would otherwise appear as added or deleted at once,
        // burying whatever actually changed. Report the capability change instead.
        var tccVisibilityWarning: String?
        // An absent value means the snapshot predates TCC capture entirely, which is
        // the same situation as not being able to read the databases — so treat it as
        // "not readable" rather than skipping the check. Without this, comparing any
        // older snapshot against a new one with Full Disk Access floods the results
        // with every grant on the Mac, which is the case this exists to prevent.
        if let availability = pairs.first(where: { $0.domain == "TCC" && $0.key == "available" }) {
            let before = availability.before ?? "0"
            let after = availability.after ?? "0"
            if before != after {
            let gained = after == "1"
            tccVisibilityWarning = gained
                ? "SetShot was granted Full Disk Access between these snapshots, so privacy "
                  + "permissions are visible in the later one and absent from the earlier one. "
                  + "Individual permissions are left out of these results because every one of "
                  + "them would show as newly added. Compare two snapshots taken with Full Disk "
                  + "Access to see permission changes."
                : "SetShot lost Full Disk Access between these snapshots, so privacy permissions "
                  + "are missing from the later one. Individual permissions are left out of these "
                  + "results because every one of them would show as deleted."
            pairs.removeAll { $0.domain.hasPrefix("TCC-") }
            }
        }

        for p in pairs {
            let before = p.before ?? ""
            let after = p.after ?? ""
            guard semanticValue(before) != semanticValue(after) else { continue }
            // Suppress any diff where either value is a CFKeyedArchiverUID reference —
            // these are object-graph pointers that change every process launch.
            let isUID = { (v: String) in
                let ns = v as NSString
                return Self.uidValueRegex.firstMatch(in: v, range: NSRange(location: 0, length: ns.length)) != nil
            }
            guard !isUID(before) && !isUID(after) else { continue }
            if let entry = kb.entry(forDomain: p.domain, key: p.key) {
                let effectiveBefore = before.isEmpty ? (entry.implicitDefault ?? "") : before
                var diffLine = DiffLine(
                    domain: p.domain,
                    key: p.key,
                    source: inferSource(rawDomain: p.rawDomain),
                    beforeValue: effectiveBefore,
                    afterValue: after,
                    macOSVersion: macOSVersion,
                    rawLine: "\(p.rawDomain) :: \(p.key)"
                )
                if p.domain == "com.apple.finder" && p.key == "NewWindowTarget" {
                    diffLine.beforeDetail = beforeFinderTarget
                    diffLine.afterDetail = afterFinderTarget
                }
                if entry.noise {
                    noise.append((entry, diffLine))
                } else {
                    recognized.append((entry, diffLine))
                }
            } else {
                let diffLine = DiffLine(
                    domain: p.domain,
                    key: p.key,
                    source: inferSource(rawDomain: p.rawDomain),
                    beforeValue: before,
                    afterValue: after,
                    macOSVersion: macOSVersion,
                    rawLine: "\(p.rawDomain) :: \(p.key)"
                )
                unrecognized.append(diffLine)
            }
        }

        let overflow = max(0, unrecognized.count - Self.maxUnrecognized)
        if overflow > 0 { unrecognized = Array(unrecognized.prefix(Self.maxUnrecognized)) }

        recognized.sort { lhs, rhs in
            let lr = SettingsPaneOrder.rank(forSettingsURL: lhs.entry.settingsURL)
            let rr = SettingsPaneOrder.rank(forSettingsURL: rhs.entry.settingsURL)
            if lr != rr { return lr < rr }
            return (lhs.entry.description ?? "") < (rhs.entry.description ?? "")
        }

        return DiffResult(recognized: recognized, unrecognized: unrecognized, noise: noise,
                          unrecognizedOverflow: overflow, limitedAccessWarning: tccVisibilityWarning)
    }

    // True when every domain::key change in `ab` (the diff that justified keeping the
    // middle snapshot) is exactly undone in `bc` (the diff from that snapshot to the next
    // one) — i.e. the middle snapshot was a transient spike with no lasting effect. Extra
    // keys in `bc` beyond what `ab` touched are fine (they may be real, unrelated changes);
    // a key present in `ab` but missing or only partially reversed in `bc` fails the check.
    static func isFullReversal(of bc: DiffResult, reversing ab: DiffResult) -> Bool {
        func keyed(_ result: DiffResult) -> [String: DiffLine] {
            var map: [String: DiffLine] = [:]
            for item in result.recognized { map["\(item.diff.domain)::\(item.diff.key)"] = item.diff }
            for diffLine in result.unrecognized { map["\(diffLine.domain)::\(diffLine.key)"] = diffLine }
            return map
        }
        let abMap = keyed(ab)
        guard !abMap.isEmpty else { return false }
        let bcMap = keyed(bc)
        return abMap.allSatisfy { key, abDiff in
            guard let bcDiff = bcMap[key] else { return false }
            return bcDiff.afterValue == abDiff.beforeValue
        }
    }

    private func normalizeDomain(_ raw: String) -> String {
        var domain = raw
        if domain.contains("/") {
            domain = URL(fileURLWithPath: domain).lastPathComponent
        }
        // Strip .plist before UUID: ByHost filenames are "com.apple.foo.UUID.plist",
        // and the UUID regex anchors at $, so it won't match when .plist trails.
        if domain.hasSuffix(".plist") {
            domain = String(domain.dropLast(6))
        }
        let ns = domain as NSString
        let range = NSRange(location: 0, length: ns.length)
        domain = Self.uuidSuffixRegex.stringByReplacingMatches(
            in: domain, range: range, withTemplate: ""
        )
        if domain == ".GlobalPreferences" {
            domain = "NSGlobalDomain"
        }
        return domain
    }

    private func semanticValue(_ value: String) -> String {
        switch value.lowercased() {
        case "true", "yes", "1": return "1"
        case "false", "no", "0": return "0"
        default: return value
        }
    }

    private func inferSource(rawDomain: String) -> String {
        if rawDomain.contains("TCC") { return "tcc" }
        if rawDomain.contains("/") { return "plist" }
        let lower = rawDomain.lowercased()
        if lower.contains("scutil") { return "scutil" }
        if lower.contains("pmset") { return "pmset" }
        if lower.contains("networksetup") { return "networksetup" }
        if lower.contains("systemsetup") { return "systemsetup" }
        return "defaults"
    }

    // Write stdout to a temp file rather than a Pipe to avoid the 64 KB pipe
    // buffer deadlock: large diff output would block the process before it
    // terminates, so the termination handler would never fire.
    private func captureProcess(executable: String, arguments: [String]) async throws -> String {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".txt")
        FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: outputURL) }
        return try await withCheckedThrowingContinuation { continuation in
            do {
                let outHandle = try FileHandle(forWritingTo: outputURL)
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments
                process.standardOutput = outHandle
                process.standardError = FileHandle.nullDevice
                process.terminationHandler = { _ in
                    try? outHandle.close()
                    let text = (try? String(contentsOf: outputURL, encoding: .utf8)) ?? ""
                    continuation.resume(returning: text)
                }
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}


