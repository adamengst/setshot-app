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

    /// Sections exempted for the base-snapshot fixtures only; the live snapshot is
    /// always held to the current contract.
    ///
    /// This list was long while the fixtures were June captures predating the format 2
    /// changes. They have since been recaptured on current macOS, and every entry that
    /// existed for a stale emit format is gone. What remains is not staleness: the
    /// fixtures come from pristine VMs, and a section that legitimately has no data on
    /// a clean install cannot be made to have any by recapturing.
    ///
    /// `testKnownIssuesAreStillIssues` re-evaluates all three waived checks against the
    /// fixtures, so an entry that stops being needed fails the suite rather than sitting
    /// here disabling its checks — which is how the previous eight accumulated.
    static let legacyFixtureSections: [String: String] = [
        "APPLICATION HANDLERS":
            "A pristine system records no LaunchServices handler overrides, so the "
            + "fixtures carry only this section's `(not found)` sentinel. On a Mac that "
            + "has ever changed a default browser or mail client the section has data, "
            + "which is why the live snapshot is still held to it.",
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
    /// sees them. Each would be a described, located setting that can never be
    /// reported — the KB calling something a setting while a `grep -vE` pattern
    /// deletes its line means one of the two is wrong.
    static let kbEntriesShadowedByNoiseFilter: [String: String] = [:]

    // MARK: - Lookup

    /// Failure modes that only appear in a live capture, because the checked-in base
    /// snapshots happened to take a different code path through the same section.
    /// Staleness checks skip these when the live snapshot is not being taken.
    static let requiresLiveSnapshot: Set<String> = []

    static func reason(for section: String, in list: [String: String]) -> String? {
        list.first { section.hasPrefix($0.key) }?.value
    }
}
