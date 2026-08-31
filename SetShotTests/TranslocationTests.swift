import XCTest
@testable import SetShot

/// A translocated bundle cannot be arranged from a test, so the path predicate is
/// tested directly against the shape macOS produces.
final class TranslocationTests: XCTestCase {

    func testATranslocatedPathIsRecognised() {
        let path = "/private/var/folders/24/abc123/T/AppTranslocation/"
            + "9C2D77E5-1A44-4E8B-B3F1-2E5A6C9D0B41/d/SetShot.app"
        XCTAssertTrue(Translocation.isTranslocated(bundlePath: path))
    }

    func testOrdinaryLocationsAreNot() {
        for path in ["/Applications/SetShot.app",
                     "/Users/someone/Applications/SetShot.app",
                     "/Users/someone/Downloads/SetShot.app",
                     "/Volumes/SetShot/SetShot.app"] {
            XCTAssertFalse(Translocation.isTranslocated(bundlePath: path), path)
        }
    }

    /// The suite runs from the built app, which is not translocated. If this ever
    /// fails the test environment itself is translocated and other results are suspect.
    func testTheTestHostIsNotTranslocated() {
        XCTAssertFalse(Translocation.isActive)
    }
}
