import XCTest
@testable import SetShot

/// The Markdown export exists to be read anywhere and, in Chris Pepper's case, to
/// be diffed between two Macs. Both depend on the structure staying stable.
final class MarkdownExporterTests: XCTestCase {

    private func entry(description: String, location: String? = nil) -> KBEntry {
        KBEntry(id: "t", domain: "com.apple.dock", key: "autohide", source: "defaults",
                valueType: "bool", description: description, uiLocation: location,
                uiLocationOverrides: nil, settingsURL: nil, noise: false, noiseReason: nil,
                minMacOS: nil, notes: nil, aiGenerated: false, contributedByIssue: nil,
                valueMap: nil, keyPrefix: nil, iconBundleID: nil, implicitDefault: nil,
                requiresHardware: nil)
    }

    private func diffLine(before: String = "0", after: String = "1") -> DiffLine {
        DiffLine(domain: "com.apple.dock", key: "autohide", source: "defaults",
                 beforeValue: before, afterValue: after, macOSVersion: "15.0",
                 rawLine: "com.apple.dock :: autohide")
    }

    private func result(_ items: [(KBEntry, DiffLine)]) -> DiffResult {
        DiffResult(recognized: items.map { (entry: $0.0, diff: $0.1) }, unrecognized: [],
                   noise: [], unrecognizedOverflow: 0, limitedAccessWarning: nil)
    }

    func testEachChangeIsOneTaskListItem() {
        let md = MarkdownExporter.export(
            result: result([(entry(description: "Automatically hide the Dock",
                                   location: "System Settings → Desktop & Dock"), diffLine())]),
            beforeName: "A", afterName: "B", macOSMajor: 15)
        XCTAssertTrue(md.contains("- [ ] Automatically hide the Dock"), md)
        XCTAssertTrue(md.contains("  - System Settings → Desktop & Dock"), md)
        XCTAssertTrue(md.contains("  - `Off` → `On`"), md)
    }

    func testHeaderNamesTheMacAndTheSnapshots() {
        let md = MarkdownExporter.export(result: result([]), beforeName: "yesterday",
                                         afterName: "today", macOSMajor: 15)
        XCTAssertTrue(md.hasPrefix("# SetShot — \(StoredSnapshot.exportComputerName)"), md)
        XCTAssertTrue(md.contains("yesterday → today"), md)
        XCTAssertTrue(md.contains("0 recognized changes"), md)
    }

    func testWarningIsCarriedAcross() {
        let r = DiffResult(recognized: [], unrecognized: [], noise: [], unrecognizedOverflow: 0,
                           limitedAccessWarning: "Something about Full Disk Access.")
        let md = MarkdownExporter.export(result: r, beforeName: "A", afterName: "B", macOSMajor: 15)
        XCTAssertTrue(md.contains("> Something about Full Disk Access."), md)
    }

    func testHTMLExportCarriesTheWarningToo() {
        // Whether a snapshot was taken without a permission changes how the whole file
        // should be read, so both formats have to carry it.
        let r = DiffResult(recognized: [], unrecognized: [], noise: [], unrecognizedOverflow: 0,
                           limitedAccessWarning: "Something about Full Disk Access.")
        let html = HTMLExporter.export(result: r, beforeName: "A", afterName: "B", macOSMajor: 15)
        XCTAssertTrue(html.contains("class=\"warning\""), "The notice should be styled")
        XCTAssertTrue(html.contains("Something about Full Disk Access."), html.prefix(400).description)
    }

    func testHTMLExportOmitsTheWarningWhenThereIsNone() {
        let html = HTMLExporter.export(result: result([]), beforeName: "A", afterName: "B",
                                       macOSMajor: 15)
        XCTAssertFalse(html.contains("class=\"warning\""))
    }

    func testBracketsInADescriptionCannotBreakTheList() {
        // A key like Choices[0].Files[0] would otherwise read as a Markdown link.
        let md = MarkdownExporter.export(
            result: result([(entry(description: "Wallpaper [main] display"), diffLine())]),
            beforeName: "A", afterName: "B", macOSMajor: 15)
        XCTAssertTrue(md.contains("\\[main\\]"), md)
    }

    func testJournalGroupsBySnapshotAndKeepsNotes() {
        let entries = [
            JournalEntry(id: UUID(), afterSnapshotId: "s1", afterSnapshotDate: Date(),
                         afterSnapshotName: "s1", domain: "com.apple.dock", key: "autohide",
                         entryDescription: "Automatically hide the Dock",
                         uiLocation: "System Settings → Desktop & Dock", settingsURL: nil,
                         oldValue: "0", newValue: "1", addedAt: Date(), userNote: "deliberate"),
        ]
        let md = MarkdownExporter.export(journal: entries, oldestFirst: false)
        XCTAssertTrue(md.contains("# SetShot Journal — \(StoredSnapshot.exportComputerName)"), md)
        XCTAssertTrue(md.contains("## "), "Entries should be grouped under a heading")
        XCTAssertTrue(md.contains("- [ ] Automatically hide the Dock"), md)
        XCTAssertTrue(md.contains("  - Note: deliberate"), md)
    }
}
