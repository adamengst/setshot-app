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

    /// A prefix entry, which is what makes the composed description differ from the
    /// KB's own text.
    private func makePrefixKBEntry(domain: String, keyPrefix: String) -> KBEntry {
        let json = """
        [{
            "id": "test.prefix", "domain": "\(domain)", "key": "",
            "key_prefix": "\(keyPrefix)", "source": "defaults", "value_type": "string",
            "description": "Generic description", "ui_location": null,
            "settings_url": null, "noise": false, "noise_reason": null,
            "min_macos": "13.0", "notes": null, "ai_generated": false,
            "contributed_by_issue": null, "value_map": null
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

    // The snapshot list and the journal both read the description stored here, so it
    // has to be the same text the comparison showed. Storing the KB's own wording made
    // a wallpaper row read "Wallpaper or screen saver set for a single display…" in the
    // list while the comparison said "Wallpaper placement on Built-in Display."

    func testJournalStoresTheComposedDescriptionNotTheKBWording() async throws {
        let key = "kTCCServiceCamera/com.apple.safari"
        let entry = makePrefixKBEntry(domain: "TCC-user", keyPrefix: "kTCCServiceCamera/")
        let diff = makeDiffLine(domain: "TCC-user", key: key)
        let added = await store.add(recognized: [(entry: entry, diff: diff)],
                                    afterSnapshot: makeSnapshot())

        let stored = try XCTUnwrap(added.first)
        XCTAssertEqual(stored.entryDescription, rowDescription(entry: entry, key: key))
        XCTAssertNotEqual(stored.entryDescription, entry.description,
                          "Storing the KB wording loses which app the row was about")
    }

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

    func testSameChangeDedupedAcrossSnapshots() async {
        let snap1 = makeSnapshot(id: "snap1.txt.gz", date: Date(timeIntervalSince1970: 1_000_000))
        let snap2 = makeSnapshot(id: "snap2.txt.gz", date: Date(timeIntervalSince1970: 2_000_000))
        let recognized = [(entry: makeKBEntry(), diff: makeDiffLine())]
        _ = await store.add(recognized: recognized, afterSnapshot: snap1)
        let entries = await store.add(recognized: recognized, afterSnapshot: snap2)
        XCTAssertEqual(entries.count, 1, "Same domain+key+values across different snapshots should not duplicate")
        XCTAssertEqual(entries[0].afterSnapshotId, snap1.id, "Older entry should be kept")
    }

    func testDifferentValuesSameKeyProduceSeparateEntries() async {
        let snap1 = makeSnapshot(id: "snap1.txt.gz", date: Date(timeIntervalSince1970: 1_000_000))
        let snap2 = makeSnapshot(id: "snap2.txt.gz", date: Date(timeIntervalSince1970: 2_000_000))
        _ = await store.add(recognized: [(entry: makeKBEntry(), diff: makeDiffLine(before: "False", after: "True"))], afterSnapshot: snap1)
        let entries = await store.add(recognized: [(entry: makeKBEntry(), diff: makeDiffLine(before: "True", after: "False"))], afterSnapshot: snap2)
        XCTAssertEqual(entries.count, 2, "Same key with different old/new values should produce separate entries")
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
        _ = await store.add(recognized: [(entry: makeKBEntry(), diff: makeDiffLine(before: "False", after: "True"))], afterSnapshot: snap1)
        _ = await store.add(recognized: [(entry: makeKBEntry(), diff: makeDiffLine(before: "True", after: "False"))], afterSnapshot: snap2)
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

    func testRoundTripThroughEmptyCancelsXToEmpty() async {
        // X → ∅ followed by ∅ → X should cancel both entries (pref domain temporarily deleted)
        let snap1 = makeSnapshot(id: "snap1.txt.gz", date: Date(timeIntervalSince1970: 1_000_000))
        let snap2 = makeSnapshot(id: "snap2.txt.gz", date: Date(timeIntervalSince1970: 2_000_000))
        _ = await store.add(recognized: [(entry: makeKBEntry(), diff: makeDiffLine(before: "True", after: ""))], afterSnapshot: snap1)
        let entries = await store.add(recognized: [(entry: makeKBEntry(), diff: makeDiffLine(before: "", after: "True"))], afterSnapshot: snap2)
        XCTAssertTrue(entries.isEmpty, "X→∅→X round-trip should cancel both entries")
    }

    func testRoundTripThroughEmptyCancelsEmptyToX() async {
        // ∅ → X followed by X → ∅ should also cancel (inverse direction)
        let snap1 = makeSnapshot(id: "snap1.txt.gz", date: Date(timeIntervalSince1970: 1_000_000))
        let snap2 = makeSnapshot(id: "snap2.txt.gz", date: Date(timeIntervalSince1970: 2_000_000))
        _ = await store.add(recognized: [(entry: makeKBEntry(), diff: makeDiffLine(before: "", after: "True"))], afterSnapshot: snap1)
        let entries = await store.add(recognized: [(entry: makeKBEntry(), diff: makeDiffLine(before: "True", after: ""))], afterSnapshot: snap2)
        XCTAssertTrue(entries.isEmpty, "∅→X→∅ round-trip should cancel both entries")
    }

    func testReloadPicksUpChangesWrittenByAnotherInstance() async {
        // Scheduled snapshots run as a separate `--background-snapshot` process,
        // so a long-running foreground app's JournalStore instance sees stale
        // data via load() until it calls reload().
        let snap1 = makeSnapshot(id: "snap1.txt.gz", date: Date(timeIntervalSince1970: 1_000_000))
        let snap2 = makeSnapshot(id: "snap2.txt.gz", date: Date(timeIntervalSince1970: 2_000_000))

        _ = await store.add(recognized: [(entry: makeKBEntry(key: "KeyA"), diff: makeDiffLine(key: "KeyA"))], afterSnapshot: snap1)
        _ = await store.load()

        let otherProcess = JournalStore(fileURL: tempURL)
        _ = await otherProcess.add(recognized: [(entry: makeKBEntry(key: "KeyB"), diff: makeDiffLine(key: "KeyB"))], afterSnapshot: snap2)

        let stale = await store.load()
        XCTAssertEqual(stale.count, 1, "load() should return the cached value, not re-read disk")

        let fresh = await store.reload()
        XCTAssertEqual(fresh.count, 2, "reload() should re-read disk and see entries added by another process")
        XCTAssertTrue(fresh.contains { $0.key == "KeyB" })
    }

    func testNonEmptyRoundTripNotCancelled() async {
        // A → B → A with no empty values must NOT cancel (could be a deliberate toggle)
        let snap1 = makeSnapshot(id: "snap1.txt.gz", date: Date(timeIntervalSince1970: 1_000_000))
        let snap2 = makeSnapshot(id: "snap2.txt.gz", date: Date(timeIntervalSince1970: 2_000_000))
        _ = await store.add(recognized: [(entry: makeKBEntry(), diff: makeDiffLine(before: "False", after: "True"))], afterSnapshot: snap1)
        let entries = await store.add(recognized: [(entry: makeKBEntry(), diff: makeDiffLine(before: "True", after: "False"))], afterSnapshot: snap2)
        XCTAssertEqual(entries.count, 2, "Non-empty round-trip should not be cancelled")
    }
}
