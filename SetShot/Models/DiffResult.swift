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
    /// A companion value read from the same snapshot, needed to label this one.
    ///
    /// NewWindowTarget is the case this exists for: the choice is an enum whose
    /// "custom folder" options say nothing about which folder, and the folder lives
    /// in a separate key that does not necessarily change at the same time. Reading
    /// that key from live defaults showed today's folder on both sides of every
    /// comparison, so it has to come from the snapshots themselves.
    var beforeDetail: String?
    var afterDetail: String?
}

struct DiffResult {
    let recognized: [(entry: KBEntry, diff: DiffLine)]
    let unrecognized: [DiffLine]
    let noise: [(entry: KBEntry, diff: DiffLine)]
    let unrecognizedOverflow: Int  // items dropped past the cap; 0 = none
    let limitedAccessWarning: String?  // non-nil when a snapshot was taken without Full Disk Access

    static let empty = DiffResult(recognized: [], unrecognized: [], noise: [], unrecognizedOverflow: 0, limitedAccessWarning: nil)

    func filteringHardware(hasBattery: Bool) -> DiffResult {
        guard !hasBattery else { return self }
        let filtered = recognized.filter { $0.entry.requiresHardware?.contains("battery") != true }
        guard filtered.count != recognized.count else { return self }
        return DiffResult(recognized: filtered, unrecognized: unrecognized, noise: noise,
                          unrecognizedOverflow: unrecognizedOverflow, limitedAccessWarning: limitedAccessWarning)
    }
}
