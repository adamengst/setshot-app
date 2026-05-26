import Foundation

struct JournalEntry: Identifiable, Codable, Sendable {
    let id: UUID
    let afterSnapshotId: String
    let afterSnapshotDate: Date
    let afterSnapshotName: String
    let domain: String
    let key: String
    let entryDescription: String
    let uiLocation: String?
    let settingsURL: String?
    let oldValue: String
    let newValue: String
    let addedAt: Date
}
