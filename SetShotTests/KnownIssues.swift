import Foundation

/// Settings that SetShot captures but cannot surface, recorded so the contract
/// tests stay green while the backlog is worked through.
///
/// Every entry here is a bug, not an exemption. The tests fail if an allowlisted
/// item starts passing, so fixing one forces its line to be deleted — the list
/// cannot silently rot into a list of things nobody remembers.
enum KnownIssues {

    // MARK: - Snapshot line format

    /// Sections that emit at least one line DiffEngine's parser cannot read,
    /// because the line has no `::` or no `=`.
    ///
    /// Keys are section-name prefixes (section titles embed paths that change).
    static let sectionsWithUnparseableLines: [String: String] = [
        "SYSTEM CONFIGURATION":
            "`scutil --dns`, `scutil --proxy`, `networksetup -listallnetworkservices` and "
            + "`pmset` blocks are dumped verbatim instead of being normalised to "
            + "`domain :: key = value`.",

        "CONFIGURATION PROFILES":
            "`profiles list -all` needs root and writes `this command requires root "
            + "privileges` to stdout, so neither `2>/dev/null` nor the `||` fallback "
            + "catches it and the error text lands in the snapshot.",

        "LAUNCH AGENTS & DAEMONS":
            "Emitted as `<dir> :: <filename>` with no `=`, so an installed launch agent "
            + "or daemon never appears in a comparison.",

        "TIME MACHINE":
            "`tmutil destinationinfo` and `tmutil status` output is passed through raw.",

        "SYSTEM EXTENSIONS":
            "`systemextensionsctl list` output is passed through raw.",
    ]

    /// Sections whose emit format changed after the base snapshots were captured.
    /// The fixtures are frozen VM captures kept for users to compare against, not
    /// test data, so they cannot be regenerated to match. These exemptions apply to
    /// the fixtures only — the live snapshot is held to the current contract.
    static let legacyFixtureSections: [String: String] = [
        "SYSTEM STATE":
            "Fixtures predate the normalisation of SIP / Gatekeeper / FileVault / Firewall "
            + "to `domain :: key = value`, and still contain the raw `systemsetup` "
            + "\"You need administrator access\" lines.",

        "WALLPAPER":
            "Fixtures predate relabelling these lines from the Index.plist path to the "
            + "`wallpaper` domain, so the old blanket noise pattern still removes them.",
    ]

    // MARK: - Section visibility

    /// Sections where every captured line is either unparseable or removed by the
    /// shell noise filter, so the section can never contribute to a comparison.
    static let sectionsWithNoVisibleData: [String: String] = [
        "APPLICATION HANDLERS":
            "Reads ~/Library/Application Support/com.apple.LaunchServices/, but the file "
            + "lives in ~/Library/Preferences/com.apple.LaunchServices/. The awk block "
            + "that emits `default-browser :: handler = …` has never run. The general "
            + "plist scan does pick the file up, but `LaunchServices.*:: LSHandlers\\[` "
            + "removes those lines, so default browser and mail client are invisible "
            + "through both paths.",

        "CONFIGURATION PROFILES": "Needs root; the app never elevates.",

        "LAUNCH AGENTS & DAEMONS": "See sectionsWithUnparseableLines.",

        "TIME MACHINE": "See sectionsWithUnparseableLines.",

        "SYSTEM EXTENSIONS": "See sectionsWithUnparseableLines.",

        "BACKGROUND TASK MANAGEMENT":
            "`sfltool dumpbackgroundtaskmanagement` needs root. Output is discarded by "
            + "`2>/dev/null` with no fallback, so Login Items & Extensions is captured as "
            + "nothing at all — silently. The awk normaliser written for it never runs.",

    ]

    /// Sections that should produce settings data on any Mac. A section here that
    /// yields only an empty-state sentinel means its source could not be read.
    static let sectionsThatMustHaveData: Set<String> = [
        "NSGlobalDomain",
        "PLIST FILES: ~/Library/Preferences",
        "PLIST FILES: /Library/Preferences",
        "SYSTEM STATE",
        "SHARING SERVICES",
        "WALLPAPER",
        "APPLICATION HANDLERS",
        "SOUND (NVRAM)",
    ]

    /// Sections from `sectionsThatMustHaveData` that currently produce only a
    /// sentinel, because the source path is wrong or unreadable.
    static let sectionsMissingTheirSource: [String: String] = [
        "APPLICATION HANDLERS":
            "Wrong path — see sectionsWithNoVisibleData. Emits `(not found)` on every Mac.",
    ]

    // MARK: - Knowledge base

    /// Non-noise KB entries the shell noise filter removes before DiffEngine ever
    /// sees them. Each is a described, located setting that can never be reported.
    static let kbEntriesShadowedByNoiseFilter: [String: String] = [
        "finder.NewWindowTargetPath":
            "Killed by `finder.*:: NewWindowTargetPath\\s*=`. The filter says noise, the "
            + "KB says setting — one of the two is wrong.",

        "universalaccess.closeViewZoomFollowsFocus":
            "Collateral damage from `universalaccess.*:: closeViewZoom`, which was aimed "
            + "at closeViewZoomFactor / closeViewZoomedIn / closeViewZoomDisplayID churn.",

        "xpc-activity2-product-build-version":
            "Killed by the domain-wide `xpc\\.activity2\\.plist ::`. Harmless in practice "
            + "— `system :: macOSBuild` already reports the build number.",
    ]

    // MARK: - Lookup

    /// Failure modes that only appear in a live capture, because the checked-in
    /// base snapshots happened to take a different code path. Staleness checks skip
    /// these unless SETSHOT_LIVE_SNAPSHOT=1.
    static let requiresLiveSnapshot: Set<String> = []

    static func reason(for section: String, in list: [String: String]) -> String? {
        list.first { section.hasPrefix($0.key) }?.value
    }
}
