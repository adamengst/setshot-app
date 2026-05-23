import Foundation

struct DiffLine: Identifiable {
    let id = UUID()
    let domain: String
    let key: String
    let source: String
    let beforeValue: String
    let afterValue: String
    let macOSVersion: String
    let rawLine: String
}

struct DiffResult {
    let recognised: [(entry: KBEntry, diff: DiffLine)]
    let unrecognised: [DiffLine]
    let noise: [(entry: KBEntry, diff: DiffLine)]

    static let empty = DiffResult(recognised: [], unrecognised: [], noise: [])
}
