import XCTest
@testable import SetShot

final class JournalStoreTests: XCTestCase {

    private var tempURL: URL!
    private var store: JournalStore!

    override func setUp() async throws {
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".json")
        store = JournalStore(fileURL: tempURL)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempURL)
    }

    // MARK: - Helpers

    private func makeKBEntry(domain: String = "com.apple.test", key: String = "SomeKey") -> KBEntry {
        let json = """
        [{
            "id": "test.\(key)",
            "domain": "\(domain)",
            "key": "\(key)",
            "source": "defaults",
            "value_type": "boolean",
            "description": "Test description for \(key)",
            "ui_location": "System Settings → Test",
            "settings_url": null,
            "noise": false,
            "noise_reason": null,
            "min_macos": "13.0",
            "notes": null,
            "ai_generated": false,
            "contributed_by_issue": null,
            "value_map": null
        }]
        """.data(using: .utf8)!
        return (try! JSONDecoder().decode([KBEntry].self, from: json))[0]
    }

    private func makeDiffLine(domain: String = "com.apple.test", key: String = "SomeKey",
                               before: String = "False", after: String = "True") -> DiffLine {
        DiffLine(domain: domain, key: key, source: "defaults",
                 beforeValue: before, afterValue: after,
                 macOSVersion: "15.0", rawLine: "\(domain) :: \(key)")
    }

    private func makeSnapshot(id: String = "setshot_2026-01-01_1200.txt.gz", date: Date = Date()) -> StoredSnapshot {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(id)
        return StoredSnapshot(url: url, date: date, customLabel: nil)
    }

    // MARK: - Tests

    func testAddNewEntries() async {
        let snapshot = makeSnapshot()
        let recognized = [(entry: makeKBEntry(), diff: makeDiffLine())]
        let entries = await store.add(recognized: recognized, afterSnapshot: snapshot)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].key, "SomeKey")
        XCTAssertEqual(entries[0].oldValue, "False")
        XCTAssertEqual(entries[0].newValue, "True")
    }

    func testDeduplicationPreventsRepeats() async {
        let snapshot = makeSnapshot()
        let recognized = [(entry: makeKBEntry(), diff: makeDiffLine())]
        _ = await store.add(recognized: recognized, afterSnapshot: snapshot)
        let entries = await store.add(recognized: recognized, afterSnapshot: snapshot)
        XCTAssertEqual(entries.count, 1, "Re-running the same comparison should not duplicate entries")
    }

    func testNewlyRecognizedEntryAddedOnRerun() async {
        let snapshot = makeSnapshot()
        let first = [(entry: makeKBEntry(key: "KeyA"), diff: makeDiffLine(key: "KeyA"))]
        _ = await store.add(recognized: first, afterSnapshot: snapshot)

        let second = [
            (entry: makeKBEntry(key: "KeyA"), diff: makeDiffLine(key: "KeyA")),
            (entry: makeKBEntry(key: "KeyB"), diff: makeDiffLine(key: "KeyB")),
        ]
        let entries = await store.add(recognized: second, afterSnapshot: snapshot)
        XCTAssertEqual(entries.count, 2, "KeyB should be added even though KeyA already exists")
        XCTAssertTrue(entries.contains { $0.key == "KeyB" })
    }

    func testDifferentSnapshotsProduceSeparateEntries() async {
        let snap1 = makeSnapshot(id: "snap1.txt.gz", date: Date(timeIntervalSince1970: 1_000_000))
        let snap2 = makeSnapshot(id: "snap2.txt.gz", date: Date(timeIntervalSince1970: 2_000_000))
        let recognized = [(entry: makeKBEntry(), diff: makeDiffLine())]
        _ = await store.add(recognized: recognized, afterSnapshot: snap1)
        let entries = await store.add(recognized: recognized, afterSnapshot: snap2)
        XCTAssertEqual(entries.count, 2, "Same key from different After snapshots should both be journaled")
    }

    func testDeleteEntry() async {
        let snapshot = makeSnapshot()
        let recognized = [
            (entry: makeKBEntry(key: "KeyA"), diff: makeDiffLine(key: "KeyA")),
            (entry: makeKBEntry(key: "KeyB"), diff: makeDiffLine(key: "KeyB")),
        ]
        var entries = await store.add(recognized: recognized, afterSnapshot: snapshot)
        let toDelete = entries.first(where: { $0.key == "KeyA" })!
        entries = await store.delete(entryID: toDelete.id)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].key, "KeyB")
    }

    func testDeleteSection() async {
        let snap1 = makeSnapshot(id: "snap1.txt.gz", date: Date(timeIntervalSince1970: 1_000_000))
        let snap2 = makeSnapshot(id: "snap2.txt.gz", date: Date(timeIntervalSince1970: 2_000_000))
        let recognized = [(entry: makeKBEntry(), diff: makeDiffLine())]
        _ = await store.add(recognized: recognized, afterSnapshot: snap1)
        _ = await store.add(recognized: recognized, afterSnapshot: snap2)
        let entries = await store.delete(afterSnapshotId: snap1.id)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].afterSnapshotId, snap2.id)
    }

    func testPersistenceRoundTrip() async {
        let snapshot = makeSnapshot()
        let recognized = [(entry: makeKBEntry(), diff: makeDiffLine())]
        _ = await store.add(recognized: recognized, afterSnapshot: snapshot)

        let freshStore = JournalStore(fileURL: tempURL)
        let loaded = await freshStore.load()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].key, "SomeKey")
    }

    func testLoadReturnsEmptyWhenFileAbsent() async {
        let entries = await store.load()
        XCTAssertTrue(entries.isEmpty)
    }
}
