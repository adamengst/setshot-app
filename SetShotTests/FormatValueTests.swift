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

    func testBooleanFallbacksAreUnchanged() {
        XCTAssertEqual(formatValue("1"), "On")
        XCTAssertEqual(formatValue("false"), "Off")
    }
}
