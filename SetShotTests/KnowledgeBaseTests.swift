import XCTest
@testable import SetShot

final class KnowledgeBaseTests: XCTestCase {

    private func makeEntry(
        id: String = "test",
        domain: String,
        key: String = "",
        keyPrefix: String? = nil,
        noise: Bool = false
    ) -> KBEntry {
        KBEntry(
            id: id, domain: domain, key: key, source: "defaults",
            valueType: "string", description: "Test entry",
            uiLocation: nil, uiLocationOverrides: nil, settingsURL: nil,
            noise: noise, noiseReason: noise ? "test" : nil,
            minMacOS: "13.0", notes: nil, aiGenerated: false,
            contributedByIssue: nil, valueMap: nil, keyPrefix: keyPrefix, iconBundleID: nil, implicitDefault: nil, requiresHardware: nil
        )
    }

    func testExactKeyMatch() {
        let kb = KnowledgeBase(entries: [makeEntry(domain: "com.apple.dock", key: "show-recents")], version: 1, updatedAt: nil)
        XCTAssertNotNil(kb.entry(forDomain: "com.apple.dock", key: "show-recents"))
    }

    func testExactKeyNoMatchOnWrongKey() {
        let kb = KnowledgeBase(entries: [makeEntry(domain: "com.apple.dock", key: "show-recents")], version: 1, updatedAt: nil)
        XCTAssertNil(kb.entry(forDomain: "com.apple.dock", key: "other-key"))
    }

    func testExactKeyNoMatchOnWrongDomain() {
        let kb = KnowledgeBase(entries: [makeEntry(domain: "com.apple.dock", key: "show-recents")], version: 1, updatedAt: nil)
        XCTAssertNil(kb.entry(forDomain: "com.apple.finder", key: "show-recents"))
    }

    func testKeyPrefixMatch() {
        let entry = makeEntry(domain: "com.apple.FolderActionsDispatcher", keyPrefix: "folderActions.$objects[", noise: true)
        let kb = KnowledgeBase(entries: [entry], version: 1, updatedAt: nil)
        XCTAssertNotNil(kb.entry(forDomain: "com.apple.FolderActionsDispatcher", key: "folderActions.$objects[7]"))
        XCTAssertNotNil(kb.entry(forDomain: "com.apple.FolderActionsDispatcher", key: "folderActions.$objects[100]"))
    }

    // MARK: - Match precedence
    //
    // key_prefix "" is how the KB says "this whole domain is noise", so it overlaps
    // every described setting in that domain. Resolution must not depend on which
    // entry happens to appear first in settings-kb.json.

    func testExactKeyBeatsEarlierDomainWideRule() {
        let domainRule = makeEntry(id: "domain-noise", domain: "com.apple.dock", keyPrefix: "", noise: true)
        let setting = makeEntry(id: "dock.autohide", domain: "com.apple.dock", key: "autohide")
        let kb = KnowledgeBase(entries: [domainRule, setting], version: 1, updatedAt: nil)
        XCTAssertEqual(kb.entry(forDomain: "com.apple.dock", key: "autohide")?.id, "dock.autohide")
    }

    func testDomainWideRuleStillCoversUnlistedKeys() {
        let domainRule = makeEntry(id: "domain-noise", domain: "com.apple.dock", keyPrefix: "", noise: true)
        let setting = makeEntry(id: "dock.autohide", domain: "com.apple.dock", key: "autohide")
        let kb = KnowledgeBase(entries: [domainRule, setting], version: 1, updatedAt: nil)
        XCTAssertEqual(kb.entry(forDomain: "com.apple.dock", key: "some-other-key")?.id, "domain-noise")
    }

    func testLongestPrefixWins() {
        let broad = makeEntry(id: "broad", domain: "com.apple.finder", keyPrefix: "View", noise: true)
        let narrow = makeEntry(id: "narrow", domain: "com.apple.finder", keyPrefix: "ViewSettings.")
        let kb = KnowledgeBase(entries: [broad, narrow], version: 1, updatedAt: nil)
        XCTAssertEqual(kb.entry(forDomain: "com.apple.finder", key: "ViewSettings.icon")?.id, "narrow")
        XCTAssertEqual(kb.entry(forDomain: "com.apple.finder", key: "ViewOptions")?.id, "broad")
    }

    func testKeyPrefixNoMatchOnWrongPrefix() {
        let entry = makeEntry(domain: "com.apple.FolderActionsDispatcher", keyPrefix: "folderActions.$objects[", noise: true)
        let kb = KnowledgeBase(entries: [entry], version: 1, updatedAt: nil)
        XCTAssertNil(kb.entry(forDomain: "com.apple.FolderActionsDispatcher", key: "folderActions.$version"))
    }

    func testEmptyKeyPrefixMatchesAllKeysInDomain() {
        let entry = makeEntry(domain: "com.apple.audio.DeviceSettings", keyPrefix: "", noise: true)
        let kb = KnowledgeBase(entries: [entry], version: 1, updatedAt: nil)
        XCTAssertNotNil(kb.entry(forDomain: "com.apple.audio.DeviceSettings", key: "14-14-7D-E4-A5-D9:output.controls[1].value"))
        XCTAssertNotNil(kb.entry(forDomain: "com.apple.audio.DeviceSettings", key: "BuiltInMicrophoneDevice.controls[0].value"))
        XCTAssertNil(kb.entry(forDomain: "com.apple.dock", key: "anything"))
    }

    func testNoiseEntryClassifiedAsNoise() {
        let entry = makeEntry(domain: "com.apple.dock", key: "someTransientKey", noise: true)
        let kb = KnowledgeBase(entries: [entry], version: 1, updatedAt: nil)
        XCTAssertTrue(kb.entry(forDomain: "com.apple.dock", key: "someTransientKey")?.noise == true)
    }

    // MARK: - Locations that changed with the macOS version

    /// Siri's pane was Siri & Spotlight through macOS 15, Apple Intelligence & Siri
    /// in 26, and Siri in 27. Three names means two overrides, and the answer must
    /// not depend on which order they were written in.
    private func siriEntry(overrides: [UILocationOverride]) -> KBEntry {
        KBEntry(id: "t", domain: "d", key: "k", source: "s", valueType: "string",
                description: "Test", uiLocation: "System Settings → Siri → Ask Siri",
                uiLocationOverrides: overrides, settingsURL: nil, noise: false,
                noiseReason: nil, minMacOS: nil, notes: nil, aiGenerated: false,
                contributedByIssue: nil, valueMap: nil, keyPrefix: nil,
                iconBundleID: nil, implicitDefault: nil, requiresHardware: nil)
    }

    func testTheTightestOverrideWinsWhicheverOrderTheyAreIn() {
        let ascending = [
            UILocationOverride(beforeMacOSMajor: 26,
                                       uiLocation: "System Settings → Siri & Spotlight → Ask Siri"),
            UILocationOverride(beforeMacOSMajor: 27,
                                       uiLocation: "System Settings → Apple Intelligence & Siri → Ask Siri"),
        ]
        for overrides in [ascending, ascending.reversed()] {
            let e = siriEntry(overrides: Array(overrides))
            XCTAssertEqual(e.effectiveUILocation(macOSMajor: 15),
                           "System Settings → Siri & Spotlight → Ask Siri")
            XCTAssertEqual(e.effectiveUILocation(macOSMajor: 26),
                           "System Settings → Apple Intelligence & Siri → Ask Siri")
            XCTAssertEqual(e.effectiveUILocation(macOSMajor: 27),
                           "System Settings → Siri → Ask Siri")
        }
    }

    func testNoOverridesLeavesTheLocationAlone() {
        XCTAssertEqual(siriEntry(overrides: []).effectiveUILocation(macOSMajor: 15),
                       "System Settings → Siri → Ask Siri")
    }
}
