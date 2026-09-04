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
            // Names the releases each format belongs to, so this needs revisiting
            // whenever SNAPSHOT_FORMAT is bumped in setshot.sh.
            warning = "These snapshots were taken by different versions of SetShot, which "
                + "capture settings differently (format 1 from b26 and earlier and format 2 "
                + "from b27 and later). Some of the changes below are the Before snapshot "
                + "recording the same settings in an older way rather than anything on this "
                + "Mac changing. For a clean comparison, use two snapshots taken by the same "
                + "version."
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

        /// A pair that exists on one side only, in a domain Media & Apple Music gates.
        /// Anything else is a difference in the settings and is left alone.
        func isMediaVisibilityArtefact(_ pair: Pair) -> Bool {
            guard (pair.before ?? "").isEmpty || (pair.after ?? "").isEmpty else { return false }
            return Self.mediaGatedDomainsInclude(pair.domain)
        }

        // Media & Apple Music gates the media domains the same way Full Disk Access
        // gates the privacy databases: without it those domains are skipped and their
        // settings vanish from the snapshot. Both sides must carry the marker — a
        // snapshot taken before it existed says nothing about what was captured, and
        // assuming it was off would invent a change.
        if let media = pairs.first(where: { $0.domain == "Music" && $0.key == "available" }),
           let mediaBefore = media.before, let mediaAfter = media.after,
           mediaBefore != mediaAfter {
            let turnedOn = mediaAfter == "1"
            let side = turnedOn ? "earlier" : "later"
            tccVisibilityWarning = "Media & Apple Music access was turned "
                + (turnedOn ? "on" : "off") + " between these snapshots, so the Music, TV and "
                + "related settings could not be read for the \(side) one. Anything that appears "
                + "in only one of the two is left out of these results, because it reflects what "
                + "SetShot could read rather than anything that changed."
            pairs.removeAll { pair in
                if pair.domain == "Music" && pair.key == "available" { return false }
                return isMediaVisibilityArtefact(pair)
            }

            // The permission SetShot holds is recorded twice: once as the marker above,
            // and once as SetShot's own row in the TCC database like any other app. Both
            // describe the same grant, so reporting both says one change twice.
            //
            // Which one survived used to depend on the direction. Granting access creates
            // the TCC row, so it arrives with nothing on its earlier side and the removal
            // above takes it, leaving one row; revoking flips an existing row from Allowed
            // to Denied, which has both sides and stays, leaving two. Dropping SetShot's
            // own row here makes both directions report one, and it is the marker that
            // remains -- it has a value on both sides whichever way the permission moved.
            //
            // Only SetShot's row. Every other app's Media & Apple Music grant is a setting
            // in its own right and is reported.
            if let ownBundleID = Bundle.main.bundleIdentifier {
                pairs.removeAll { pair in
                    pair.domain.hasPrefix("TCC-")
                        && pair.key == "kTCCServiceMediaLibrary/\(ownBundleID)"
                }
            }
        }

        // A TCC service that gained the app it names between the two captures.
        //
        // Automation records one grant per controlled app, and the capture used to record
        // only the app doing the controlling: six grants for one app read identically and
        // a comparison keyed them together, so revoking one of them reported nothing. The
        // capture now names both, which changes every one of those keys -- against a
        // snapshot taken before that, each grant looks newly added.
        //
        // Detected from the keys themselves rather than by bumping the snapshot format,
        // which would make every earlier snapshot an older format for every purpose over
        // one service's shape. This corrects itself: once both captures name the app, the
        // depths match and none of this runs.
        func tccKeyDepths(_ snapshot: String) -> [String: Set<Int>] {
            var depths: [String: Set<Int>] = [:]
            for line in snapshot.split(separator: "\n") where line.contains(" :: kTCCService") {
                guard let sep = line.range(of: " :: "),
                      let eq = line.range(of: " = ", range: sep.upperBound..<line.endIndex)
                else { continue }
                let key = line[sep.upperBound..<eq.lowerBound]
                let parts = key.split(separator: "/", omittingEmptySubsequences: false)
                guard let service = parts.first else { continue }
                depths[String(service), default: []].insert(parts.count)
            }
            return depths
        }
        var reshapedServices: Set<String> = []
        if !beforeSnapshot.isEmpty && !afterSnapshot.isEmpty {
            let before = tccKeyDepths(beforeSnapshot), after = tccKeyDepths(afterSnapshot)
            for (service, beforeDepths) in before {
                guard let afterDepths = after[service] else { continue }
                if beforeDepths.isDisjoint(with: afterDepths) { reshapedServices.insert(service) }
            }
        }
        if !reshapedServices.isEmpty {
            let names = reshapedServices.map { $0.replacingOccurrences(of: "kTCCService", with: "") }
                .sorted().joined(separator: ", ")
            tccVisibilityWarning = "SetShot now records which app each of these permissions lets "
                + "another app reach — \(names) — where before it recorded only the app holding "
                + "the permission. Those entries therefore look new when an older snapshot is on "
                + "the other side, and are left out of these results. Two snapshots taken by this "
                + "version compare normally."
            pairs.removeAll { pair in
                guard pair.domain.hasPrefix("TCC-") else { return false }
                guard let service = pair.key.split(separator: "/").first,
                      reshapedServices.contains(String(service)) else { return false }
                return (pair.before ?? "").isEmpty || (pair.after ?? "").isEmpty
            }
        }

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
                ? "SetShot was granted Full Disk Access between these snapshots, so for the "
                  + "earlier one it could not read privacy permissions, Messages, Contacts, "
                  + "Time Machine, Home, Focus, Wi-Fi networks this Mac has joined, or Mail. "
                  + "Anything from those that appears in only one of the two is left out of "
                  + "these results, because it reflects what SetShot could read rather than "
                  + "anything that changed. Compare two snapshots taken with Full Disk Access "
                  + "to see changes to them."
                : "SetShot lost Full Disk Access between these snapshots, so for the later one "
                  + "it could not read privacy permissions, Messages, Contacts, Time Machine, "
                  + "Home, Focus, Wi-Fi networks this Mac has joined, or Mail. Anything from "
                  + "those that appears in only one of the two is left out of these results, "
                  + "because it reflects what SetShot could read rather than anything that "
                  + "changed."
            // A value that exists on one side only, in one of those domains, is the
            // signature of a file that became readable or unreadable rather than of a
            // setting someone changed. Losing access made Time Machine look switched off
            // and Mail's settings look wiped. A genuine
            // change has a value on both sides and is kept.
            pairs.removeAll { pair in
                if pair.domain == "TCC" && pair.key == "available" { return false }
                // The privacy databases are read as a whole or not at all, so every row
                // in them is about what could be read whichever side it sits on.
                if pair.domain.hasPrefix("TCC-") { return true }
                guard (pair.before ?? "").isEmpty || (pair.after ?? "").isEmpty else { return false }
                return Self.fullDiskAccessGatedDomainsInclude(pair.domain)
            }
            }
        }

        // While a laptop runs on battery, macOS substitutes a still image for a
        // dynamic desktop or aerial and rewrites the SystemDefault entry to match,
        // switching it back on the power adapter. Unplugging therefore reported the
        // system default wallpaper changing, with nothing on screen having changed:
        // SystemDefault is the fallback for a display that has no choice of its own,
        // and once every display has one it is inert. Only suppressed when both
        // snapshots show per-display choices, so a Mac genuinely relying on the
        // fallback still reports it, and so does a change that removes the
        // per-display choices.
        func perDisplayWallpaperBranches(in snapshot: String) -> Set<String> {
            guard !snapshot.isEmpty else { return [] }
            var found: Set<String> = []
            for line in snapshot.components(separatedBy: "\n")
            where line.hasPrefix("wallpaper :: Spaces.") {
                if line.contains(".Desktop.Content.Choices") { found.insert("Desktop") }
                if line.contains(".Idle.Content.Choices") { found.insert("Idle") }
            }
            return found
        }
        let inertSystemDefaults = perDisplayWallpaperBranches(in: beforeSnapshot)
            .intersection(perDisplayWallpaperBranches(in: afterSnapshot))
        if !inertSystemDefaults.isEmpty {
            pairs.removeAll { pair in
                guard pair.domain == "wallpaper" else { return false }
                return inertSystemDefaults.contains {
                    pair.key.hasPrefix("SystemDefault.\($0).Content")
                }
            }
        }

        // A wallpaper choice names its content in exactly one of several shapes, and
        // which one depends on what was chosen: Configuration.assetID for an aerial or
        // dynamic desktop, Files[N].relative for a picture or a third-party .saver
        // bundle, Configuration.style for one of the built-in screen savers,
        // Configuration.module.relative for a screen saver supplied by a bundle.
        // Replacing one kind with another therefore arrived as two rows for one
        // choice — the old identifier disappearing and the new one appearing, each
        // with a blank on the other side. They are paired back into the single change
        // they describe, keeping the row that says what the choice is now and giving
        // it the identifier the old one carried.
        //
        // Runs before the per-Space collapse so a pair always comes from one Space's
        // own record: matching across Spaces would have to guess which Space's old
        // wallpaper the new one replaced. A solid colour uses a further shape
        // (Configuration.backgroundColor) and is not paired.
        var imageRowsByChoice: [String: [Int]] = [:]
        for (i, pair) in pairs.enumerated() where pair.domain == "wallpaper" {
            guard let leaf = pair.key.range(
                of: #"\.(Configuration\.assetID|Configuration\.style|Configuration\.module\.relative|Files\[\d+\]\.relative)$"#,
                options: .regularExpression) else { continue }
            imageRowsByChoice[String(pair.key[..<leaf.lowerBound]), default: []].append(i)
        }
        var pairedAway = Set<Int>()
        for (_, indices) in imageRowsByChoice where indices.count == 2 {
            func vanished(_ i: Int) -> Bool {
                !(pairs[i].before ?? "").isEmpty && (pairs[i].after ?? "").isEmpty
            }
            func appeared(_ i: Int) -> Bool {
                (pairs[i].before ?? "").isEmpty && !(pairs[i].after ?? "").isEmpty
            }
            let (first, second) = (indices[0], indices[1])
            let old: Int, new: Int
            if vanished(first), appeared(second) { old = first; new = second }
            else if vanished(second), appeared(first) { old = second; new = first }
            else { continue }
            // Configuration.style is an index into the built-in screen savers, and
            // nothing in the snapshot says which one it names. Carrying the number
            // across would put "0" on the left of the arrow; saying what kind of
            // thing it was at least reads.
            pairs[new].before = pairs[old].key.hasSuffix(".Configuration.style")
                ? "a built-in screen saver" : pairs[old].before
            pairedAway.insert(old)
        }
        if !pairedAway.isEmpty {
            pairs = pairs.enumerated().filter { !pairedAway.contains($0.offset) }.map(\.element)
        }

        // Wallpaper settings live at one of two scopes: AllSpacesAndDisplays while
        // every display shares a choice, and Spaces.<space>.Displays.<display> once
        // they have their own. Turning off "same on all displays" moves every value
        // from the first to the second, and each move arrived as two rows — one
        // saying the shared value went away, one saying the same value appeared for a
        // display — for a display whose wallpaper a user watching the screen would say
        // had not changed at all.
        //
        // Both halves are dropped when the effective value is the same on both sides.
        // What survives is the row for a display that landed on something different,
        // and, going the other way, the row saying every display now shares one
        // choice — the change the user made.
        func wallpaperLeaf(_ key: String) -> String? {
            for prefix in [#"^AllSpacesAndDisplays\."#,
                           #"^Spaces\.[^.]*\.Displays\.[^.]*\."#] {
                if let r = key.range(of: prefix, options: .regularExpression) {
                    return String(key[r.upperBound...])
                }
            }
            return nil
        }
        /// The shared value a leaf held in one snapshot, for comparing against what a
        /// per-display row now says.
        func sharedWallpaperValues(in snapshot: String) -> [String: String] {
            guard !snapshot.isEmpty else { return [:] }
            var found: [String: String] = [:]
            for line in snapshot.components(separatedBy: "\n")
            where line.hasPrefix("wallpaper :: AllSpacesAndDisplays.") {
                let body = line.dropFirst("wallpaper :: ".count)
                guard let split = body.range(of: " = "),
                      let leaf = wallpaperLeaf(String(body[..<split.lowerBound]))
                else { continue }
                found[leaf] = String(body[split.upperBound...])
            }
            return found
        }
        let sharedBefore = sharedWallpaperValues(in: beforeSnapshot)
        let sharedAfter = sharedWallpaperValues(in: afterSnapshot)
        let perDisplayAppeared = pairs.contains { pair in
            pair.domain == "wallpaper" && pair.key.hasPrefix("Spaces.")
                && (pair.before ?? "").isEmpty && !(pair.after ?? "").isEmpty
        }
        pairs.removeAll { pair in
            guard pair.domain == "wallpaper" else { return false }
            let before = pair.before ?? "", after = pair.after ?? ""
            // The shared value going away while displays take over. What each display
            // landed on is reported by its own row.
            if pair.key.hasPrefix("AllSpacesAndDisplays."),
               !before.isEmpty, after.isEmpty, perDisplayAppeared { return true }
            guard pair.key.hasPrefix("Spaces."), let leaf = wallpaperLeaf(pair.key)
            else { return false }
            // A display inheriting what it already had, either as it stops sharing or
            // as it starts.
            if before.isEmpty, !after.isEmpty { return sharedBefore[leaf] == after }
            if after.isEmpty, !before.isEmpty { return sharedAfter[leaf] == before }
            return false
        }

        // "Show on all Spaces" writes the same wallpaper into every Space, so one
        // change arrived as one row per Space — five identical "Wallpaper on Built-in
        // Display" rows for a single wallpaper. A Space is not something the wallpaper
        // is set for from the user's side, so rows that differ only by which Space
        // they came from, and that land on the same before and after, collapse to one.
        // Spaces that genuinely held different wallpapers still report separately,
        // because their before values differ.
        var seenAcrossSpaces = Set<String>()
        pairs.removeAll { pair in
            guard pair.domain == "wallpaper", pair.key.hasPrefix("Spaces.") else { return false }
            // The Space UUID is empty for the entry macOS writes as the default across
            // Spaces, so this also folds "Spaces..Displays.…" in with the rest.
            let withoutSpace = pair.key.replacingOccurrences(
                of: #"^Spaces\.[^.]*\."#, with: "Spaces.", options: .regularExpression)
            let identity = "\(withoutSpace)\u{0}\(pair.before ?? "")\u{0}\(pair.after ?? "")"
            return !seenAcrossSpaces.insert(identity).inserted
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

    /// The domains Full Disk Access gates.
    ///
    /// Read off two captures 33 seconds apart on one Mac, the permission granted for the
    /// first and revoked for the second and nothing else touched: fourteen domains
    /// disappeared entirely, 1273 lines, with none appearing and none partially read.
    /// The alternative was to guess, and guessing at the equivalent list for Media &
    /// Apple Music is what put settings it does not gate -- hot corners, Dock
    /// magnification -- behind a permission toggle.
    ///
    /// This is one Mac's answer. A domain that gates on some other Mac and is missing
    /// here will read as a settings change when the permission moves, which is the old
    /// symptom confined to that domain rather than applied to the whole comparison. Add
    /// to it from the same experiment rather than from reasoning about what sounds
    /// protected.
    static func fullDiskAccessGatedDomainsInclude(_ domain: String) -> Bool {
        // Focus is captured from ~/Library/DoNotDisturb/DB and carries that as its domain.
        let gated: Set<String> = [
            "DB",
            "com.apple.AddressBook",
            "com.apple.MobileSMS",
            "com.apple.MobileSMS.CKDNDList",
            "com.apple.TimeMachine",
            "com.apple.airport.preferences",
            "com.apple.homed",
            "com.apple.homed.notbackedup",
            "com.apple.madrid",
            "com.apple.mail-shared",
            "com.apple.messages.pinning",
        ]
        return gated.contains(domain)
    }

    /// The domains Media & Apple Music gates, mirroring _MUSIC_RE in setshot.sh — the
    /// list the capture itself uses to decide what to skip without that permission.
    /// MediaGatedDomainsTests runs every domain in the baselines past both and fails if
    /// they disagree, because two copies of one list drift silently otherwise.
    ///
    /// Derived from the permission rather than from the snapshots being compared.
    /// Looking at which domains vanished between the two seems equivalent and is not:
    /// against a bundled baseline, 504 domains are present on an ordinary Mac and absent
    /// from the VM the baseline came from, and treating those as unreadable suppresses
    /// settings no permission gates.
    static func mediaGatedDomainsInclude(_ domain: String) -> Bool {
        let d = domain.lowercased()
        guard d.hasPrefix("com.apple.") else { return false }
        let rest = String(d.dropFirst("com.apple.".count))
        let exact = ["music", "itunes", "itunesx", "icloud.music", "homesharing",
                     "cloudmusic", "applemediaservices", "personalaudio", "tv", "podcasts"]
        if exact.contains(where: { rest == $0 || rest.hasPrefix($0 + ".") }) { return true }
        // The open-ended alternatives in _MUSIC_RE: amp/AMP…, itunes…, media….
        return rest.hasPrefix("amp") || rest.hasPrefix("itunes") || rest.hasPrefix("media")
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
        let outHandle = try FileHandle(forWritingTo: outputURL)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = outHandle
        process.standardError = FileHandle.nullDevice
        return try await CancellableProcess.run(process) { _ in
            try? outHandle.close()
            return (try? String(contentsOf: outputURL, encoding: .utf8)) ?? ""
        }
    }
}


