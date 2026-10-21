import XCTest
@testable import SetShot

/// The address and message rules match worker.js's validateSupport, which was checked
/// against the same cases with a mocked GitHub API.
final class SupportRequestTests: XCTestCase {

    private let diagnostics = SupportDiagnostics(
        appVersion: "1.0b31 (43)", kbVersion: "212", macOSVersion: "27.0 (26A123)",
        macModel: "Mac16,10", fullDiskAccess: "Granted", mediaAccess: "Not requested")

    private func json(_ request: SupportRequest) throws -> [String: Any] {
        let data = try JSONEncoder().encode(request)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testEncodesWhatTheWorkerExpects() throws {
        let object = try json(SupportRequest(kind: .suggestion, message: "  Dark icons, please \n",
                                             email: " name@example.com ", diagnostics: diagnostics))
        XCTAssertEqual(object["kind"] as? String, "suggestion")
        XCTAssertEqual(object["message"] as? String, "Dark icons, please")
        XCTAssertEqual(object["email"] as? String, "name@example.com")
        let d = try XCTUnwrap(object["diagnostics"] as? [String: String])
        XCTAssertEqual(Set(d.keys), ["app_version", "kb_version", "macos_version",
                                     "mac_model", "full_disk_access", "media_access"])
        XCTAssertEqual(d["macos_version"], "27.0 (26A123)")
    }

    func testBlankAddressAndDiagnosticsAreLeftOut() throws {
        let object = try json(SupportRequest(kind: .bug, message: "It hangs",
                                             email: "   ", diagnostics: nil))
        XCTAssertNil(object["email"], "A blank field means no reply is wanted, not an invalid address")
        XCTAssertNil(object["diagnostics"])
    }

    func testCurrentDiagnosticsAreFilledIn() {
        let current = SupportDiagnostics.current()
        let major = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        XCTAssertTrue(current.macOSVersion.hasPrefix("\(major)."), current.macOSVersion)
        XCTAssertTrue(current.macOSVersion.contains("("), "The build number should follow: \(current.macOSVersion)")
        XCTAssertNotEqual(current.macModel, "unknown")
        XCTAssertEqual(current.rows.count, 6)
    }

    func testAcceptsOrdinaryAddresses() {
        for address in ["", "  ", "name@example.com", "o'brien+setshot@mail.example.co.uk",
                        "first.last-x@sub-domain.example.org"] {
            XCTAssertNil(SubmissionValidator.problem(withEmail: address), address)
        }
    }

    func testExplainsAnAddressTheWorkerRefuses() {
        for address in ["name", "name@example", "a b@example.com", "a@b.com?cc=c@d.com",
                        "<a@b.com>", "a@b.com (work)", "a@b..com"] {
            let problem = SubmissionValidator.problem(withEmail: address)
            XCTAssertNotNil(problem, address)
        }
        let problem = SubmissionValidator.problem(withEmail: "name@example")!
        XCTAssertTrue(problem.contains("name@example"), "It should quote the address: \(problem)")
    }

    func testSupportMessagesMayContainLinksAndBrackets() {
        XCTAssertNil(SubmissionValidator.problem(
            withSupportMessage: "See https://talk.tidbits.com/t/123 — the <Tab> key does nothing"))
    }

    func testExplainsAnOverlongMessage() {
        let limit = SubmissionValidator.maxSupportMessageLength
        XCTAssertNil(SubmissionValidator.problem(withSupportMessage: String(repeating: "a", count: limit)))
        let problem = SubmissionValidator.problem(
            withSupportMessage: String(repeating: "a", count: limit + 12))
        XCTAssertTrue(problem?.contains("12") == true, problem ?? "nil")
    }
}
