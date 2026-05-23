import Foundation

struct KBEntry: Codable, Identifiable {
    let id: String
    let domain: String
    let key: String
    let source: String
    let valueType: String
    let description: String
    let uiLocation: String?
    let settingsURL: String?
    let noise: Bool
    let noiseReason: String?
    let minMacOS: String
    let notes: String?
    let aiGenerated: Bool
    let contributedByIssue: Int?

    enum CodingKeys: String, CodingKey {
        case id, domain, key, source, noise, notes, description
        case valueType = "value_type"
        case uiLocation = "ui_location"
        case settingsURL = "settings_url"
        case noiseReason = "noise_reason"
        case minMacOS = "min_macos"
        case aiGenerated = "ai_generated"
        case contributedByIssue = "contributed_by_issue"
    }
}
