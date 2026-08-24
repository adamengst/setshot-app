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
    static let sectionsWithUnparseableLines: [String: String] = [:]

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

        "APPLICATION HANDLERS":
            "Fixtures were captured while this section read the wrong path, so they "
            + "contain only its `(not found)` sentinel.",

        "LAUNCH AGENTS & DAEMONS":
            "Fixtures predate giving each item a value, so their lines have no `=`.",

        "TIME MACHINE":
            "Fixtures predate normalising tmutil's banner output to `destination[N].field`.",

        "SYSTEM EXTENSIONS":
            "Fixtures predate normalising systemextensionsctl output, so they contain its "
            + "raw \"0 extension(s)\" header.",

        "SYSTEM CONFIGURATION":
            "Fixtures predate normalising the scutil DNS and proxy blocks and the "
            + "networksetup service list.",

        "CONFIGURATION PROFILES":
            "Fixtures were captured while this section ran `profiles list -all`, so they "
            + "contain its root-privileges refusal as a data line.",
    ]

    /// Sources that genuinely need root, so the app — which never elevates — cannot
    /// read them. These are limitations rather than bugs: each now emits a sentinel
    /// saying so, instead of an empty section or a captured error message.
    ///
    /// - BACKGROUND TASK MANAGEMENT: `sfltool dumpbackgroundtaskmanagement` has no
    ///   root-free equivalent. The launchd half of what it reports is covered by
    ///   LAUNCH AGENTS & DAEMONS.
    /// - CONFIGURATION PROFILES: system-scope profiles need root. User-scope profiles
    ///   come from `profiles show`, and MDM-controlled domains from
    ///   /Library/Managed Preferences, both without root.
    static let rootOnlySources: Set<String> = [
        "BACKGROUND TASK MANAGEMENT",
        "CONFIGURATION PROFILES",
    ]

    // MARK: - Section visibility

    /// Sections where every captured line is either unparseable or removed by the
    /// shell noise filter, so the section can never contribute to a comparison.
    static let sectionsWithNoVisibleData: [String: String] = [:]

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
    static let sectionsMissingTheirSource: [String: String] = [:]

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

    /// Failure modes that only appear in a live capture, because the checked-in base
    /// snapshots happened to take a different code path through the same section.
    /// Staleness checks skip these when the live snapshot is not being taken.
    static let requiresLiveSnapshot: Set<String> = []

    static func reason(for section: String, in list: [String: String]) -> String? {
        list.first { section.hasPrefix($0.key) }?.value
    }
}
