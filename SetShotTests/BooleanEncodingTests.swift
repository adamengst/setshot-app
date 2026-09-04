import XCTest
@testable import SetShot

/// The snapshot used to write integer and floating-point 0 and 1 as False and True,
/// which threw away the difference between a switch and a number. A mouse tracking
/// speed of exactly 1 was shown as "On"; a Magic Mouse gesture whose values run 0 to
/// 3 was shown as a switch next to the 2 it changed from.
///
/// Removing the coercion changes what roughly two thousand lines of a snapshot say —
/// about half the True/False lines on this Mac — so the pair of tests that matters
/// most is the second group: a snapshot written the old way and one written the new
/// way have to compare as unchanged, or the fix would strand every snapshot anyone
/// has already taken.
final class BooleanEncodingTests: XCTestCase {

    // MARK: - What the flattener writes

    private func flattened(_ plist: [String: Any]) -> String {
        var out = ""
        PlistFlattener.flatten(plist, prefix: "", line: "", into: &out)
        return out
    }

    func testABooleanIsStillWrittenAsTrueOrFalse() {
        XCTAssertEqual(flattened(["on": true, "off": false]), "off = False\non = True\n")
    }

    func testAnIntegerZeroOrOneIsWrittenAsANumber() {
        XCTAssertEqual(flattened(["a": 0, "b": 1, "c": 2]), "a = 0\nb = 1\nc = 2\n")
    }

    func testAFloatingPointOneIsWrittenAsANumber() {
        // The case that started this: com.apple.mouse.scaling holds 1 as a real
        // number, and it was arriving as True.
        XCTAssertEqual(flattened(["speed": 1.0]), "speed = 1\n")
        XCTAssertEqual(flattened(["speed": 0.6875]), "speed = 0.6875\n")
    }

    // MARK: - Comparing across the change

    /// Both forms of the same snapshot. Nothing here changed on the machine; the
    /// lines are the same settings written the two different ways.
    private static let oldForm = """
        com.example :: switch = True
        com.example :: gesture = True
        com.example :: speed = True
        com.example :: off = False
        """

    private static let newForm = """
        com.example :: switch = True
        com.example :: gesture = 1
        com.example :: speed = 1
        com.example :: off = 0
        """

    func testTheScriptsDiffReportsNothingAcrossTheChange() throws {
        let output = try TestSupport.runScriptDiff(before: Self.oldForm, after: Self.newForm)
        let changed = output.components(separatedBy: "\n").filter {
            ($0.hasPrefix("-") || $0.hasPrefix("+")) && !$0.hasPrefix("---") && !$0.hasPrefix("+++")
        }
        XCTAssertTrue(changed.isEmpty, """
            A snapshot taken before the flattener changed and one taken after hold the \
            same values written two ways. Reporting them would bury whatever else moved.

            \(changed.joined(separator: "\n"))
            """)
    }

    func testAValueThatGenuinelyChangedIsStillReported() throws {
        let after = Self.oldForm.replacingOccurrences(of: "gesture = True", with: "gesture = 3")
        let output = try TestSupport.runScriptDiff(before: Self.oldForm, after: after)
        XCTAssertTrue(output.contains("gesture = 3"),
                      "True and 3 are not the same value, whichever way either was written.")
    }

    func testOnAndOffAreNotFoldedTogether() throws {
        let after = Self.oldForm.replacingOccurrences(of: "switch = True", with: "switch = 0")
        let output = try TestSupport.runScriptDiff(before: Self.oldForm, after: after)
        XCTAssertTrue(output.contains("switch = 0"),
                      "True and 0 are opposite values; only True and 1 are the same one.")
    }

    func testTheEngineAgreesWithTheScript() throws {
        // The script's filter and the engine's own comparison both have to hold this,
        // since the app runs one through the other and the CLI runs only the first.
        let diff = try TestSupport.runScriptDiff(before: Self.oldForm, after: Self.newForm)
        let kb = KnowledgeBase(entries: [], version: 1, updatedAt: nil)
        let result = DiffEngine().parse(diffOutput: diff, kb: kb,
                                        beforeSnapshot: Self.oldForm, afterSnapshot: Self.newForm)
        XCTAssertEqual(result.recognized.count, 0)
        XCTAssertEqual(result.unrecognized.count, 0)
        XCTAssertEqual(result.noise.count, 0)
    }

    func testArraysAreLeftAloneWhereMatchingWouldBeGuesswork() throws {
        // Several lines share a key under an array index only when the index moves,
        // and pairing those up would be guesswork. This one is a genuine reordering,
        // not a recoding, and has to survive.
        let before = """
            com.example :: list[0] = True
            com.example :: list[1] = False
            """
        let after = """
            com.example :: list[0] = 0
            com.example :: list[1] = 1
            """
        let output = try TestSupport.runScriptDiff(before: before, after: after)
        XCTAssertTrue(output.contains("list[0] = 0"))
        XCTAssertTrue(output.contains("list[1] = 1"))
    }
}
