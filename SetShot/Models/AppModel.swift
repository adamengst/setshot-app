import Foundation

@MainActor
class AppModel: ObservableObject {
    @Published var kb: KnowledgeBase = .empty
    @Published var kbUnavailable = false
    var beforeSnapshot: Snapshot?

    func loadKB() async {
        let (kb, unavailable) = await KBFetcher.shared.fetchIfNeeded()
        self.kb = kb
        self.kbUnavailable = unavailable
    }
}
