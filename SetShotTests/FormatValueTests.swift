import XCTest
@testable import SetShot

/// formatValue turns a raw snapshot value into something readable. Anything it
/// resolves by reading the live system is a value the snapshot did not record, so
/// it must never be used for a setting that could itself have changed between the
/// two snapshots being compared.
final class FormatValueTests: XCTestCase {

    private let newWindowTargetMap = [
        "PfHm": "Home", "PfCm": "My Mac", "PfVo": "Startup Volume",
        "PfDe": "Desktop", "PfLo": "Custom folder", "PfOt": "Custom folder",
    ]

    func testCustomFolderResolvesFromTheSnapshotItCameFrom() {
        // The folder name comes from the snapshot the value was read out of, so each
        // side of a comparison shows its own folder rather than today's.
        XCTAssertEqual(
            formatValue("PfLo", key: "NewWindowTarget", valueMap: newWindowTargetMap,
                        detail: "file:///Users/someone/Pictures/Art/"),
            "Art"
        )
        XCTAssertEqual(
            formatValue("PfOt", key: "NewWindowTarget", valueMap: newWindowTargetMap,
                        detail: "file:///Users/someone/Documents/Invoices/"),
            "Invoices"
        )
    }

    func testCustomFolderFallsBackWhenTheSnapshotHasNoPath() {
        // Older snapshots predate the path being captured, and a malformed value must
        // not produce a nonsense name. "Custom folder" is vague but never wrong.
        for detail in [nil, "", "not-a-url"] as [String?] {
            XCTAssertEqual(
                formatValue("PfLo", key: "NewWindowTarget",
                            valueMap: newWindowTargetMap, detail: detail),
                "Custom folder",
                "detail=\(detail ?? "nil")"
            )
        }
    }

    func testCustomFolderTargetDoesNotReadLiveDefaults() {
        // This used to resolve a folder name from live UserDefaults, which showed
        // today's folder for both sides of a comparison — so switching from one
        // custom folder to another read as no change at all, and old snapshots were
        // labelled with the current folder.
        // With no detail supplied the live NewWindowTargetPath must not be consulted,
        // whatever it currently holds.
        XCTAssertEqual(
            formatValue("PfLo", key: "NewWindowTarget", valueMap: newWindowTargetMap),
            "Custom folder"
        )
        XCTAssertEqual(
            formatValue("PfOt", key: "NewWindowTarget", valueMap: newWindowTargetMap),
            "Custom folder"
        )
    }

    func testNewWindowTargetPathShowsTheFolderItRecorded() {
        // The folder itself is reported as its own row, from the snapshot's own value.
        XCTAssertEqual(
            formatValue("file:///Users/someone/Pictures/Art/", key: "NewWindowTargetPath"),
            "Art"
        )
        XCTAssertEqual(
            formatValue("file:///Users/someone/Documents/", key: "NewWindowTargetPath"),
            "Documents"
        )
    }

    func testMappedTargetsStillUseTheirLabels() {
        XCTAssertEqual(
            formatValue("PfDe", key: "NewWindowTarget", valueMap: newWindowTargetMap),
            "Desktop"
        )
    }

    func testMachineIdentityTargetsStillResolve() {
        // PfHm names the home folder, which is machine identity rather than a setting
        // this comparison could be about, so resolving it live is still worthwhile.
        let home = FileManager.default.homeDirectoryForCurrentUser.lastPathComponent
        XCTAssertEqual(
            formatValue("PfHm", key: "NewWindowTarget", valueMap: newWindowTargetMap),
            home
        )
    }

    func testDefaultHandlerShowsTheAppName() {
        // LaunchServices records and lowercases bundle identifiers, so the raw value
        // is "com.apple.safari" — not something to show anyone.
        XCTAssertEqual(formatValue("com.apple.safari", key: "handler"), "Safari")
    }

    func testUninstalledHandlerFallsBackToItsIdentifier() {
        // A snapshot can name an app that is no longer installed, and the identifier
        // is then the only honest answer.
        XCTAssertEqual(formatValue("com.example.definitely.not.installed", key: "handler"),
                       "com.example.definitely.not.installed")
    }

    func testHandlerLookupIgnoresValuesThatAreNotIdentifiers() {
        XCTAssertEqual(formatValue("/Applications/Foo.app", key: "handler"), "Foo")
        XCTAssertEqual(formatValue("(not set)", key: "handler"), "(not set)")
    }

    // MARK: - Row subjects
    //
    // A recognized row shows only its description, so an entry covering many keys
    // via key_prefix renders identically for every key it matches. The subject is
    // what says which display, which app, or which background item a row is about.

    private func prefixEntry(_ prefix: String?, domain: String = "d") -> KBEntry {
        KBEntry(id: "t", domain: domain, key: "", source: "s", valueType: "string",
                description: "Test", uiLocation: nil, uiLocationOverrides: nil, settingsURL: nil,
                noise: false, noiseReason: nil, minMacOS: nil, notes: nil, aiGenerated: false,
                contributedByIssue: nil, valueMap: nil, keyPrefix: prefix,
                iconBundleID: nil, implicitDefault: nil, requiresHardware: nil)
    }

    func testExactMatchEntriesHaveNoSubject() {
        // The description already names the setting; a subject would be redundant.
        XCTAssertNil(rowSubject(entry: prefixEntry(nil), key: "AppleKeyboardUIMode"))
    }

    func testSubjectIsTheKeyBeyondThePrefix() {
        XCTAssertEqual(
            rowSubject(entry: prefixEntry(""), key: "com.backblaze.bzbmenu.plist"),
            "com.backblaze.bzbmenu.plist"
        )
    }

    func testSubjectNamesTheAppBehindABundleIdentifier() {
        XCTAssertEqual(
            rowSubject(entry: prefixEntry("kTCCServiceCamera/"), key: "kTCCServiceCamera/com.apple.safari"),
            "Safari"
        )
    }

    func testSubjectKeepsAnUnresolvableIdentifier() {
        XCTAssertEqual(
            rowSubject(entry: prefixEntry("kTCCServiceCamera/"),
                       key: "kTCCServiceCamera/com.example.not.installed"),
            "com.example.not.installed"
        )
    }

    func testSubjectKeepsAnUnknownDisplayUUID() {
        // A snapshot outlives a monitor; the UUID is then all there is.
        let uuid = "00000000-0000-0000-0000-000000000000"
        XCTAssertEqual(
            rowSubject(entry: prefixEntry("Displays."), key: "Displays.\(uuid).Desktop"),
            "\(uuid).Desktop"
        )
    }

    // MARK: - Wallpaper rows
    //
    // One KB entry covers every key under a display, because the display's UUID sits
    // in the middle of the key and a key_prefix cannot skip it. The description is
    // therefore composed, not looked up — and it has to be one line, since SetShot
    // has no second description line.

    private func wallpaperEntry() -> KBEntry { prefixEntry("Displays.", domain: "wallpaper") }

    func testPerDisplayWallpaperDescriptionNamesTheDisplay() {
        let uuid = "00000000-0000-0000-0000-000000000000"
        XCTAssertEqual(
            rowDescription(entry: wallpaperEntry(),
                           key: "Displays.\(uuid).Desktop.Content.Choices[0].Files[0].relative"),
            "Wallpaper for \(uuid), set when \u{201C}Show on all Spaces\u{201D} is turned off."
        )
    }

    func testWallpaperDescriptionDistinguishesItsAspects() {
        let uuid = "00000000-0000-0000-0000-000000000000"
        let e = wallpaperEntry()
        XCTAssertTrue(rowDescription(entry: e,
            key: "Displays.\(uuid).Desktop.Content.Choices[0].Configuration.placement")
            .hasPrefix("Wallpaper placement for"))
        XCTAssertTrue(rowDescription(entry: e,
            key: "Displays.\(uuid).Idle.Content.Choices[0].Configuration.module.relative")
            .hasPrefix("Screen saver for"))
        XCTAssertEqual(rowDescription(entry: e, key: "Displays.\(uuid).Type"),
                       "Whether every display and Space shares one wallpaper.")
    }

    func testWholeMachineWallpaperScopesReadPlainly() {
        XCTAssertEqual(
            rowDescription(entry: prefixEntry("AllSpacesAndDisplays.Desktop.Content.Choices",
                                              domain: "wallpaper"),
                           key: "AllSpacesAndDisplays.Desktop.Content.Choices[0].Files[0].relative"),
            "Wallpaper for all displays."
        )
        XCTAssertEqual(
            rowDescription(entry: prefixEntry("SystemDefault.Desktop.Content.Choices",
                                              domain: "wallpaper"),
                           key: "SystemDefault.Desktop.Content.Choices[0].Files[0].relative"),
            "Wallpaper for the system default."
        )
    }

    func testOtherPrefixEntriesGetTheirSubjectOnTheSameLine() {
        let e = prefixEntry("kTCCServiceCamera/")
        XCTAssertEqual(rowDescription(entry: e, key: "kTCCServiceCamera/com.apple.safari"),
                       "Test — Safari")
    }

    func testExactMatchEntriesKeepTheirDescriptionAlone() {
        XCTAssertEqual(rowDescription(entry: prefixEntry(nil), key: "AppleKeyboardUIMode"), "Test")
    }

    func testAerialWallpaperShowsItsName() throws {
        // Aerials are stored only as asset UUIDs; the catalogue naming them is a
        // world-readable JSON file, so this needs no permission.
        try XCTSkipIf(AerialCatalogue.namesByID.isEmpty, "No aerial catalogue on this Mac")
        let id = "4A3590EC-FF30-41E7-85FE-210FF6112917"
        XCTAssertEqual(formatValue(id, key: "Content.Choices.Configuration.assetID"),
                       AerialCatalogue.name(forAssetID: id))
        XCTAssertFalse(formatValue(id, key: "Content.Choices.Configuration.assetID").contains("-"),
                       "An asset UUID should never reach the reader")
    }

    func testBuiltInWallpaperShowsItsName() {
        XCTAssertEqual(
            formatValue("file:///System/Library/Desktop%20Pictures/Sequoia%20Sunrise.madesktop"),
            "Sequoia Sunrise"
        )
    }

    func testChosenPhotoIsLabelledRatherThanShownAsAHash() {
        // macOS copies a photo you pick under a content hash and keeps no record of
        // its name, so the hash is all there is — shortened, but still distinct enough
        // to tell two photos apart.
        XCTAssertEqual(
            formatValue("file:///Users/x/Library/Application%20Support/com.apple.desktop.photos/ee3ebb28973e24dea544113339d59dca.jpeg"),
            "Photo ee3ebb28\u{2026}"
        )
    }

    func testBooleanFallbacksAreUnchanged() {
        XCTAssertEqual(formatValue("1"), "On")
        XCTAssertEqual(formatValue("false"), "Off")
    }
}
