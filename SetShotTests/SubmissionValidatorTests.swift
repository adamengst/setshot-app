import XCTest
@testable import SetShot

/// Every case here was verified against the deployed worker: each is refused with a
/// bare 400, which the sheet used to report as "Submission failed. Please try again"
/// — advice that cannot work, since the same text always fails.
final class SubmissionValidatorTests: XCTestCase {

    func testAcceptsOrdinaryNotes() {
        XCTAssertNil(SubmissionValidator.problem(withNotes: ""))
        XCTAssertNil(SubmissionValidator.problem(withNotes: "   \n "))
        XCTAssertNil(SubmissionValidator.problem(
            withNotes: "This shows Off but System Settings says the switch is on."))
    }

    func testAcceptsWhatTheWorkerNowAllows() {
        // The fix that prompted this: an address in angle brackets is accepted.
        XCTAssertNil(SubmissionValidator.problem(withNotes: "contact <name@example.com>"))
        XCTAssertNil(SubmissionValidator.problem(withNotes: "a < b and c > d"))
        XCTAssertNil(SubmissionValidator.problem(withNotes: "Choices[0] before Choices[1]"))
    }

    func testExplainsALink() {
        let problem = SubmissionValidator.problem(
            withNotes: "see https://support.apple.com/en-us/12345")
        XCTAssertNotNil(problem)
        XCTAssertTrue(problem!.contains("https://support.apple.com/en-us/12345"),
                      "It should quote what to remove: \(problem!)")
        XCTAssertNotNil(SubmissionValidator.problem(withNotes: "javascript:alert(1)"))
        XCTAssertNotNil(SubmissionValidator.problem(withNotes: "ftp://example.com/x"))
    }

    func testExplainsAngleBrackets() {
        for text in ["press <Tab> to move focus", "the <name> placeholder", "<script>x</script>"] {
            let problem = SubmissionValidator.problem(withNotes: text)
            XCTAssertNotNil(problem, text)
            XCTAssertTrue(problem!.contains("angle brackets"), problem ?? "")
        }
    }

    func testExplainsLengthWithTheNumbers() {
        let long = String(repeating: "a", count: SubmissionValidator.maxNotesLength + 25)
        let problem = SubmissionValidator.problem(withNotes: long)
        XCTAssertNotNil(problem)
        XCTAssertTrue(problem!.contains("25"), "It should say how much to cut: \(problem!)")
        XCTAssertNil(SubmissionValidator.problem(
            withNotes: String(repeating: "a", count: SubmissionValidator.maxNotesLength)))
    }
}
