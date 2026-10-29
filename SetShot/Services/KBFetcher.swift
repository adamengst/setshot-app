import Foundation

/// Where the KB is fetched from, in order. SetShot's own host comes first, so the KB
/// can move without an update; the worker there proxies the GitHub copy, which is
/// asked directly if the host fails. When neither answers, the cache or the bundled
/// copy is used.
struct KBSource: Equatable {
    let version: URL
    let entries: URL

    static let all = [
        KBSource(version: URL(string: "https://setshot.tidbits.com/kb/version.json")!,
                 entries: URL(string: "https://setshot.tidbits.com/kb/settings-kb.json")!),
        KBSource(version: URL(string: "https://raw.githubusercontent.com/adamengst/setshot-kb/main/version.json")!,
                 entries: URL(string: "https://raw.githubusercontent.com/adamengst/setshot-kb/main/settings-kb.json")!)
    ]
}

actor KBFetcher {
    static let shared = KBFetcher()

    private let versionKey = "kb_version"
    private let entriesKey = "kb_entries"
    private let updatedAtKey = "kb_updated_at"

    private let defaults: UserDefaults
    /// Holds settings-kb.json and version.json, copied in by scripts/refresh-bundled-kb.sh.
    private let bundledKBDirectory: URL?
    private let sources: [KBSource]
    private let fetch: @Sendable (URLRequest) async -> Data?

    init(defaults: UserDefaults = .standard,
         bundledKBDirectory: URL? = Bundle.main.url(forResource: "BundledKB", withExtension: nil),
         sources: [KBSource] = KBSource.all,
         fetch: @escaping @Sendable (URLRequest) async -> Data? = KBFetcher.networkFetch) {
        self.defaults = defaults
        self.bundledKBDirectory = bundledKBDirectory
        self.sources = sources
        self.fetch = fetch
    }

    /// Only a 200 counts, so an error page is never taken for the KB.
    static func networkFetch(_ request: URLRequest) async -> Data? {
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return data
    }

    // Returns the KB to use and whether it is completely unavailable (no cache, no
    // bundled copy, no network).
    func fetchIfNeeded() async -> (KnowledgeBase, unavailable: Bool) {
        let local = loadLocal()

        if let kb = await fetchRemote(newerThan: local?.version) {
            return (kb, false)
        }

        if let local { return (local, false) }
        return (.empty, true)
    }

    func forceRefresh() async -> (KnowledgeBase, unavailable: Bool) {
        if let kb = await fetchRemote(newerThan: nil) {
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

    /// Tries each source in turn and fetches the entries from the one that answered
    /// version.json, so the version and the entries always come from the same place.
    /// A source that answers with a version no newer than the local one ends the
    /// search: the others hold the same repository.
    private func fetchRemote(newerThan localVersion: Int?) async -> KnowledgeBase? {
        for source in sources {
            guard let remote = await fetchRemoteVersion(from: source) else { continue }
            if let localVersion, remote.version <= localVersion { return nil }
            if let kb = await fetchAndCacheKB(from: source, version: remote.version, updatedAt: remote.updatedAt) {
                return kb
            }
        }
        return nil
    }

    private func fetchRemoteVersion(from source: KBSource) async -> (version: Int, updatedAt: Date?)? {
        let request = URLRequest(url: source.version, cachePolicy: .reloadIgnoringLocalCacheData)
        guard let data = await fetch(request) else { return nil }
        return decodeVersion(data)
    }

    private func fetchAndCacheKB(from source: KBSource, version: Int, updatedAt: Date?) async -> KnowledgeBase? {
        let request = URLRequest(url: source.entries, cachePolicy: .reloadIgnoringLocalCacheData)
        guard let data = await fetch(request),
              let entries = try? JSONDecoder().decode([KBEntry].self, from: data) else { return nil }
        defaults.set(data, forKey: entriesKey)
        defaults.set(version, forKey: versionKey)
        if let updatedAt { defaults.set(updatedAt, forKey: updatedAtKey) }
        return KnowledgeBase(entries: entries, version: version, updatedAt: updatedAt)
    }
}
