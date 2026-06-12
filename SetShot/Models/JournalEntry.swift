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
    let fromBaseline: Bool

    // Custom decoder so existing journal files (missing fromBaseline) decode cleanly.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id               = try c.decode(UUID.self,   forKey: .id)
        afterSnapshotId  = try c.decode(String.self, forKey: .afterSnapshotId)
        afterSnapshotDate = try c.decode(Date.self,  forKey: .afterSnapshotDate)
        afterSnapshotName = try c.decode(String.self, forKey: .afterSnapshotName)
        domain           = try c.decode(String.self, forKey: .domain)
        key              = try c.decode(String.self, forKey: .key)
        entryDescription = try c.decode(String.self, forKey: .entryDescription)
        uiLocation       = try c.decodeIfPresent(String.self, forKey: .uiLocation)
        settingsURL      = try c.decodeIfPresent(String.self, forKey: .settingsURL)
        oldValue         = try c.decode(String.self, forKey: .oldValue)
        newValue         = try c.decode(String.self, forKey: .newValue)
        addedAt          = try c.decode(Date.self,   forKey: .addedAt)
        fromBaseline     = (try? c.decodeIfPresent(Bool.self, forKey: .fromBaseline)) ?? false
    }

    init(id: UUID, afterSnapshotId: String, afterSnapshotDate: Date, afterSnapshotName: String,
         domain: String, key: String, entryDescription: String, uiLocation: String?,
         settingsURL: String?, oldValue: String, newValue: String, addedAt: Date,
         fromBaseline: Bool = false) {
        self.id = id; self.afterSnapshotId = afterSnapshotId
        self.afterSnapshotDate = afterSnapshotDate; self.afterSnapshotName = afterSnapshotName
        self.domain = domain; self.key = key; self.entryDescription = entryDescription
        self.uiLocation = uiLocation; self.settingsURL = settingsURL
        self.oldValue = oldValue; self.newValue = newValue
        self.addedAt = addedAt; self.fromBaseline = fromBaseline
    }
}
