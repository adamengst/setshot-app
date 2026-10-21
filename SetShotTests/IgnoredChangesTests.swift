import XCTest
@testable import SetShot

final class IgnoredChangesTests: XCTestCase {

    private func row(domain: String, key: String) -> (entry: KBEntry, diff: DiffLine) {
        let entry = KBEntry(
            id: "\(domain).\(key)", domain: domain, key: key, source: "defaults",
            valueType: "string", description: "Test entry",
            uiLocation: nil, uiLocationOverrides: nil, settingsURL: nil,
            noise: false, noiseReason: nil,
            minMacOS: "13.0", notes: nil, aiGenerated: false,
            contributedByIssue: nil, valueMap: nil, keyPrefix: nil, iconBundleID: nil,
            implicitDefault: nil, requiresHardware: nil
        )
        let diff = DiffLine(domain: domain, key: key, source: "defaults",
                            beforeValue: "MacBook Pro Speakers", afterValue: "AirPods Pro",
                            macOSVersion: "26.0", rawLine: "")
        return (entry, diff)
    }

    private func result(_ rows: [(entry: KBEntry, diff: DiffLine)]) -> DiffResult {
        DiffResult(recognized: rows, unrecognized: [], noise: [],
                   unrecognizedOverflow: 0, limitedAccessWarning: nil)
    }

    func testSoundDevicesGroupDropsOutputAndInput() {
        let filtered = result([
            row(domain: "sound", key: "outputDevice"),
            row(domain: "sound", key: "inputDevice"),
            row(domain: "com.apple.FaceTime", key: "PreferredAudioInputDeviceUID"),
            row(domain: "com.apple.dock", key: "autohide"),
        ]).filteringIgnored(IgnoredChanges(groups: [.soundDevices]))

        XCTAssertEqual(filtered.recognized.map(\.diff.key), ["autohide"])
    }

    func testScreenshotGroupDropsModeAndStyleButNotSaveLocation() {
        let filtered = result([
            row(domain: "com.apple.screencapture", key: "video"),
            row(domain: "com.apple.screencapture", key: "style"),
            row(domain: "com.apple.screencapture", key: "location"),
        ]).filteringIgnored(IgnoredChanges(groups: [.screenshotMode]))

        XCTAssertEqual(filtered.recognized.map(\.diff.key), ["location"])
    }

    func testNoGroupsLeavesResultAlone() {
        let filtered = result([row(domain: "sound", key: "outputDevice")])
            .filteringIgnored(IgnoredChanges(groups: []))
        XCTAssertEqual(filtered.recognized.count, 1)
    }

    func testCurrentReadsOnlyGroupsSwitchedOn() throws {
        let suite = "IgnoredChangesTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertTrue(IgnoredChanges.current(defaults).isEmpty)
        defaults.set(true, forKey: IgnoredChangeGroup.soundDevices.defaultsKey)
        XCTAssertTrue(IgnoredChanges.current(defaults).covers(domain: "sound", key: "inputDevice"))
    }

    /// A group names its settings by domain and key, so a key renamed in the KB would
    /// leave the switch hiding nothing without any other sign.
    func testEveryIgnoredSettingIsARecognizedKBEntry() throws {
        let kb = KnowledgeBase(entries: try TestSupport.requireKnowledgeBase(), version: 1, updatedAt: nil)
        for group in IgnoredChangeGroup.allCases {
            for setting in group.settings {
                let entry = kb.entry(forDomain: setting.domain, key: setting.key)
                XCTAssertEqual(entry?.key, setting.key, "\(group): \(setting.domain) \(setting.key) has no exact KB entry")
                XCTAssertEqual(entry?.noise, false, "\(group): \(setting.domain) \(setting.key) is noise already")
            }
            for p in group.settingPrefixes {
                let entry = kb.entries.first { $0.domain == p.domain && $0.keyPrefix == p.prefix }
                XCTAssertNotNil(entry, "\(group): no KB entry with key_prefix \(p.domain) \(p.prefix)")
                XCTAssertEqual(entry?.noise, false, "\(group): \(p.domain) \(p.prefix) is noise already")
            }
        }
    }

    func testDNSGroupHidesTheLiveListButNotManualServers() {
        let filtered = result([
            row(domain: "dns", key: "nameserver[0]"),
            row(domain: "dns", key: "nameserver[1]"),
            row(domain: "dns", key: "searchdomain[0]"),
            row(domain: "dns", key: "domain"),
            row(domain: "dns-manual", key: "servers.Wi-Fi"),
        ]).filteringIgnored(IgnoredChanges(groups: [.dnsFromNetwork]))

        XCTAssertEqual(filtered.recognized.map(\.diff.key), ["servers.Wi-Fi"])
    }
}
