import XCTest
@testable import SetShot

/// KBFetcher picks between three sources: the network, the UserDefaults cache, and the
/// copy bundled with the app. Each test gives it its own defaults suite, bundled
/// directory and network stand-in, and tells the sources apart by version and entry id.
final class KBFetcherTests: XCTestCase {

    private var suite = ""
    private var defaults: UserDefaults!
    private var bundledDir: URL!

    override func setUpWithError() throws {
        suite = "KBFetcherTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        bundledDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("KBFetcherTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: bundledDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: bundledDir)
    }

    // MARK: - Fixtures

    private func entries(id: String) -> Data {
        """
        [{"id":"\(id)","domain":"com.apple.test","key":"k","source":"defaults",
          "value_type":"string","description":"d","ui_location":null,"settings_url":null,
          "noise":false,"noise_reason":null,"min_macos":"13.0","notes":null,
          "ai_generated":false,"contributed_by_issue":null,"value_map":null}]
        """.data(using: .utf8)!
    }

    private func versionJSON(_ version: Int) -> Data {
        #"{"version": \#(version), "updated_at": "2026-10-28T13:47:49Z"}"#.data(using: .utf8)!
    }

    private func writeBundled(version: Int, id: String) throws {
        try versionJSON(version).write(to: bundledDir.appendingPathComponent("version.json"))
        try entries(id: id).write(to: bundledDir.appendingPathComponent("settings-kb.json"))
    }

    /// Stands in for the cache a previous network fetch would have left.
    private func writeCache(version: Int, id: String) {
        defaults.set(entries(id: id), forKey: "kb_entries")
        defaults.set(version, forKey: "kb_version")
    }

    private func fetcher(network: (version: Int, id: String)? = nil) -> KBFetcher {
        let versionData = network.map { versionJSON($0.version) }
        let entriesData = network.map { entries(id: $0.id) }
        return KBFetcher(defaults: defaults, bundledKBDirectory: bundledDir) { request in
            switch request.url?.lastPathComponent {
            case "version.json": return versionData
            case "settings-kb.json": return entriesData
            default: return nil
            }
        }
    }

    // MARK: - Tests

    func testNoCacheNoNetworkLoadsBundledKB() async throws {
        try writeBundled(version: 10, id: "bundled")
        let (kb, unavailable) = await fetcher().fetchIfNeeded()
        XCTAssertFalse(unavailable)
        XCTAssertEqual(kb.version, 10)
        XCTAssertEqual(kb.entries.map(\.id), ["bundled"])
        XCTAssertNotNil(kb.updatedAt)
    }

    func testNewerCacheBeatsBundledKB() async throws {
        try writeBundled(version: 10, id: "bundled")
        writeCache(version: 12, id: "cached")
        let (kb, unavailable) = await fetcher().fetchIfNeeded()
        XCTAssertFalse(unavailable)
        XCTAssertEqual(kb.version, 12)
        XCTAssertEqual(kb.entries.map(\.id), ["cached"])
    }

    func testNewerBundledKBBeatsOlderCache() async throws {
        try writeBundled(version: 15, id: "bundled")
        writeCache(version: 12, id: "cached")
        let (kb, unavailable) = await fetcher().fetchIfNeeded()
        XCTAssertFalse(unavailable)
        XCTAssertEqual(kb.version, 15)
        XCTAssertEqual(kb.entries.map(\.id), ["bundled"])
    }

    func testNewerNetworkKBBeatsBundledAndIsCached() async throws {
        try writeBundled(version: 10, id: "bundled")
        let (kb, _) = await fetcher(network: (20, "remote")).fetchIfNeeded()
        XCTAssertEqual(kb.version, 20)
        XCTAssertEqual(kb.entries.map(\.id), ["remote"])
        XCTAssertEqual(defaults.integer(forKey: "kb_version"), 20)
    }

    func testNothingAnywhereIsUnavailable() async {
        let (kb, unavailable) = await fetcher().fetchIfNeeded()
        XCTAssertTrue(unavailable)
        XCTAssertEqual(kb.version, 0)
    }

    /// The tests run hosted in the built app, so Bundle.main is SetShot.app. This
    /// catches a project.yml change that stops the KB being copied in.
    func testAppBundlesTheCheckedInKB() throws {
        let bundled = try XCTUnwrap(Bundle.main.url(forResource: "BundledKB", withExtension: nil),
                                    "SetShot.app has no BundledKB folder")
        let repoCopy = TestSupport.repoRoot.appendingPathComponent("SetShot/Resources/BundledKB")
        for name in ["version.json", "settings-kb.json"] {
            XCTAssertEqual(try Data(contentsOf: bundled.appendingPathComponent(name)),
                           try Data(contentsOf: repoCopy.appendingPathComponent(name)), name)
        }
    }
}
