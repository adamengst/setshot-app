import XCTest
@testable import SetShot

/// AboutView holds the help text twice: once in the `aboutHelpContent` array, which
/// the non-search path renders as a single NSTextView so text can be selected across
/// paragraphs, and once as SwiftUI views the search path renders so each paragraph can
/// carry an id and be scrolled to. Nothing makes the two agree — they compile
/// independently, and every test passes with them saying different things — so they had
/// drifted in three paragraphs before this test existed, telling users with the search
/// field open something different from users without.
///
/// Read out of the source rather than at runtime: the array is private, and the view
/// copy exists only inside view builders, so there is nothing to enumerate once built.
final class AboutViewCopiesTests: XCTestCase {

    private static let sourceURL = TestSupport.repoRoot
        .appendingPathComponent("SetShot/Views/AboutView.swift")

    /// Captures the raw source text between the quotes, escapes and all, so the two are
    /// compared as written rather than as rendered — `\u{2014}` on one side and a
    /// literal em dash on the other would compile the same but is still worth catching.
    private static let stringBody = #"((?:[^"\\]|\\.)*)"#

    private struct Item { let kind: String; let text: String }

    private func items(in source: String, pattern: String, kinds: [String: String]) throws -> [Item] {
        let regex = try NSRegularExpression(pattern: pattern)
        let ns = source as NSString
        return regex.matches(in: source, range: NSRange(location: 0, length: ns.length))
            .map { Item(kind: kinds[ns.substring(with: $0.range(at: 1))]!,
                        text: ns.substring(with: $0.range(at: 2))) }
    }

    func testTheTwoCopiesOfTheHelpTextAreIdentical() throws {
        let source = try String(contentsOf: Self.sourceURL, encoding: .utf8)

        // The array is above the view code; "// MARK: - Sections" divides them.
        let parts = source.components(separatedBy: "// MARK: - Sections")
        XCTAssertEqual(parts.count, 2, "AboutView.swift no longer has a single Sections marker")
        guard let arraySource = parts.first?.components(separatedBy: "private let aboutHelpContent").last
        else { return XCTFail("aboutHelpContent not found") }
        let viewSource = parts[1]

        let array = try items(in: arraySource,
                              pattern: #"\.(intro|paragraph|bullet)\(""# + Self.stringBody + #"""#,
                              kinds: ["intro": "paragraph", "paragraph": "paragraph", "bullet": "bullet"])
        let views = try items(in: viewSource,
                              pattern: #"Help(Paragraph|Bullet)\(""# + Self.stringBody + #"""#,
                              kinds: ["Paragraph": "paragraph", "Bullet": "bullet"])

        XCTAssertFalse(array.isEmpty, "No help text found in the array — has its shape changed?")
        XCTAssertEqual(array.count, views.count, """
            The two copies of the About text have a different number of entries \
            (array \(array.count), views \(views.count)). One gained a paragraph the \
            other did not.
            """)
        guard array.count == views.count else { return }

        // Kinds first: a paragraph facing a bullet means the two have been reordered, and
        // comparing text position by position past that point reports nonsense.
        for (index, pair) in zip(array, views).enumerated() where pair.0.kind != pair.1.kind {
            return XCTFail("""
                Entry \(index) is a \(pair.0.kind) in the array and a \(pair.1.kind) in the \
                views — the two copies are in different orders.
                """)
        }

        let mismatched = zip(array, views).enumerated()
            .filter { $0.element.0.text != $0.element.1.text }
        XCTAssertTrue(mismatched.isEmpty, """
            \(mismatched.count) paragraph(s) differ between the two copies of the About \
            text. Both have to be edited together.

            \(mismatched.map { index, pair in
                "[\(index)]\n  array: \(pair.0.text)\n  views: \(pair.1.text)"
            }.joined(separator: "\n\n"))
            """)
    }
}
