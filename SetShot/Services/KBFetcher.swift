import Foundation

private let kbVersionURL = URL(string: "https://raw.githubusercontent.com/adamengst/setshot-kb/main/version.json")!
private let kbEntriesURL = URL(string: "https://raw.githubusercontent.com/adamengst/setshot-kb/main/settings-kb.json")!

actor KBFetcher {
    static let shared = KBFetcher()

    private let versionKey = "kb_version"
    private let entriesKey = "kb_entries"

    // Returns the KB to use and whether it is completely unavailable (no cache, no network).
    func fetchIfNeeded() async -> (KnowledgeBase, unavailable: Bool) {
        let cachedVersion = UserDefaults.standard.integer(forKey: versionKey)
        let cachedData = UserDefaults.standard.data(forKey: entriesKey)

        if let remoteVersion = await fetchRemoteVersion() {
            if remoteVersion > cachedVersion || cachedData == nil {
                if let kb = await fetchAndCacheKB(version: remoteVersion) {
                    return (kb, false)
                }
            }
        }

        if let cachedData,
           let entries = try? JSONDecoder().decode([KBEntry].self, from: cachedData) {
            return (KnowledgeBase(entries: entries, version: cachedVersion), false)
        }

        return (.empty, true)
    }

    private func fetchRemoteVersion() async -> Int? {
        guard let (data, _) = try? await URLSession.shared.data(from: kbVersionURL) else { return nil }
        struct VersionResponse: Decodable { let version: Int }
        return try? JSONDecoder().decode(VersionResponse.self, from: data).version
    }

    private func fetchAndCacheKB(version: Int) async -> KnowledgeBase? {
        guard let (data, _) = try? await URLSession.shared.data(from: kbEntriesURL),
              let entries = try? JSONDecoder().decode([KBEntry].self, from: data) else { return nil }
        UserDefaults.standard.set(data, forKey: entriesKey)
        UserDefaults.standard.set(version, forKey: versionKey)
        return KnowledgeBase(entries: entries, version: version)
    }
}
