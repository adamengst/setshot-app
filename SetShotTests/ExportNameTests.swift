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
        XCTAssertEqual(snapshot(date: jan2, baseName: "macOS Sequoia 15.7.7 baseline defaults").exportLabel,
                       "macOS Sequoia 15.7.7 baseline defaults")
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
}
