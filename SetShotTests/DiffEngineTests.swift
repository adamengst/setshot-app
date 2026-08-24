import XCTest
@testable import SetShot

final class DiffEngineTests: XCTestCase {

    private func makeEntry(domain: String, key: String = "", keyPrefix: String? = nil, noise: Bool = false) -> KBEntry {
        KBEntry(
            id: "\(domain).\(key)", domain: domain, key: key, source: "defaults",
            valueType: "string", description: "Test",
            uiLocation: nil, uiLocationOverrides: nil, settingsURL: nil,
            noise: noise, noiseReason: noise ? "test" : nil,
            minMacOS: "13.0", notes: nil, aiGenerated: false,
            contributedByIssue: nil, valueMap: nil, keyPrefix: keyPrefix, iconBundleID: nil, implicitDefault: nil, requiresHardware: nil
        )
    }

    private func engine() -> DiffEngine { DiffEngine() }

    func testRecognizedEntry() {
        let kb = KnowledgeBase(entries: [makeEntry(domain: "com.apple.dock", key: "show-recents")], version: 1, updatedAt: nil)
        let result = engine().parse(diffOutput: """
            -com.apple.dock :: show-recents = 1
            +com.apple.dock :: show-recents = 0
            """, kb: kb)
        XCTAssertEqual(result.recognized.count, 1)
        XCTAssertEqual(result.unrecognized.count, 0)
        XCTAssertEqual(result.noise.count, 0)
    }

    func testUnrecognizedEntry() {
        let kb = KnowledgeBase(entries: [], version: 1, updatedAt: nil)
        let result = engine().parse(diffOutput: """
            -com.apple.dock :: unknown-key = 1
            +com.apple.dock :: unknown-key = 0
            """, kb: kb)
        XCTAssertEqual(result.unrecognized.count, 1)
        XCTAssertEqual(result.recognized.count, 0)
    }

    func testNoiseEntry() {
        let kb = KnowledgeBase(entries: [makeEntry(domain: "com.apple.FolderActionsDispatcher", keyPrefix: "folderActions.$objects[", noise: true)], version: 1, updatedAt: nil)
        let result = engine().parse(diffOutput: """
            -com.apple.FolderActionsDispatcher :: folderActions.$objects[7] = old.pdf
            +com.apple.FolderActionsDispatcher :: folderActions.$objects[7] = new.pdf
            """, kb: kb)
        XCTAssertEqual(result.noise.count, 1)
        XCTAssertEqual(result.unrecognized.count, 0)
    }

    // MARK: - Privacy permissions
    //
    // Reading the TCC databases needs Full Disk Access, so the snapshot carries
    // `TCC :: available` to separate "a permission changed" from "SetShot can
    // suddenly see all of them".

    private func tccKB() -> KnowledgeBase {
        KnowledgeBase(entries: [
            makeEntry(domain: "TCC", key: "available"),
            makeEntry(domain: "TCC-user", keyPrefix: "kTCCServiceMediaLibrary/"),
            makeEntry(domain: "TCC-system", keyPrefix: "kTCCServiceSystemPolicyAllFiles/"),
        ], version: 1, updatedAt: nil)
    }

    func testMediaAndMusicGrantIsReported() {
        let result = engine().parse(diffOutput: """
            -TCC-user :: kTCCServiceMediaLibrary/com.tidbits.SetShot = 0
            +TCC-user :: kTCCServiceMediaLibrary/com.tidbits.SetShot = 2
            """, kb: tccKB())
        XCTAssertEqual(result.recognized.count, 1)
        XCTAssertEqual(result.recognized.first?.diff.key, "kTCCServiceMediaLibrary/com.tidbits.SetShot")
        XCTAssertEqual(result.recognized.first?.diff.afterValue, "2")
    }

    func testFullDiskAccessGrantToAnotherAppIsReported() {
        let result = engine().parse(diffOutput: """
            -TCC-system :: kTCCServiceSystemPolicyAllFiles/com.example.tool = 0
            +TCC-system :: kTCCServiceSystemPolicyAllFiles/com.example.tool = 2
            """, kb: tccKB())
        XCTAssertEqual(result.recognized.count, 1)
        XCTAssertEqual(result.recognized.first?.diff.key,
                       "kTCCServiceSystemPolicyAllFiles/com.example.tool")
    }

    func testGainingFullDiskAccessSuppressesTheFloodOfPermissions() {
        // Every grant on the Mac becomes visible at once. Report the capability
        // change, not two hundred spurious additions.
        let result = engine().parse(diffOutput: """
            -TCC :: available = 0
            +TCC :: available = 1
            +TCC-user :: kTCCServiceMediaLibrary/com.apple.Music = 2
            +TCC-user :: kTCCServiceCamera/us.zoom.xos = 2
            +TCC-system :: kTCCServiceSystemPolicyAllFiles/com.tidbits.SetShot = 2
            """, kb: tccKB())

        XCTAssertEqual(result.recognized.count, 1)
        XCTAssertEqual(result.recognized.first?.diff.key, "available")
        XCTAssertTrue(result.unrecognized.isEmpty, "Permission rows should be withheld")
        XCTAssertTrue(result.limitedAccessWarning?.contains("granted Full Disk Access") == true,
                      "Expected an explanation, got: \(result.limitedAccessWarning ?? "nil")")
    }

    func testOlderSnapshotWithNoTCCDataIsTreatedAsNotReadable() {
        // Snapshots taken before SetShot captured privacy permissions have no
        // `TCC :: available` line at all — the key is absent rather than 0. Comparing
        // one of those against a snapshot taken with Full Disk Access is exactly the
        // flood this suppression exists for, so an absent value has to count.
        let result = engine().parse(diffOutput: """
            +TCC :: available = 1
            +TCC-user :: kTCCServiceCamera/us.zoom.xos = 2
            +TCC-user :: kTCCServiceMicrophone/com.example.a = 2
            +TCC-system :: kTCCServiceSystemPolicyAllFiles/com.example.b = 2
            """, kb: tccKB())

        XCTAssertEqual(result.recognized.count, 1)
        XCTAssertEqual(result.recognized.first?.diff.key, "available")
        XCTAssertTrue(result.unrecognized.isEmpty, "Permission rows should be withheld")
        XCTAssertTrue(result.limitedAccessWarning?.contains("granted Full Disk Access") == true)
    }

    func testLosingFullDiskAccessSuppressesTheFloodOfPermissions() {
        let result = engine().parse(diffOutput: """
            -TCC :: available = 1
            +TCC :: available = 0
            -TCC-user :: kTCCServiceMediaLibrary/com.apple.Music = 2
            -TCC-system :: kTCCServiceSystemPolicyAllFiles/com.tidbits.SetShot = 2
            """, kb: tccKB())

        XCTAssertEqual(result.recognized.count, 1)
        XCTAssertTrue(result.unrecognized.isEmpty)
        XCTAssertTrue(result.limitedAccessWarning?.contains("lost Full Disk Access") == true)
    }

    func testSemanticDuplicatesSkipped() {
        // "1" and "true" are semantically equal — should not appear in results
        let kb = KnowledgeBase(entries: [], version: 1, updatedAt: nil)
        let result = engine().parse(diffOutput: """
            -com.apple.dock :: show-recents = 1
            +com.apple.dock :: show-recents = true
            """, kb: kb)
        XCTAssertEqual(result.unrecognized.count, 0)
    }

    func testDomainNormalisationStripsPath() {
        let kb = KnowledgeBase(entries: [makeEntry(domain: "com.apple.dock", key: "show-recents")], version: 1, updatedAt: nil)
        let result = engine().parse(diffOutput: """
            -/Users/adam/Library/Preferences/com.apple.dock.plist :: show-recents = 1
            +/Users/adam/Library/Preferences/com.apple.dock.plist :: show-recents = 0
            """, kb: kb)
        XCTAssertEqual(result.recognized.count, 1)
    }

    func testBeforeAndAfterValuesExtracted() {
        let kb = KnowledgeBase(entries: [], version: 1, updatedAt: nil)
        let result = engine().parse(diffOutput: """
            -com.apple.dock :: autohide = 0
            +com.apple.dock :: autohide = 1
            """, kb: kb)
        XCTAssertEqual(result.unrecognized.first?.beforeValue, "0")
        XCTAssertEqual(result.unrecognized.first?.afterValue, "1")
    }

    func testMixedResults() {
        let kb = KnowledgeBase(entries: [
            makeEntry(domain: "com.apple.dock", key: "show-recents"),
            makeEntry(domain: "com.apple.dock", key: "autohide-delay", noise: true),
        ], version: 1, updatedAt: nil)
        let result = engine().parse(diffOutput: """
            -com.apple.dock :: show-recents = 1
            +com.apple.dock :: show-recents = 0
            -com.apple.dock :: autohide-delay = 0.5
            +com.apple.dock :: autohide-delay = 0.2
            -com.apple.dock :: unknown = foo
            +com.apple.dock :: unknown = bar
            """, kb: kb)
        XCTAssertEqual(result.recognized.count, 1)
        XCTAssertEqual(result.noise.count, 1)
        XCTAssertEqual(result.unrecognized.count, 1)
    }

    // MARK: - isFullReversal

    func testIsFullReversalTrueWithExtraRealChange() {
        let kb = KnowledgeBase(entries: [], version: 1, updatedAt: nil)
        let ab = engine().parse(diffOutput: """
            -com.apple.dock :: key1 = 1
            +com.apple.dock :: key1 = 2
            -com.apple.dock :: key2 = A
            +com.apple.dock :: key2 = B
            """, kb: kb)
        let bc = engine().parse(diffOutput: """
            -com.apple.dock :: key1 = 2
            +com.apple.dock :: key1 = 1
            -com.apple.dock :: key2 = B
            +com.apple.dock :: key2 = A
            -com.apple.dock :: key3 = X
            +com.apple.dock :: key3 = Y
            """, kb: kb)
        XCTAssertTrue(DiffEngine.isFullReversal(of: bc, reversing: ab))
    }

    func testIsFullReversalFalseWhenPartial() {
        let kb = KnowledgeBase(entries: [], version: 1, updatedAt: nil)
        let ab = engine().parse(diffOutput: """
            -com.apple.dock :: key1 = 1
            +com.apple.dock :: key1 = 2
            -com.apple.dock :: key2 = A
            +com.apple.dock :: key2 = B
            """, kb: kb)
        let bc = engine().parse(diffOutput: """
            -com.apple.dock :: key1 = 2
            +com.apple.dock :: key1 = 1
            """, kb: kb)
        XCTAssertFalse(DiffEngine.isFullReversal(of: bc, reversing: ab))
    }

    func testIsFullReversalFalseWhenAbEmpty() {
        let kb = KnowledgeBase(entries: [], version: 1, updatedAt: nil)
        let ab = engine().parse(diffOutput: "", kb: kb)
        let bc = engine().parse(diffOutput: """
            -com.apple.dock :: key1 = 1
            +com.apple.dock :: key1 = 2
            """, kb: kb)
        XCTAssertFalse(DiffEngine.isFullReversal(of: bc, reversing: ab))
    }

    func testIsFullReversalFalseWhenKeyLandsOnDifferentValue() {
        let kb = KnowledgeBase(entries: [], version: 1, updatedAt: nil)
        let ab = engine().parse(diffOutput: """
            -com.apple.dock :: key1 = 1
            +com.apple.dock :: key1 = 2
            """, kb: kb)
        let bc = engine().parse(diffOutput: """
            -com.apple.dock :: key1 = 2
            +com.apple.dock :: key1 = 3
            """, kb: kb)
        XCTAssertFalse(DiffEngine.isFullReversal(of: bc, reversing: ab))
    }
}
