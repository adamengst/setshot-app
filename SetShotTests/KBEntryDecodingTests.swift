import XCTest
@testable import SetShot

final class KBEntryDecodingTests: XCTestCase {

    private func json(_ fields: String) -> Data {
        "[{\(fields)}]".data(using: .utf8)!
    }

    // All required non-optional fields. Removing any one of these causes the
    // entire [KBEntry] array decode to throw — the app then silently falls back
    // to the cached KB version. validate_kb.py in setshot-kb enforces this.
    private let base = """
        "id":"t","domain":"com.apple.test","key":"k","source":"defaults",
        "value_type":"string","ui_location":null,"settings_url":null,
        "noise":false,"noise_reason":null,"min_macos":"13.0","notes":null,
        "ai_generated":false,"contributed_by_issue":null,"value_map":null
        """

    func testValidEntryDecodes() throws {
        let data = json("\(base),\"description\":\"A setting\"")
        let entries = try JSONDecoder().decode([KBEntry].self, from: data)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].description, "A setting")
    }

    func testNullDescriptionDecodesAsNil() throws {
        let data = json("\(base),\"description\":null")
        let entries = try JSONDecoder().decode([KBEntry].self, from: data)
        XCTAssertNil(entries[0].description)
    }

    func testKeyPrefixDecodes() throws {
        let data = json("\(base),\"description\":\"d\",\"key_prefix\":\"folderActions.$objects[\"")
        let entries = try JSONDecoder().decode([KBEntry].self, from: data)
        XCTAssertEqual(entries[0].keyPrefix, "folderActions.$objects[")
    }

    func testNullKeyPrefixDecodesAsNil() throws {
        let data = json("\(base),\"description\":\"d\"")
        let entries = try JSONDecoder().decode([KBEntry].self, from: data)
        XCTAssertNil(entries[0].keyPrefix)
    }

    // MARK: - Required field coverage
    // Each test removes one required field and asserts the whole array decode fails.
    // If any of these tests start passing (decode succeeds), the field became
    // optional in KBEntry and validate_kb.py should be updated to match.

    private func baseDropping(_ field: String) -> Data {
        let pairs = base.split(separator: ",").map(String.init)
        let filtered = pairs.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("\"\(field)\"") }
        return "[{\(filtered.joined(separator: ","))}]".data(using: .utf8)!
    }

    func testMissingIdFailsDecode() {
        XCTAssertThrowsError(try JSONDecoder().decode([KBEntry].self, from: baseDropping("id")))
    }

    func testMissingDomainFailsDecode() {
        XCTAssertThrowsError(try JSONDecoder().decode([KBEntry].self, from: baseDropping("domain")))
    }

    func testMissingKeyFailsDecode() {
        XCTAssertThrowsError(try JSONDecoder().decode([KBEntry].self, from: baseDropping("key")))
    }

    func testMissingSourceFailsDecode() {
        XCTAssertThrowsError(try JSONDecoder().decode([KBEntry].self, from: baseDropping("source")))
    }

    func testMissingValueTypeFailsDecode() {
        XCTAssertThrowsError(try JSONDecoder().decode([KBEntry].self, from: baseDropping("value_type")))
    }

    func testMissingNoiseFailsDecode() {
        XCTAssertThrowsError(try JSONDecoder().decode([KBEntry].self, from: baseDropping("noise")))
    }

    func testMissingAiGeneratedFailsDecode() {
        XCTAssertThrowsError(try JSONDecoder().decode([KBEntry].self, from: baseDropping("ai_generated")))
    }
}
