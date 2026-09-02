import XCTest
@testable import SetShot

final class DiffEngineTests: XCTestCase {

    private func makeEntry(domain: String, key: String = "", keyPrefix: String? = nil, noise: Bool = false) -> KBEntry {
        KBEntry(
            id: "\(domain).\(key)", domain: domain, key: key, source: "defaults",
            valueType: "string", description: "Test",
            uiLocation: nil, uiLocationOverrides: nil, settingsURL: nil,
            noise: noise, noiseReason: noise ? "test" : nil,
            minMacOS: "13.0", notes: nil, aiGenerated: false,
            contributedByIssue: nil, valueMap: nil, keyPrefix: keyPrefix, iconBundleID: nil, implicitDefault: nil, requiresHardware: nil
        )
    }

    private func engine() -> DiffEngine { DiffEngine() }

    func testRecognizedEntry() {
        let kb = KnowledgeBase(entries: [makeEntry(domain: "com.apple.dock", key: "show-recents")], version: 1, updatedAt: nil)
        let result = engine().parse(diffOutput: """
            -com.apple.dock :: show-recents = 1
            +com.apple.dock :: show-recents = 0
            """, kb: kb)
        XCTAssertEqual(result.recognized.count, 1)
        XCTAssertEqual(result.unrecognized.count, 0)
        XCTAssertEqual(result.noise.count, 0)
    }

    func testUnrecognizedEntry() {
        let kb = KnowledgeBase(entries: [], version: 1, updatedAt: nil)
        let result = engine().parse(diffOutput: """
            -com.apple.dock :: unknown-key = 1
            +com.apple.dock :: unknown-key = 0
            """, kb: kb)
        XCTAssertEqual(result.unrecognized.count, 1)
        XCTAssertEqual(result.recognized.count, 0)
    }

    func testNoiseEntry() {
        let kb = KnowledgeBase(entries: [makeEntry(domain: "com.apple.FolderActionsDispatcher", keyPrefix: "folderActions.$objects[", noise: true)], version: 1, updatedAt: nil)
        let result = engine().parse(diffOutput: """
            -com.apple.FolderActionsDispatcher :: folderActions.$objects[7] = old.pdf
            +com.apple.FolderActionsDispatcher :: folderActions.$objects[7] = new.pdf
            """, kb: kb)
        XCTAssertEqual(result.noise.count, 1)
        XCTAssertEqual(result.unrecognized.count, 0)
    }

    func testFinderTargetPathIsTakenFromEachSnapshot() {
        // The real case from testing: switching away from a custom folder leaves
        // NewWindowTargetPath untouched, so it never appears in the diff — the folder
        // name has to be read out of the snapshots directly.
        let kb = KnowledgeBase(entries: [
            makeEntry(domain: "com.apple.finder", key: "NewWindowTarget"),
        ], version: 1, updatedAt: nil)
        let beforeSnapshot = """
            /Users/x/Library/Preferences/com.apple.finder.plist :: NewWindowTarget = PfLo
            /Users/x/Library/Preferences/com.apple.finder.plist :: NewWindowTargetPath = file:///Users/x/Pictures/Art/
            """
        let afterSnapshot = """
            /Users/x/Library/Preferences/com.apple.finder.plist :: NewWindowTarget = PfHm
            /Users/x/Library/Preferences/com.apple.finder.plist :: NewWindowTargetPath = file:///Users/x/Pictures/Art/
            """
        let result = engine().parse(diffOutput: """
            -/Users/x/Library/Preferences/com.apple.finder.plist :: NewWindowTarget = PfLo
            +/Users/x/Library/Preferences/com.apple.finder.plist :: NewWindowTarget = PfHm
            """, kb: kb, beforeSnapshot: beforeSnapshot, afterSnapshot: afterSnapshot)

        XCTAssertEqual(result.recognized.count, 1)
        XCTAssertEqual(result.recognized.first?.diff.beforeDetail, "file:///Users/x/Pictures/Art/")
        XCTAssertEqual(result.recognized.first?.diff.afterDetail, "file:///Users/x/Pictures/Art/")
    }

    func testFinderTargetPathIsPerSnapshotNotShared() {
        // Custom folder to a different custom folder: NewWindowTarget never moves off
        // PfLo, so the path is the only record, and each side must show its own.
        let kb = KnowledgeBase(entries: [
            makeEntry(domain: "com.apple.finder", key: "NewWindowTarget"),
        ], version: 1, updatedAt: nil)
        let result = engine().parse(diffOutput: """
            -/Users/x/Library/Preferences/com.apple.finder.plist :: NewWindowTargetPath = file:///Users/x/Pictures/Art/
            +/Users/x/Library/Preferences/com.apple.finder.plist :: NewWindowTargetPath = file:///Users/x/Documents/
            """, kb: kb,
            beforeSnapshot: "com.apple.finder.plist :: NewWindowTargetPath = file:///Users/x/Pictures/Art/",
            afterSnapshot: "com.apple.finder.plist :: NewWindowTargetPath = file:///Users/x/Documents/")

        XCTAssertEqual(result.unrecognized.count + result.recognized.count, 1,
                       "The path change itself must still be reported")
    }

    // MARK: - Capture format
    //
    // A format change alters what is captured, so comparing across one shows renamed
    // and restructured keys as though settings had changed. Anyone updating from an
    // older build has a library of older-format snapshots and will hit this.

    private func snapshot(format: Int?, extra: String = "") -> Snapshot {
        let header = format.map { "Format: \($0) (SetShot 1.0 (26))\n" } ?? ""
        return Snapshot(takenAt: .now, rawOutput: """
            ==========================================
            macOS Settings Snapshot
            \(header)==========================================
            \(extra)
            """)
    }

    func testSnapshotWithoutAFormatLineIsFormatOne() {
        XCTAssertEqual(DiffEngine.snapshotFormat(of: snapshot(format: nil).rawOutput), 1)
        XCTAssertEqual(DiffEngine.snapshotFormat(of: snapshot(format: 2).rawOutput), 2)
    }

    func testComparingAcrossFormatsWarns() async throws {
        let kb = KnowledgeBase(entries: [], version: 1, updatedAt: nil)
        let result = try await engine().diff(before: snapshot(format: nil),
                                             after: snapshot(format: 2), kb: kb)
        let warning = try XCTUnwrap(result.limitedAccessWarning)
        XCTAssertTrue(warning.contains("different versions of SetShot"), warning)
        XCTAssertTrue(warning.contains("b26") && warning.contains("b27"),
                      "It should name the releases each format belongs to")
    }

    func testFormatWarningOutranksTheFullDiskAccessOne() async throws {
        // An older snapshot has no `TCC :: available` line at all, and its absence
        // otherwise reads as Full Disk Access having been lost — which is exactly the
        // false report that prompted this.
        let kb = KnowledgeBase(entries: [], version: 1, updatedAt: nil)
        let result = try await engine().diff(
            before: snapshot(format: 2, extra: "TCC :: available = 1"),
            after: snapshot(format: nil),
            kb: kb)
        let warning = try XCTUnwrap(result.limitedAccessWarning)
        XCTAssertTrue(warning.contains("different versions of SetShot"), warning)
        XCTAssertFalse(warning.contains("lost Full Disk Access"), warning)
    }

    func testMatchingFormatsDoNotWarn() async throws {
        let kb = KnowledgeBase(entries: [], version: 1, updatedAt: nil)
        let result = try await engine().diff(before: snapshot(format: 2),
                                             after: snapshot(format: 2), kb: kb)
        XCTAssertNil(result.limitedAccessWarning)
    }

    // MARK: - Privacy permissions
    //
    // Reading the TCC databases needs Full Disk Access, so the snapshot carries
    // `TCC :: available` to separate "a permission changed" from "SetShot can
    // suddenly see all of them".

    private func tccKB(extra: [KBEntry] = []) -> KnowledgeBase {
        KnowledgeBase(entries: extra + [
            makeEntry(domain: "TCC", key: "available"),
            makeEntry(domain: "TCC-user", keyPrefix: "kTCCServiceMediaLibrary/"),
            makeEntry(domain: "TCC-system", keyPrefix: "kTCCServiceSystemPolicyAllFiles/"),
        ], version: 1, updatedAt: nil)
    }

    func testMediaAndMusicGrantIsReported() {
        let result = engine().parse(diffOutput: """
            -TCC-user :: kTCCServiceMediaLibrary/com.tidbits.SetShot = 0
            +TCC-user :: kTCCServiceMediaLibrary/com.tidbits.SetShot = 2
            """, kb: tccKB())
        XCTAssertEqual(result.recognized.count, 1)
        XCTAssertEqual(result.recognized.first?.diff.key, "kTCCServiceMediaLibrary/com.tidbits.SetShot")
        XCTAssertEqual(result.recognized.first?.diff.afterValue, "2")
    }

    // MARK: - Inert SystemDefault wallpaper

    /// The three lines that moved when the power cord came out, and the per-display
    /// choice that did not.
    private static let systemDefaultFlipDiff = """
        -wallpaper :: SystemDefault.Desktop.Content.Choices[0].Configuration.assetID = 4A3590EC-FF30-41E7-85FE-210FF6112917
        +wallpaper :: SystemDefault.Desktop.Content.Choices[0].Configuration.placement = True
        +wallpaper :: SystemDefault.Desktop.Content.Choices[0].Files[0].relative = file:///Users/adam/Library/Application%20Support/com.apple.desktop.photos/ee3ebb28.jpeg
        """

    private static let perDisplaySnapshot = """
        wallpaper :: Spaces..Displays.37D8832A.Desktop.Content.Choices[0].Files[0].relative = file:///a.heic
        wallpaper :: SystemDefault.Desktop.Content.Choices[0].Configuration.assetID = 4A3590EC
        """

    private static let fallbackOnlySnapshot = """
        wallpaper :: SystemDefault.Desktop.Content.Choices[0].Configuration.assetID = 4A3590EC
        """

    private func wallpaperKB() -> KnowledgeBase {
        KnowledgeBase(entries: [
            makeEntry(domain: "wallpaper", keyPrefix: "SystemDefault.Desktop.Content.Choices"),
            makeEntry(domain: "wallpaper", keyPrefix: "Spaces."),
        ], version: 1, updatedAt: nil)
    }

    func testSystemDefaultWallpaperIsSuppressedWhenEveryDisplayHasItsOwnChoice() {
        let result = engine().parse(diffOutput: Self.systemDefaultFlipDiff, kb: wallpaperKB(),
                                    beforeSnapshot: Self.perDisplaySnapshot,
                                    afterSnapshot: Self.perDisplaySnapshot)
        XCTAssertEqual(result.recognized.count, 0,
                       "SystemDefault is the fallback for a display with no choice of its own; "
                       + "with per-display choices on both sides it cannot be what is on screen.")
        XCTAssertEqual(result.unrecognized.count, 0)
    }

    func testSystemDefaultWallpaperIsReportedWhenNothingElseSetsIt() {
        let result = engine().parse(diffOutput: Self.systemDefaultFlipDiff, kb: wallpaperKB(),
                                    beforeSnapshot: Self.fallbackOnlySnapshot,
                                    afterSnapshot: Self.fallbackOnlySnapshot)
        // Two, not three: the flip replaces an aerial with a picture, so the assetID
        // and file rows pair into one, leaving that and the placement row.
        XCTAssertEqual(result.recognized.count, 2,
                       "With no per-display choice, SystemDefault is the wallpaper.")
    }

    func testSystemDefaultWallpaperIsReportedWhenPerDisplayChoicesAreRemoved() {
        let result = engine().parse(diffOutput: Self.systemDefaultFlipDiff, kb: wallpaperKB(),
                                    beforeSnapshot: Self.perDisplaySnapshot,
                                    afterSnapshot: Self.fallbackOnlySnapshot)
        XCTAssertEqual(result.recognized.count, 2,
                       "Falling back to SystemDefault is itself a change worth reporting.")
    }

    func testPerDisplayWallpaperChangesAreNeverSuppressed() {
        let result = engine().parse(diffOutput: """
            -wallpaper :: Spaces..Displays.37D8832A.Desktop.Content.Choices[0].Files[0].relative = file:///a.heic
            +wallpaper :: Spaces..Displays.37D8832A.Desktop.Content.Choices[0].Files[0].relative = file:///b.heic
            """, kb: wallpaperKB(),
            beforeSnapshot: Self.perDisplaySnapshot, afterSnapshot: Self.perDisplaySnapshot)
        XCTAssertEqual(result.recognized.count, 1)
    }

    func testScreenSaverFallbackIsSuppressedIndependentlyOfTheDesktop() {
        // Per-display choices exist for the desktop but not the screen saver, so the
        // desktop fallback is inert and the screen saver fallback is not.
        let snapshot = Self.perDisplaySnapshot
        let kb = KnowledgeBase(entries: [
            makeEntry(domain: "wallpaper", keyPrefix: "SystemDefault.Desktop.Content.Choices"),
            makeEntry(domain: "wallpaper", keyPrefix: "SystemDefault.Idle.Content.Choices"),
        ], version: 1, updatedAt: nil)
        let result = engine().parse(diffOutput: """
            -wallpaper :: SystemDefault.Desktop.Content.Choices[0].Configuration.assetID = A
            +wallpaper :: SystemDefault.Desktop.Content.Choices[0].Configuration.assetID = B
            -wallpaper :: SystemDefault.Idle.Content.Choices[0].Configuration.module.relative = file:///x
            +wallpaper :: SystemDefault.Idle.Content.Choices[0].Configuration.module.relative = file:///y
            """, kb: kb, beforeSnapshot: snapshot, afterSnapshot: snapshot)
        XCTAssertEqual(result.recognized.count, 1)
        XCTAssertTrue(result.recognized[0].diff.key.hasPrefix("SystemDefault.Idle"))
    }

    // MARK: - Pairing an aerial with the picture that replaced it

    private static let choice =
        "Spaces.AAAAAAAA-1111-2222-3333-444444444444.Displays."
        + "37D8832A-2D66-02CA-B9F7-8F30A301B230.Desktop.Content.Choices[0]"

    func testAnAerialReplacedByAPictureIsOneChange() {
        let result = engine().parse(diffOutput: """
            -wallpaper :: \(Self.choice).Configuration.assetID = AERIAL-ID
            +wallpaper :: \(Self.choice).Files[0].relative = file:///new.jpg
            """, kb: spacesKB())
        XCTAssertEqual(result.recognized.count, 1)
        let row = result.recognized[0].diff
        XCTAssertTrue(row.key.hasSuffix("Files[0].relative"),
                      "The surviving row should say what the wallpaper is now.")
        XCTAssertEqual(row.beforeValue, "AERIAL-ID")
        XCTAssertEqual(row.afterValue, "file:///new.jpg")
    }

    func testAPictureReplacedByAnAerialIsOneChange() {
        let result = engine().parse(diffOutput: """
            -wallpaper :: \(Self.choice).Files[0].relative = file:///old.jpg
            +wallpaper :: \(Self.choice).Configuration.assetID = AERIAL-ID
            """, kb: spacesKB())
        XCTAssertEqual(result.recognized.count, 1)
        let row = result.recognized[0].diff
        XCTAssertTrue(row.key.hasSuffix("Configuration.assetID"))
        XCTAssertEqual(row.beforeValue, "file:///old.jpg")
        XCTAssertEqual(row.afterValue, "AERIAL-ID")
    }

    func testSeparateChoicesAreNotPairedWithEachOther() {
        // Choices[0] and Choices[1] are two slots in a shuffling wallpaper, not one
        // image being replaced.
        let base = "Spaces.AAAAAAAA-1111-2222-3333-444444444444.Displays."
            + "37D8832A-2D66-02CA-B9F7-8F30A301B230.Desktop.Content"
        let result = engine().parse(diffOutput: """
            -wallpaper :: \(base).Choices[0].Configuration.assetID = AERIAL-ID
            +wallpaper :: \(base).Choices[1].Files[0].relative = file:///new.jpg
            """, kb: spacesKB())
        XCTAssertEqual(result.recognized.count, 2)
    }

    func testAnAerialRemovedWithNothingReplacingItStillReports() {
        let result = engine().parse(diffOutput: """
            -wallpaper :: \(Self.choice).Configuration.assetID = AERIAL-ID
            """, kb: spacesKB())
        XCTAssertEqual(result.recognized.count, 1)
        XCTAssertEqual(result.recognized[0].diff.afterValue, "")
    }

    func testTwoWallpapersBothChangingValueAreNotPaired() {
        // Both sides have a value, so neither is an identifier appearing or
        // disappearing — pairing them would drop a real change.
        let result = engine().parse(diffOutput: """
            -wallpaper :: \(Self.choice).Configuration.assetID = ONE
            +wallpaper :: \(Self.choice).Configuration.assetID = TWO
            -wallpaper :: \(Self.choice).Files[0].relative = file:///a.jpg
            +wallpaper :: \(Self.choice).Files[0].relative = file:///b.jpg
            """, kb: spacesKB())
        XCTAssertEqual(result.recognized.count, 2)
    }

    // MARK: - Per-Space wallpaper collapse

    private static let displayA = "37D8832A-2D66-02CA-B9F7-8F30A301B230"

    private func spacesKB() -> KnowledgeBase {
        KnowledgeBase(entries: [makeEntry(domain: "wallpaper", keyPrefix: "Spaces.")],
                      version: 1, updatedAt: nil)
    }

    func testOneWallpaperPerDisplayNoMatterHowManySpacesRecordedIt() {
        // "Show on all Spaces" writes the same wallpaper into every Space, so this
        // arrived as one identical row per Space.
        let leaf = "Desktop.Content.Choices[0].Files[0].relative"
        var diff = ""
        for space in ["", "AAAAAAAA-1111-2222-3333-444444444444", "BBBBBBBB-1111-2222-3333-444444444444"] {
            let key = "Spaces.\(space).Displays.\(Self.displayA).\(leaf)"
            diff += "-wallpaper :: \(key) = file:///old.jpg\n"
            diff += "+wallpaper :: \(key) = file:///new.jpg\n"
        }
        let result = engine().parse(diffOutput: diff, kb: spacesKB())
        XCTAssertEqual(result.recognized.count, 1)
    }

    func testSpacesThatGenuinelyHeldDifferentWallpapersStillReportSeparately() {
        let leaf = "Desktop.Content.Choices[0].Files[0].relative"
        var diff = ""
        for (space, old) in [("AAAAAAAA-1111-2222-3333-444444444444", "one.jpg"),
                             ("BBBBBBBB-1111-2222-3333-444444444444", "two.jpg")] {
            let key = "Spaces.\(space).Displays.\(Self.displayA).\(leaf)"
            diff += "-wallpaper :: \(key) = file:///\(old)\n"
            diff += "+wallpaper :: \(key) = file:///new.jpg\n"
        }
        let result = engine().parse(diffOutput: diff, kb: spacesKB())
        XCTAssertEqual(result.recognized.count, 2,
                       "Collapsing these would claim both Spaces started from the same wallpaper.")
    }

    func testDifferentDisplaysAreNeverCollapsedTogether() {
        let other = "5E3571FF-033C-4BD8-A9CB-C8F33B34BBD2"
        let leaf = "Desktop.Content.Choices[0].Files[0].relative"
        var diff = ""
        for display in [Self.displayA, other] {
            let key = "Spaces.AAAAAAAA-1111-2222-3333-444444444444.Displays.\(display).\(leaf)"
            diff += "-wallpaper :: \(key) = file:///old.jpg\n"
            diff += "+wallpaper :: \(key) = file:///new.jpg\n"
        }
        let result = engine().parse(diffOutput: diff, kb: spacesKB())
        XCTAssertEqual(result.recognized.count, 2)
    }

    func testFullDiskAccessGrantToAnotherAppIsReported() {
        let result = engine().parse(diffOutput: """
            -TCC-system :: kTCCServiceSystemPolicyAllFiles/com.example.tool = 0
            +TCC-system :: kTCCServiceSystemPolicyAllFiles/com.example.tool = 2
            """, kb: tccKB())
        XCTAssertEqual(result.recognized.count, 1)
        XCTAssertEqual(result.recognized.first?.diff.key,
                       "kTCCServiceSystemPolicyAllFiles/com.example.tool")
    }

    func testGainingFullDiskAccessSuppressesTheFloodOfPermissions() {
        // Every grant on the Mac becomes visible at once. Report the capability
        // change, not two hundred spurious additions.
        let result = engine().parse(diffOutput: """
            -TCC :: available = 0
            +TCC :: available = 1
            +TCC-user :: kTCCServiceMediaLibrary/com.apple.Music = 2
            +TCC-user :: kTCCServiceCamera/us.zoom.xos = 2
            +TCC-system :: kTCCServiceSystemPolicyAllFiles/com.tidbits.SetShot = 2
            """, kb: tccKB())

        XCTAssertEqual(result.recognized.count, 1)
        XCTAssertEqual(result.recognized.first?.diff.key, "available")
        XCTAssertTrue(result.unrecognized.isEmpty, "Permission rows should be withheld")
        XCTAssertTrue(result.limitedAccessWarning?.contains("granted Full Disk Access") == true,
                      "Expected an explanation, got: \(result.limitedAccessWarning ?? "nil")")
    }

    func testOlderSnapshotWithNoTCCDataIsTreatedAsNotReadable() {
        // Snapshots taken before SetShot captured privacy permissions have no
        // `TCC :: available` line at all — the key is absent rather than 0. Comparing
        // one of those against a snapshot taken with Full Disk Access is exactly the
        // flood this suppression exists for, so an absent value has to count.
        let result = engine().parse(diffOutput: """
            +TCC :: available = 1
            +TCC-user :: kTCCServiceCamera/us.zoom.xos = 2
            +TCC-user :: kTCCServiceMicrophone/com.example.a = 2
            +TCC-system :: kTCCServiceSystemPolicyAllFiles/com.example.b = 2
            """, kb: tccKB())

        XCTAssertEqual(result.recognized.count, 1)
        XCTAssertEqual(result.recognized.first?.diff.key, "available")
        XCTAssertTrue(result.unrecognized.isEmpty, "Permission rows should be withheld")
        XCTAssertTrue(result.limitedAccessWarning?.contains("granted Full Disk Access") == true)
    }

    func testTurningOffMediaAccessWithholdsTheSettingsItGates() {
        // Without Media & Apple Music the script skips the media domains entirely, so
        // roughly three hundred settings vanish from the snapshot. They did not change.
        let kb = KnowledgeBase(entries: [
            makeEntry(domain: "Music", key: "available"),
            makeEntry(domain: "com.apple.Music", key: "userWantsPlaybackNotifications"),
            makeEntry(domain: "com.apple.dock", key: "autohide"),
        ], version: 1, updatedAt: nil)
        let result = engine().parse(diffOutput: """
            -Music :: available = 1
            +Music :: available = 0
            -/Users/x/Library/Preferences/com.apple.Music.plist :: userWantsPlaybackNotifications = 1
            -/Users/x/Library/Preferences/com.apple.dock.plist :: autohide = 0
            +/Users/x/Library/Preferences/com.apple.dock.plist :: autohide = 1
            """, kb: kb)

        let keys = Set(result.recognized.map(\.diff.key) + result.unrecognized.map(\.key))
        XCTAssertTrue(keys.contains("available"))
        XCTAssertTrue(keys.contains("autohide"), "A real change must not be withheld")
        XCTAssertFalse(keys.contains("userWantsPlaybackNotifications"),
                       "Music settings only became unreadable")
        XCTAssertTrue(result.limitedAccessWarning?.contains("Media & Apple Music") == true)
    }

    func testMediaMarkerMissingOnOneSideChangesNothing() {
        // A snapshot taken before the marker existed says nothing about what was
        // captured; assuming it was off would invent a change.
        let kb = KnowledgeBase(entries: [
            makeEntry(domain: "com.apple.Music", key: "userWantsPlaybackNotifications"),
        ], version: 1, updatedAt: nil)
        let result = engine().parse(diffOutput: """
            +Music :: available = 1
            -/Users/x/Library/Preferences/com.apple.Music.plist :: userWantsPlaybackNotifications = 1
            """, kb: kb)
        XCTAssertNil(result.limitedAccessWarning)
        XCTAssertEqual(result.recognized.count, 1, "The Music setting should still be reported")
    }

    func testLosingAccessWithholdsSettingsThatMerelyBecameUnreadable() {
        // Revoking Full Disk Access on a real Mac made Time Machine read as switched
        // off and Mail's settings as wiped: those files live behind the permission, so
        // they vanished from the snapshot. A value on one side only says what SetShot
        // could read, not what changed.
        let kb = KnowledgeBase(entries: [
            makeEntry(domain: "com.apple.TimeMachine", key: "AutoBackup"),
            makeEntry(domain: "com.apple.mail-shared", key: "AddressDisplayMode"),
            makeEntry(domain: "com.apple.dock", key: "autohide"),
        ], version: 1, updatedAt: nil)
        let result = engine().parse(diffOutput: """
            -TCC :: available = 1
            +TCC :: available = 0
            -/Users/x/Library/Preferences/com.apple.TimeMachine.plist :: AutoBackup = 1
            -/Users/x/Library/Preferences/com.apple.mail-shared.plist :: AddressDisplayMode = 0
            -/Users/x/Library/Preferences/com.apple.dock.plist :: autohide = 0
            +/Users/x/Library/Preferences/com.apple.dock.plist :: autohide = 1
            """, kb: tccKB(extra: kb.entries))

        // The Dock changed for real — both sides have a value — so it survives.
        let keys = Set(result.recognized.map(\.diff.key) + result.unrecognized.map(\.key))
        XCTAssertTrue(keys.contains("autohide"), "A real change must not be withheld")
        XCTAssertFalse(keys.contains("AutoBackup"), "Time Machine only became unreadable")
        XCTAssertFalse(keys.contains("AddressDisplayMode"), "Mail only became unreadable")
        XCTAssertTrue(keys.contains("available"), "The row explaining the results must stay")
    }

    func testLosingFullDiskAccessSuppressesTheFloodOfPermissions() {
        let result = engine().parse(diffOutput: """
            -TCC :: available = 1
            +TCC :: available = 0
            -TCC-user :: kTCCServiceMediaLibrary/com.apple.Music = 2
            -TCC-system :: kTCCServiceSystemPolicyAllFiles/com.tidbits.SetShot = 2
            """, kb: tccKB())

        XCTAssertEqual(result.recognized.count, 1)
        XCTAssertTrue(result.unrecognized.isEmpty)
        XCTAssertTrue(result.limitedAccessWarning?.contains("lost Full Disk Access") == true)
    }

    func testSemanticDuplicatesSkipped() {
        // "1" and "true" are semantically equal — should not appear in results
        let kb = KnowledgeBase(entries: [], version: 1, updatedAt: nil)
        let result = engine().parse(diffOutput: """
            -com.apple.dock :: show-recents = 1
            +com.apple.dock :: show-recents = true
            """, kb: kb)
        XCTAssertEqual(result.unrecognized.count, 0)
    }

    func testDomainNormalisationStripsPath() {
        let kb = KnowledgeBase(entries: [makeEntry(domain: "com.apple.dock", key: "show-recents")], version: 1, updatedAt: nil)
        let result = engine().parse(diffOutput: """
            -/Users/adam/Library/Preferences/com.apple.dock.plist :: show-recents = 1
            +/Users/adam/Library/Preferences/com.apple.dock.plist :: show-recents = 0
            """, kb: kb)
        XCTAssertEqual(result.recognized.count, 1)
    }

    func testBeforeAndAfterValuesExtracted() {
        let kb = KnowledgeBase(entries: [], version: 1, updatedAt: nil)
        let result = engine().parse(diffOutput: """
            -com.apple.dock :: autohide = 0
            +com.apple.dock :: autohide = 1
            """, kb: kb)
        XCTAssertEqual(result.unrecognized.first?.beforeValue, "0")
        XCTAssertEqual(result.unrecognized.first?.afterValue, "1")
    }

    func testMixedResults() {
        let kb = KnowledgeBase(entries: [
            makeEntry(domain: "com.apple.dock", key: "show-recents"),
            makeEntry(domain: "com.apple.dock", key: "autohide-delay", noise: true),
        ], version: 1, updatedAt: nil)
        let result = engine().parse(diffOutput: """
            -com.apple.dock :: show-recents = 1
            +com.apple.dock :: show-recents = 0
            -com.apple.dock :: autohide-delay = 0.5
            +com.apple.dock :: autohide-delay = 0.2
            -com.apple.dock :: unknown = foo
            +com.apple.dock :: unknown = bar
            """, kb: kb)
        XCTAssertEqual(result.recognized.count, 1)
        XCTAssertEqual(result.noise.count, 1)
        XCTAssertEqual(result.unrecognized.count, 1)
    }

    // MARK: - isFullReversal

    func testIsFullReversalTrueWithExtraRealChange() {
        let kb = KnowledgeBase(entries: [], version: 1, updatedAt: nil)
        let ab = engine().parse(diffOutput: """
            -com.apple.dock :: key1 = 1
            +com.apple.dock :: key1 = 2
            -com.apple.dock :: key2 = A
            +com.apple.dock :: key2 = B
            """, kb: kb)
        let bc = engine().parse(diffOutput: """
            -com.apple.dock :: key1 = 2
            +com.apple.dock :: key1 = 1
            -com.apple.dock :: key2 = B
            +com.apple.dock :: key2 = A
            -com.apple.dock :: key3 = X
            +com.apple.dock :: key3 = Y
            """, kb: kb)
        XCTAssertTrue(DiffEngine.isFullReversal(of: bc, reversing: ab))
    }

    func testIsFullReversalFalseWhenPartial() {
        let kb = KnowledgeBase(entries: [], version: 1, updatedAt: nil)
        let ab = engine().parse(diffOutput: """
            -com.apple.dock :: key1 = 1
            +com.apple.dock :: key1 = 2
            -com.apple.dock :: key2 = A
            +com.apple.dock :: key2 = B
            """, kb: kb)
        let bc = engine().parse(diffOutput: """
            -com.apple.dock :: key1 = 2
            +com.apple.dock :: key1 = 1
            """, kb: kb)
        XCTAssertFalse(DiffEngine.isFullReversal(of: bc, reversing: ab))
    }

    func testIsFullReversalFalseWhenAbEmpty() {
        let kb = KnowledgeBase(entries: [], version: 1, updatedAt: nil)
        let ab = engine().parse(diffOutput: "", kb: kb)
        let bc = engine().parse(diffOutput: """
            -com.apple.dock :: key1 = 1
            +com.apple.dock :: key1 = 2
            """, kb: kb)
        XCTAssertFalse(DiffEngine.isFullReversal(of: bc, reversing: ab))
    }

    func testIsFullReversalFalseWhenKeyLandsOnDifferentValue() {
        let kb = KnowledgeBase(entries: [], version: 1, updatedAt: nil)
        let ab = engine().parse(diffOutput: """
            -com.apple.dock :: key1 = 1
            +com.apple.dock :: key1 = 2
            """, kb: kb)
        let bc = engine().parse(diffOutput: """
            -com.apple.dock :: key1 = 2
            +com.apple.dock :: key1 = 3
            """, kb: kb)
        XCTAssertFalse(DiffEngine.isFullReversal(of: bc, reversing: ab))
    }

    // MARK: - Media & Apple Music reported once

    /// SetShot's own Media & Apple Music grant is recorded twice: as the Music ::
    /// available marker, and as SetShot's row in the TCC database like any other app.
    /// Reporting both said one change twice, and which one survived depended on the
    /// direction -- a user saw one row granting and two revoking.

    private func mediaKB() -> KnowledgeBase {
        KnowledgeBase(entries: [
            makeEntry(domain: "Music", key: "available"),
            makeEntry(domain: "TCC-user", keyPrefix: "kTCCServiceMediaLibrary/"),
        ], version: 1, updatedAt: nil)
    }

    private var ownBundleID: String { Bundle.main.bundleIdentifier ?? "com.tidbits.SetShot" }

    func testRevokingMediaAccessReportsOneChangeNotTwo() {
        let result = engine().parse(diffOutput: """
            -Music :: available = 1
            +Music :: available = 0
            -TCC-user :: kTCCServiceMediaLibrary/\(ownBundleID) = 2
            +TCC-user :: kTCCServiceMediaLibrary/\(ownBundleID) = 0
            """, kb: mediaKB())
        XCTAssertEqual(result.recognized.count, 1,
                       "Revoking should report the marker alone, not it and SetShot's TCC row")
        XCTAssertEqual(result.recognized.first?.diff.domain, "Music")
    }

    func testGrantingMediaAccessAlsoReportsOneChange() {
        let result = engine().parse(diffOutput: """
            -Music :: available = 0
            +Music :: available = 1
            +TCC-user :: kTCCServiceMediaLibrary/\(ownBundleID) = 2
            """, kb: mediaKB())
        XCTAssertEqual(result.recognized.count, 1,
                       "Granting should report the marker alone, as it already did")
        XCTAssertEqual(result.recognized.first?.diff.domain, "Music")
    }

    /// Only SetShot's own row is folded in. Another app gaining or losing the same
    /// permission is a setting in its own right.
    func testAnotherAppsMediaAccessIsStillReported() {
        let result = engine().parse(diffOutput: """
            -Music :: available = 1
            +Music :: available = 0
            -TCC-user :: kTCCServiceMediaLibrary/com.example.OtherApp = 2
            +TCC-user :: kTCCServiceMediaLibrary/com.example.OtherApp = 0
            """, kb: mediaKB())
        XCTAssertEqual(result.recognized.count, 2,
                       "Another app's grant should survive alongside the marker")
    }
}
