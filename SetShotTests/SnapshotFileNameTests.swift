import XCTest
@testable import SetShot

/// Snapshot file names carry the date the library lists them by. A name the list
/// cannot read leaves the snapshot on disk but missing from SetShot (support issue 389).
final class SnapshotFileNameTests: XCTestCase {

    private func components(_ date: Date) -> DateComponents {
        Calendar(identifier: .gregorian).dateComponents(
            [.year, .month, .day, .hour, .minute, .second], from: date)
    }

    func testTheFixedFormIsRead() throws {
        let parsed = try XCTUnwrap(SnapshotStore.parseDateAndLabel(from: "setshot_2026-11-01_083822.txt.gz"))
        let c = components(parsed.date)
        XCTAssertEqual([c.year, c.month, c.day, c.hour, c.minute, c.second], [2026, 11, 1, 8, 38, 22])
        XCTAssertNil(parsed.label)
    }

    func testTheOldestMinuteFormWithALabelIsRead() throws {
        let parsed = try XCTUnwrap(SnapshotStore.parseDateAndLabel(from: "setshot_2026-08-06_1628_Before update.txt.gz"))
        XCTAssertEqual(components(parsed.date).hour, 16)
        XCTAssertEqual(parsed.label, "Before update")
    }

    // Names from Steve Kawalko's Mac, which wrote a 12-hour clock into them.
    func testTwelveHourNamesAreRead() throws {
        let morning = try XCTUnwrap(SnapshotStore.parseDateAndLabel(from: "setshot_2026-11-01_83822 AM.txt.gz"))
        let c = components(morning.date)
        XCTAssertEqual([c.year, c.month, c.day, c.hour, c.minute, c.second], [2026, 11, 1, 8, 38, 22])

        let evening = try XCTUnwrap(SnapshotStore.parseDateAndLabel(from: "setshot_2026-10-26_110930 PM.txt.gz"))
        let e = components(evening.date)
        XCTAssertEqual([e.hour, e.minute, e.second], [23, 9, 30])

        let noon = try XCTUnwrap(SnapshotStore.parseDateAndLabel(from: "setshot_2026-10-26_120005 PM.txt.gz"))
        XCTAssertEqual(components(noon.date).hour, 12)
        let midnight = try XCTUnwrap(SnapshotStore.parseDateAndLabel(from: "setshot_2026-10-26_120005 AM.txt.gz"))
        XCTAssertEqual(components(midnight.date).hour, 0)
    }

    func testARenamedTwelveHourNameKeepsItsLabel() throws {
        let parsed = try XCTUnwrap(SnapshotStore.parseDateAndLabel(from: "setshot_2026-11-01_838 AM_Clean install.txt.gz"))
        let c = components(parsed.date)
        XCTAssertEqual([c.hour, c.minute], [8, 38])
        XCTAssertEqual(parsed.label, "Clean install")
    }

    func testNewNamesUseTheFixedFormWhateverTheMacsSettings() {
        let f = SnapshotStore.fileNameFormatter("yyyy-MM-dd_HHmmss")
        var c = DateComponents()
        c.year = 2026; c.month = 11; c.day = 1; c.hour = 20; c.minute = 38; c.second = 22
        let date = Calendar(identifier: .gregorian).date(from: c)!
        XCTAssertEqual(f.string(from: date), "2026-11-01_203822")
    }

    func testAnUnrelatedFileIsIgnored() {
        XCTAssertNil(SnapshotStore.parseDateAndLabel(from: "setshot_notes.txt.gz"))
        XCTAssertNil(SnapshotStore.parseDateAndLabel(from: "other_2026-11-01_083822.txt.gz"))
    }
}
