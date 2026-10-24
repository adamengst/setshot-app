import XCTest
@testable import SetShot

/// Contact Support opens beside the main window: right if it fits, else left, 8 points
/// away — the same gap as comparison windows — with the top edges aligned, and over the
/// main window only when neither side has room. Frames are in AppKit's coordinates,
/// with y increasing upward.
final class WindowPlacementTests: XCTestCase {

    private let screen = NSRect(x: 0, y: 0, width: 2000, height: 1200)
    private let support = NSSize(width: 480, height: 644)

    func testGoesRightWhenThereIsRoom() {
        let main = NSRect(x: 200, y: 300, width: 750, height: 760)
        let origin = WindowPlacement.originBeside(main, size: support, within: screen)
        XCTAssertEqual(origin, NSPoint(x: 958, y: 1060 - 644))
    }

    func testGoesLeftWhenTheRightIsFull() {
        let main = NSRect(x: 1100, y: 300, width: 750, height: 760)
        let origin = WindowPlacement.originBeside(main, size: support, within: screen)
        XCTAssertEqual(origin, NSPoint(x: 1100 - 8 - 480, y: 1060 - 644))
    }

    func testFitsExactlyAgainstTheScreenEdge() {
        // 1512 + 8 + 480 = 2000, the screen's right edge.
        let main = NSRect(x: 762, y: 300, width: 750, height: 760)
        XCTAssertEqual(WindowPlacement.originBeside(main, size: support, within: screen)?.x, 1520)
    }

    func testNilWhenNeitherSideHasRoom() {
        let main = NSRect(x: 300, y: 300, width: 1400, height: 760)
        XCTAssertNil(WindowPlacement.originBeside(main, size: support, within: screen))
    }

    func testKeepsTheBottomOnScreenWhenTheMainWindowIsShort() {
        // Top-aligned, the support window would end 344 points below the screen.
        let main = NSRect(x: 200, y: 0, width: 750, height: 300)
        let origin = WindowPlacement.originBeside(main, size: support, within: screen)
        XCTAssertEqual(origin?.y, 0)
    }

    func testRespectsAVisibleFrameThatDoesNotStartAtZero() {
        // A second display to the left, with the Dock along its bottom.
        let visible = NSRect(x: -1600, y: 80, width: 1600, height: 900)
        let main = NSRect(x: -700, y: 200, width: 600, height: 400)
        let origin = WindowPlacement.originBeside(main, size: support, within: visible)
        XCTAssertEqual(origin, NSPoint(x: -700 - 8 - 480, y: 80),
                       "Right would cross x = 0, so left; the bottom stops at the Dock")
    }
}
