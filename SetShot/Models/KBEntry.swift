import Foundation

struct UILocationOverride: Codable {
    let beforeMacOSMajor: Int
    let uiLocation: String

    enum CodingKeys: String, CodingKey {
        case beforeMacOSMajor = "before_macos_major"
        case uiLocation = "ui_location"
    }
}

struct KBEntry: Codable, Identifiable {
    let id: String
    let domain: String
    let key: String
    let source: String
    let valueType: String
    let description: String?
    let uiLocation: String?
    let uiLocationOverrides: [UILocationOverride]?
    let settingsURL: String?
    let noise: Bool
    let noiseReason: String?
    let minMacOS: String
    let notes: String?
    let aiGenerated: Bool
    let contributedByIssue: Int?
    let valueMap: [String: String]?
    let keyPrefix: String?
    let iconBundleID: String?

    enum CodingKeys: String, CodingKey {
        case id, domain, key, source, noise, notes, description
        case valueType = "value_type"
        case uiLocation = "ui_location"
        case uiLocationOverrides = "ui_location_overrides"
        case settingsURL = "settings_url"
        case noiseReason = "noise_reason"
        case minMacOS = "min_macos"
        case aiGenerated = "ai_generated"
        case contributedByIssue = "contributed_by_issue"
        case valueMap = "value_map"
        case keyPrefix = "key_prefix"
        case iconBundleID = "icon_bundle_id"
    }

    func effectiveUILocation(macOSMajor: Int) -> String? {
        if let overrides = uiLocationOverrides {
            for override in overrides where macOSMajor < override.beforeMacOSMajor {
                return override.uiLocation
            }
        }
        return uiLocation
    }
}
