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
    let recognized: [(entry: KBEntry, diff: DiffLine)]
    let unrecognized: [DiffLine]
    let noise: [(entry: KBEntry, diff: DiffLine)]

    static let empty = DiffResult(recognized: [], unrecognized: [], noise: [])
}
