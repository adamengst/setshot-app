import Foundation

struct Snapshot {
    let takenAt: Date
    let rawOutput: String

    static func empty() -> Snapshot {
        Snapshot(takenAt: .now, rawOutput: "")
    }
}
