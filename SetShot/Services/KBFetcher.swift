import Foundation

private let kbVersionURL = URL(string: "https://raw.githubusercontent.com/adamengst/setshot-kb/main/version.json")!
private let kbEntriesURL = URL(string: "https://raw.githubusercontent.com/adamengst/setshot-kb/main/settings-kb.json")!

actor KBFetcher {
    static let shared = KBFetcher()

    private let versionKey = "kb_version"
    private let entriesKey = "kb_entries"
    private let updatedAtKey = "kb_updated_at"

    // Returns the KB to use and whether it is completely unavailable (no cache, no network).
    func fetchIfNeeded() async -> (KnowledgeBase, unavailable: Bool) {
        let cachedVersion = UserDefaults.standard.integer(forKey: versionKey)
        let cachedData = UserDefaults.standard.data(forKey: entriesKey)

        if let remote = await fetchRemoteVersion() {
            if remote.version > cachedVersion || cachedData == nil {
                if let kb = await fetchAndCacheKB(version: remote.version, updatedAt: remote.updatedAt) {
                    return (kb, false)
                }
            }
        }

        if let cachedData,
           let entries = try? JSONDecoder().decode([KBEntry].self, from: cachedData) {
            let date = UserDefaults.standard.object(forKey: updatedAtKey) as? Date
            return (KnowledgeBase(entries: entries, version: cachedVersion, updatedAt: date), false)
        }

        return (.empty, true)
    }

    func forceRefresh() async -> (KnowledgeBase, unavailable: Bool) {
        if let remote = await fetchRemoteVersion(),
           let kb = await fetchAndCacheKB(version: remote.version, updatedAt: remote.updatedAt) {
            return (kb, false)
        }
        if let cachedData = UserDefaults.standard.data(forKey: entriesKey),
           let entries = try? JSONDecoder().decode([KBEntry].self, from: cachedData) {
            let date = UserDefaults.standard.object(forKey: updatedAtKey) as? Date
            return (KnowledgeBase(entries: entries, version: UserDefaults.standard.integer(forKey: versionKey), updatedAt: date), false)
        }
        return (.empty, true)
    }

    private struct VersionResponse: Decodable {
        let version: Int
        let updatedAt: String?
        enum CodingKeys: String, CodingKey {
            case version
            case updatedAt = "updated_at"
        }
    }

    private func fetchRemoteVersion() async -> (version: Int, updatedAt: Date?)? {
        let request = URLRequest(url: kbVersionURL, cachePolicy: .reloadIgnoringLocalCacheData)
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let response = try? JSONDecoder().decode(VersionResponse.self, from: data) else { return nil }
        let date = response.updatedAt.flatMap { ISO8601DateFormatter().date(from: $0) }
        return (response.version, date)
    }

    private func fetchAndCacheKB(version: Int, updatedAt: Date?) async -> KnowledgeBase? {
        let request = URLRequest(url: kbEntriesURL, cachePolicy: .reloadIgnoringLocalCacheData)
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let entries = try? JSONDecoder().decode([KBEntry].self, from: data) else { return nil }
        UserDefaults.standard.set(data, forKey: entriesKey)
        UserDefaults.standard.set(version, forKey: versionKey)
        if let updatedAt { UserDefaults.standard.set(updatedAt, forKey: updatedAtKey) }
        return KnowledgeBase(entries: entries, version: version, updatedAt: updatedAt)
    }
}
