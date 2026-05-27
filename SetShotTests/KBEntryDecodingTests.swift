import XCTest
@testable import SetShot

final class KBEntryDecodingTests: XCTestCase {

    private func json(_ fields: String) -> Data {
        "[{\(fields)}]".data(using: .utf8)!
    }

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
}
