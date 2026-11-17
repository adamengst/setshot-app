import XCTest
@testable import SetShot

/// The pointer's colors are four numbers each in com.apple.universalaccess, and a
/// comparison shows each color as one row valued as a hex code.
final class PointerColorTests: XCTestCase {

    private let plist = "/Users/someone/Library/Preferences/com.apple.universalaccess.plist"
    private let kb = KnowledgeBase(entries: [], version: 1, updatedAt: nil)

    private func snapshot(fill: (Double, Double, Double)?, outline: (Double, Double, Double)? = (1, 1, 1)) -> String {
        var lines: [String] = []
        for (name, rgb) in [("cursorFill", fill), ("cursorOutline", outline)] {
            guard let (r, g, b) = rgb else { continue }
            lines += ["\(plist) :: \(name).alpha = 1", "\(plist) :: \(name).blue = \(b)",
                      "\(plist) :: \(name).green = \(g)", "\(plist) :: \(name).red = \(r)"]
        }
        return lines.joined(separator: "\n") + "\n"
    }

    func testAColorReadsAsHex() {
        let s = snapshot(fill: (0.5791940689, 0.1280144453, 0.5726861358000001), outline: (0.9999960065, 1, 1))
        XCTAssertEqual(DiffEngine.pointerColor("cursorFill", from: s), "#942192")
        XCTAssertEqual(DiffEngine.pointerColor("cursorOutline", from: s), "#FFFFFF")
        XCTAssertNil(DiffEngine.pointerColor("cursorFill", from: "nothing here\n"))
    }

    // From Adam's Mac: only green changed, so the diff carries one component, and the
    // row still has to name the whole color on each side.
    func testOneChangedComponentIsOneRowForTheWholeColor() {
        let before = snapshot(fill: (1, 0.1280144453, 1))
        let after = snapshot(fill: (1, 0.2527923882, 1))
        let result = DiffEngine().parse(diffOutput: """
            -\(plist) :: cursorFill.green = 0.1280144453
            +\(plist) :: cursorFill.green = 0.2527923882
            """, kb: kb, beforeSnapshot: before, afterSnapshot: after)
        XCTAssertEqual(result.unrecognized.count, 1)
        let row = result.unrecognized.first
        XCTAssertEqual(row?.key, "cursorFill")
        XCTAssertEqual(row?.beforeValue, "#FF21FF")
        XCTAssertEqual(row?.afterValue, "#FF40FF")
    }

    func testFirstCustomisationReadsAsAnAddedColor() {
        let result = DiffEngine().parse(diffOutput: """
            +\(plist) :: cursorFill.alpha = 1
            +\(plist) :: cursorFill.blue = 0
            +\(plist) :: cursorFill.green = 0
            +\(plist) :: cursorFill.red = 1
            """, kb: kb, beforeSnapshot: snapshot(fill: nil), afterSnapshot: snapshot(fill: (1, 0, 0)))
        XCTAssertEqual(result.unrecognized.count, 1)
        XCTAssertEqual(result.unrecognized.first?.beforeValue, "")
        XCTAssertEqual(result.unrecognized.first?.afterValue, "#FF0000")
    }
}
