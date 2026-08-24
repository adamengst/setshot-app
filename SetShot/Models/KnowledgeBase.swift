import Foundation

struct KnowledgeBase {
    let entries: [KBEntry]
    let version: Int
    let updatedAt: Date?

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
        var best: (entry: KBEntry, prefixLength: Int)?

        for candidate in entries where candidate.domain == domain {
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
