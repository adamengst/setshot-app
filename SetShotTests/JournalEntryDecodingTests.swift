import XCTest
@testable import SetShot

final class JournalEntryDecodingTests: XCTestCase {

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private func makeEntry(
        afterSnapshotId: String = "snap1",
        domain: String = "com.apple.test",
        key: String = "SomeKey",
        description: String = "A setting description",
        uiLocation: String? = "System Settings → Test",
        settingsURL: String? = "x-apple.systempreferences:com.apple.Test",
        oldValue: String = "Off",
        newValue: String = "On"
    ) -> JournalEntry {
        JournalEntry(
            id: UUID(),
            afterSnapshotId: afterSnapshotId,
            afterSnapshotDate: Date(timeIntervalSince1970: 1_000_000),
            afterSnapshotName: "Test Snapshot",
            domain: domain,
            key: key,
            entryDescription: description,
            uiLocation: uiLocation,
            settingsURL: settingsURL,
            oldValue: oldValue,
            newValue: newValue,
            addedAt: Date(timeIntervalSince1970: 1_000_001)
        )
    }

    func testRoundTrip() throws {
        let original = makeEntry()
        let data = try encoder.encode([original])
        let decoded = try decoder.decode([JournalEntry].self, from: data)
        XCTAssertEqual(decoded.count, 1)
        let e = decoded[0]
        XCTAssertEqual(e.id, original.id)
        XCTAssertEqual(e.afterSnapshotId, "snap1")
        XCTAssertEqual(e.domain, "com.apple.test")
        XCTAssertEqual(e.key, "SomeKey")
        XCTAssertEqual(e.entryDescription, "A setting description")
        XCTAssertEqual(e.uiLocation, "System Settings → Test")
        XCTAssertEqual(e.settingsURL, "x-apple.systempreferences:com.apple.Test")
        XCTAssertEqual(e.oldValue, "Off")
        XCTAssertEqual(e.newValue, "On")
    }

    func testNullableFieldsRoundTrip() throws {
        let original = makeEntry(uiLocation: nil, settingsURL: nil)
        let data = try encoder.encode([original])
        let decoded = try decoder.decode([JournalEntry].self, from: data)
        XCTAssertNil(decoded[0].uiLocation)
        XCTAssertNil(decoded[0].settingsURL)
    }

    func testEmptyArrayRoundTrip() throws {
        let data = try encoder.encode([JournalEntry]())
        let decoded = try decoder.decode([JournalEntry].self, from: data)
        XCTAssertTrue(decoded.isEmpty)
    }
}
