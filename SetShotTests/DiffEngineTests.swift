import XCTest
@testable import SetShot

final class DiffEngineTests: XCTestCase {

    private func makeEntry(domain: String, key: String = "", keyPrefix: String? = nil, noise: Bool = false) -> KBEntry {
        KBEntry(
            id: "\(domain).\(key)", domain: domain, key: key, source: "defaults",
            valueType: "string", description: "Test",
            uiLocation: nil, settingsURL: nil,
            noise: noise, noiseReason: noise ? "test" : nil,
            minMacOS: "13.0", notes: nil, aiGenerated: false,
            contributedByIssue: nil, valueMap: nil, keyPrefix: keyPrefix
        )
    }

    private func engine() -> DiffEngine { DiffEngine() }

    func testRecognisedEntry() {
        let kb = KnowledgeBase(entries: [makeEntry(domain: "com.apple.dock", key: "show-recents")], version: 1)
        let result = engine().parse(diffOutput: """
            -com.apple.dock :: show-recents = 1
            +com.apple.dock :: show-recents = 0
            """, kb: kb)
        XCTAssertEqual(result.recognised.count, 1)
        XCTAssertEqual(result.unrecognised.count, 0)
        XCTAssertEqual(result.noise.count, 0)
    }

    func testUnrecognisedEntry() {
        let kb = KnowledgeBase(entries: [], version: 1)
        let result = engine().parse(diffOutput: """
            -com.apple.dock :: unknown-key = 1
            +com.apple.dock :: unknown-key = 0
            """, kb: kb)
        XCTAssertEqual(result.unrecognised.count, 1)
        XCTAssertEqual(result.recognised.count, 0)
    }

    func testNoiseEntry() {
        let kb = KnowledgeBase(entries: [makeEntry(domain: "com.apple.FolderActionsDispatcher", keyPrefix: "folderActions.$objects[", noise: true)], version: 1)
        let result = engine().parse(diffOutput: """
            -com.apple.FolderActionsDispatcher :: folderActions.$objects[7] = old.pdf
            +com.apple.FolderActionsDispatcher :: folderActions.$objects[7] = new.pdf
            """, kb: kb)
        XCTAssertEqual(result.noise.count, 1)
        XCTAssertEqual(result.unrecognised.count, 0)
    }

    func testSemanticDuplicatesSkipped() {
        // "1" and "true" are semantically equal — should not appear in results
        let kb = KnowledgeBase(entries: [], version: 1)
        let result = engine().parse(diffOutput: """
            -com.apple.dock :: show-recents = 1
            +com.apple.dock :: show-recents = true
            """, kb: kb)
        XCTAssertEqual(result.unrecognised.count, 0)
    }

    func testDomainNormalisationStripsPath() {
        let kb = KnowledgeBase(entries: [makeEntry(domain: "com.apple.dock", key: "show-recents")], version: 1)
        let result = engine().parse(diffOutput: """
            -/Users/adam/Library/Preferences/com.apple.dock.plist :: show-recents = 1
            +/Users/adam/Library/Preferences/com.apple.dock.plist :: show-recents = 0
            """, kb: kb)
        XCTAssertEqual(result.recognised.count, 1)
    }

    func testBeforeAndAfterValuesExtracted() {
        let kb = KnowledgeBase(entries: [], version: 1)
        let result = engine().parse(diffOutput: """
            -com.apple.dock :: autohide = 0
            +com.apple.dock :: autohide = 1
            """, kb: kb)
        XCTAssertEqual(result.unrecognised.first?.beforeValue, "0")
        XCTAssertEqual(result.unrecognised.first?.afterValue, "1")
    }

    func testMixedResults() {
        let kb = KnowledgeBase(entries: [
            makeEntry(domain: "com.apple.dock", key: "show-recents"),
            makeEntry(domain: "com.apple.dock", key: "autohide-delay", noise: true),
        ], version: 1)
        let result = engine().parse(diffOutput: """
            -com.apple.dock :: show-recents = 1
            +com.apple.dock :: show-recents = 0
            -com.apple.dock :: autohide-delay = 0.5
            +com.apple.dock :: autohide-delay = 0.2
            -com.apple.dock :: unknown = foo
            +com.apple.dock :: unknown = bar
            """, kb: kb)
        XCTAssertEqual(result.recognised.count, 1)
        XCTAssertEqual(result.noise.count, 1)
        XCTAssertEqual(result.unrecognised.count, 1)
    }
}
