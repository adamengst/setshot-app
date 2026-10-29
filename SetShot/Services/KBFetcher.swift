import Foundation

private let kbVersionURL = URL(string: "https://raw.githubusercontent.com/adamengst/setshot-kb/main/version.json")!
private let kbEntriesURL = URL(string: "https://raw.githubusercontent.com/adamengst/setshot-kb/main/settings-kb.json")!

actor KBFetcher {
    static let shared = KBFetcher()

    private let versionKey = "kb_version"
    private let entriesKey = "kb_entries"
    private let updatedAtKey = "kb_updated_at"

    private let defaults: UserDefaults
    /// Holds settings-kb.json and version.json, copied in by scripts/refresh-bundled-kb.sh.
    private let bundledKBDirectory: URL?
    private let fetch: @Sendable (URLRequest) async -> Data?

    init(defaults: UserDefaults = .standard,
         bundledKBDirectory: URL? = Bundle.main.url(forResource: "BundledKB", withExtension: nil),
         fetch: @escaping @Sendable (URLRequest) async -> Data? = KBFetcher.networkFetch) {
        self.defaults = defaults
        self.bundledKBDirectory = bundledKBDirectory
        self.fetch = fetch
    }

    static func networkFetch(_ request: URLRequest) async -> Data? {
        try? await URLSession.shared.data(for: request).0
    }

    // Returns the KB to use and whether it is completely unavailable (no cache, no
    // bundled copy, no network).
    func fetchIfNeeded() async -> (KnowledgeBase, unavailable: Bool) {
        let local = loadLocal()

        if let remote = await fetchRemoteVersion(),
           local.map({ remote.version > $0.version }) ?? true,
           let kb = await fetchAndCacheKB(version: remote.version, updatedAt: remote.updatedAt) {
            return (kb, false)
        }

        if let local { return (local, false) }
        return (.empty, true)
    }

    func forceRefresh() async -> (KnowledgeBase, unavailable: Bool) {
        if let remote = await fetchRemoteVersion(),
           let kb = await fetchAndCacheKB(version: remote.version, updatedAt: remote.updatedAt) {
            return (kb, false)
        }
        if let local = loadLocal() { return (local, false) }
        return (.empty, true)
    }

    // MARK: - Local copies

    /// The cached KB or the bundled one, whichever is newer. The bundled copy is the
    /// floor: it covers a first launch with no network, and a cache older than the app.
    /// A tie goes to the cache, which is the same data plus the date it was fetched.
    private func loadLocal() -> KnowledgeBase? {
        let cachedVersion = defaults.data(forKey: entriesKey) != nil ? defaults.integer(forKey: versionKey) : nil
        let bundled = bundledVersion()

        if let cachedVersion, cachedVersion >= (bundled?.version ?? 0), let kb = loadCached() {
            return kb
        }
        if let bundled, let kb = loadBundled(version: bundled.version, updatedAt: bundled.updatedAt) {
            return kb
        }
        // Only reached when the bundled copy is newer but fails to decode.
        return loadCached()
    }

    private func loadCached() -> KnowledgeBase? {
        guard let data = defaults.data(forKey: entriesKey),
              let entries = try? JSONDecoder().decode([KBEntry].self, from: data) else { return nil }
        let date = defaults.object(forKey: updatedAtKey) as? Date
        return KnowledgeBase(entries: entries, version: defaults.integer(forKey: versionKey), updatedAt: date)
    }

    private func bundledVersion() -> (version: Int, updatedAt: Date?)? {
        guard let url = bundledKBDirectory?.appendingPathComponent("version.json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return decodeVersion(data)
    }

    private func loadBundled(version: Int, updatedAt: Date?) -> KnowledgeBase? {
        guard let url = bundledKBDirectory?.appendingPathComponent("settings-kb.json"),
              let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([KBEntry].self, from: data) else { return nil }
        return KnowledgeBase(entries: entries, version: version, updatedAt: updatedAt)
    }

    // MARK: - Network

    private struct VersionResponse: Decodable {
        let version: Int
        let updatedAt: String?
        enum CodingKeys: String, CodingKey {
            case version
            case updatedAt = "updated_at"
        }
    }

    private func decodeVersion(_ data: Data) -> (version: Int, updatedAt: Date?)? {
        guard let response = try? JSONDecoder().decode(VersionResponse.self, from: data) else { return nil }
        let date = response.updatedAt.flatMap { ISO8601DateFormatter().date(from: $0) }
        return (response.version, date)
    }

    private func fetchRemoteVersion() async -> (version: Int, updatedAt: Date?)? {
        let request = URLRequest(url: kbVersionURL, cachePolicy: .reloadIgnoringLocalCacheData)
        guard let data = await fetch(request) else { return nil }
        return decodeVersion(data)
    }

    private func fetchAndCacheKB(version: Int, updatedAt: Date?) async -> KnowledgeBase? {
        let request = URLRequest(url: kbEntriesURL, cachePolicy: .reloadIgnoringLocalCacheData)
        guard let data = await fetch(request),
              let entries = try? JSONDecoder().decode([KBEntry].self, from: data) else { return nil }
        defaults.set(data, forKey: entriesKey)
        defaults.set(version, forKey: versionKey)
        if let updatedAt { defaults.set(updatedAt, forKey: updatedAtKey) }
        return KnowledgeBase(entries: entries, version: version, updatedAt: updatedAt)
    }
}
