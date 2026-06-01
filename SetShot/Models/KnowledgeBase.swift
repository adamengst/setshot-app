import Foundation

struct KnowledgeBase {
    let entries: [KBEntry]
    let version: Int
    let updatedAt: Date?

    static let empty = KnowledgeBase(entries: [], version: 0, updatedAt: nil)

    func entry(forDomain domain: String, key: String) -> KBEntry? {
        entries.first {
            $0.domain == domain &&
            ($0.key == key || $0.keyPrefix.map { key.hasPrefix($0) } ?? false)
        }
    }
}
