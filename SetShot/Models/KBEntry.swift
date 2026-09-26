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
    let minMacOS: String?
    let notes: String?
    let aiGenerated: Bool
    let contributedByIssue: Int?
    let valueMap: [String: String]?
    let keyPrefix: String?
    let iconBundleID: String?
    let implicitDefault: String?
    let requiresHardware: [String]?

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
        case implicitDefault = "implicit_default"
        case requiresHardware = "requires_hardware"
    }

    /// Where this setting lives on a given macOS, which is not always where it lives
    /// now: Siri's pane was Siri & Spotlight through macOS 15, Apple Intelligence &
    /// Siri in 26, and Siri in 27.
    ///
    /// Each override says which version it stops applying before, and the tightest
    /// one wins — the smallest `beforeMacOSMajor` this Mac still falls under. Taking
    /// whichever came first in the array instead made the answer depend on the order
    /// they happened to be written in, so a Mac on 15 could be told about the 26
    /// pane.
    func effectiveUILocation(macOSMajor: Int) -> String? {
        let applicable = (uiLocationOverrides ?? [])
            .filter { macOSMajor < $0.beforeMacOSMajor }
            .min { $0.beforeMacOSMajor < $1.beforeMacOSMajor }
        return applicable?.uiLocation ?? uiLocation
    }
}
