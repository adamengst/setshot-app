import Foundation

actor KBFetcher {
    static let shared = KBFetcher()

    private let versionURL = URL(string: "https://raw.githubusercontent.com/\(kbRepo)/main/version.json")!
    private let kbURL = URL(string: "https://raw.githubusercontent.com/\(kbRepo)/main/settings-kb.json")!

    private let versionKey = "kb_version"
    private let entriesKey = "kb_entries"

    func fetchIfNeeded() async throws -> KnowledgeBase {
        // TODO: implemented in KBFetcher session
        return .empty
    }
}

private let kbRepo = "the-account-of-adam-engst/setshot-kb"
