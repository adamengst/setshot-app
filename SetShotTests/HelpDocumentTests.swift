import XCTest
import AppKit
@testable import SetShot

/// The About view and its search both come from the bundled documentation.md. If the
/// file drops out of the build or stops parsing, About goes blank without an error,
/// so these check what the running app actually loads.
final class HelpDocumentTests: XCTestCase {

    func testTheBundledDocumentParses() {
        let content = HelpDocument.content
        XCTAssertFalse(content.isEmpty, "documentation.md is missing from the app bundle or parsed to nothing")
        XCTAssertTrue(content.contains { if case .title = $0 { return true }; return false }, "no # title")
        XCTAssertTrue(content.contains { if case .section = $0 { return true }; return false }, "no ## sections")
        XCTAssertTrue(content.contains { $0.searchText?.isEmpty == false }, "nothing searchable")
    }

    func testEveryScreenshotIsInTheAssetCatalog() {
        for item in HelpDocument.content {
            switch item {
            case .screenshot(let name), .indentedScreenshot(let name):
                XCTAssertNotNil(NSImage(named: name), "documentation.md shows \(name), which the app does not contain")
            default:
                break
            }
        }
    }
}
