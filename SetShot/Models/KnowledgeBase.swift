import Foundation

struct KnowledgeBase {
    let entries: [KBEntry]
    let version: Int
    let updatedAt: Date?

    /// Entries grouped by domain, so a lookup does not scan the whole knowledge base.
    /// Grouping preserves order within each domain, which the match precedence below
    /// relies on for two entries that tie.
    private let byDomain: [String: [KBEntry]]

    init(entries: [KBEntry], version: Int, updatedAt: Date?) {
        self.entries = entries
        self.version = version
        self.updatedAt = updatedAt
        self.byDomain = Dictionary(grouping: entries, by: \.domain)
    }

    static let empty = KnowledgeBase(entries: [], version: 0, updatedAt: nil)

    /// Finds the entry describing `key` in `domain`, most specific match first.
    ///
    /// Precedence matters because `key_prefix` rules overlap with the settings they
    /// cover: `key_prefix: ""` matches every key in a domain and is how the KB
    /// expresses "this whole domain is noise". Picking whichever entry appeared
    /// first in settings-kb.json meant a domain-wide noise rule could swallow a
    /// described setting purely because it was added to the file earlier — which is
    /// what happened to Home Sharing, Remote Management's screen-sharing permission
    /// and Spotlight's search categories.
    func entry(forDomain domain: String, key: String) -> KBEntry? {
        guard let candidates = byDomain[domain] else { return nil }
        var best: (entry: KBEntry, prefixLength: Int)?

        for candidate in candidates {
            // An entry naming this key exactly always wins: a prefix rule is a
            // default for the domain, and a specific entry overrides the default.
            if candidate.key == key { return candidate }

            guard let prefix = candidate.keyPrefix, key.hasPrefix(prefix) else { continue }
            // Among prefix rules the longest match wins, so "" loses to everything.
            if let best, best.prefixLength >= prefix.count { continue }
            best = (candidate, prefix.count)
        }

        return best?.entry
    }
}
