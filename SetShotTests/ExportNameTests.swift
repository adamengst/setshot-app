import XCTest
@testable import SetShot

/// Exports are meant to be compared between Macs — Chris Pepper's case is diffing
/// two machines to see what to reconcile, and checking a new Mac against an old one
/// for customisations he forgot. A filename has to survive that: it must say which
/// Mac it came from, and it must not say "Today".
final class ExportNameTests: XCTestCase {

    private func snapshot(date: Date, customLabel: String? = nil,
                          baseName: String? = nil) -> StoredSnapshot {
        var s = StoredSnapshot(
            url: URL(fileURLWithPath: "/tmp/setshot_2026-01-02_1530.txt.gz"),
            date: date, customLabel: customLabel)
        s.baseDisplayName = baseName
        return s
    }

    private var jan2: Date {
        var c = DateComponents(); c.year = 2026; c.month = 1; c.day = 2; c.hour = 15; c.minute = 30
        return Calendar.current.date(from: c)!
    }

    func testExportLabelIsNeverRelative() {
        // displayName says "Today at 15:30" for a snapshot taken today, which is wrong
        // in a file opened next week or on another Mac.
        let today = snapshot(date: Date())
        XCTAssertTrue(today.displayName.contains("Today"), "Precondition: displayName is relative")
        XCTAssertFalse(today.exportLabel.contains("Today"))
        XCTAssertFalse(today.exportLabel.contains("Yesterday"))
    }

    func testExportLabelSortsAndReadsAsADate() {
        XCTAssertEqual(snapshot(date: jan2).exportLabel, "2026-01-02 1530")
    }

    func testExportLabelKeepsNamesTheUserGave() {
        XCTAssertEqual(snapshot(date: jan2, customLabel: "before round 1").exportLabel,
                       "before round 1")
        XCTAssertEqual(snapshot(date: jan2, baseName: "macOS 15.7.7 Sequoia baseline defaults").exportLabel,
                       "macOS 15.7.7 Sequoia baseline defaults")
    }

    func testComputerNameIsUsableInAFilename() {
        let name = StoredSnapshot.exportComputerName
        XCTAssertFalse(name.isEmpty)
        XCTAssertFalse(name.contains("/"), "A slash would split the path")
        XCTAssertFalse(name.contains(":"), "A colon reads as a path separator in the Finder")
    }

    func testDateStampIsJustTheDay() {
        XCTAssertEqual(StoredSnapshot.exportDateStamp.count, 10)
        XCTAssertFalse(StoredSnapshot.exportDateStamp.contains("/"))
    }

    // MARK: - Baseline labels

    /// A release whose name is two words cannot carry the space in the filename:
    /// baseLabel splits on "_" to find the version, and the file sits on a build
    /// phase's path. The capital marks the join, so "base_GoldenGate_27.0.txt.gz"
    /// has to come back out as "Golden Gate" rather than running the words together.
    func testATwoWordReleaseNameGetsItsSpaceBack() {
        let store = SnapshotStore.shared
        XCTAssertEqual(store.spacedName("GoldenGate"), "Golden Gate")
        XCTAssertEqual(store.spacedName("Sequoia"), "Sequoia")
        XCTAssertEqual(store.spacedName("Tahoe"), "Tahoe")
    }

    /// Every baseline in the bundle is labelled, so one added with a name the
    /// deriver cannot read shows up here rather than in the picker.
    func testEveryBundledBaselineIsLabelled() throws {
        let names = try FileManager.default
            .contentsOfDirectory(at: TestSupport.baseSnapshotsDir, includingPropertiesForKeys: nil)
            .map(\.lastPathComponent)
            .filter { $0.hasPrefix("base_") && $0.hasSuffix(".txt.gz") }
        XCTAssertFalse(names.isEmpty)
        for name in names {
            let parts = name.dropFirst(5).dropLast(7).split(separator: "_", maxSplits: 1)
            XCTAssertEqual(parts.count, 2, "\(name) has no version after the release name")
            XCTAssertNotNil(Int(String(parts[1]).split(separator: ".").first ?? ""),
                            "\(name) has no major version the picker can match on")
        }
    }
}
