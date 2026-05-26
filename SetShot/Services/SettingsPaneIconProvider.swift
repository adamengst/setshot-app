import AppKit

actor SettingsPaneIconProvider {
    static let shared = SettingsPaneIconProvider()
    private init() {}

    private var bundleIDToPath: [String: String]?
    private var iconCache: [String: NSImage] = [:]

    // Legacy / renamed bundle IDs that don't appear in ExtensionKit
    private let aliases: [String: String] = [
        "com.apple.preference.security": "com.apple.settings.PrivacySecurity.extension",
        "com.apple.preferences.password": "com.apple.Touch-ID-Settings.extension",
    ]

    func icon(forSettingsURL urlString: String?, domain: String) async -> NSImage? {
        if let urlString, let bundleID = extractBundleID(from: urlString) {
            let resolvedID = aliases[bundleID] ?? bundleID
            if let cached = iconCache[resolvedID] { return cached }
            ensureBundleMap()
            if let path = bundleIDToPath?[resolvedID] {
                let img = await MainActor.run { NSWorkspace.shared.icon(forFile: path) }
                iconCache[resolvedID] = img
                return img
            }
        }
        if let cached = iconCache[domain] { return cached }
        if let url = await MainActor.run(body: { NSWorkspace.shared.urlForApplication(withBundleIdentifier: domain) }) {
            let img = await MainActor.run { NSWorkspace.shared.icon(forFile: url.path) }
            iconCache[domain] = img
            return img
        }
        return nil
    }

    private func ensureBundleMap() {
        guard bundleIDToPath == nil else { return }
        var map: [String: String] = [:]
        let dir = "/System/Library/ExtensionKit/Extensions"
        if let items = try? FileManager.default.contentsOfDirectory(atPath: dir) {
            for item in items where item.hasSuffix(".appex") {
                let path = (dir as NSString).appendingPathComponent(item)
                let plist = (path as NSString).appendingPathComponent("Contents/Info.plist")
                if let dict = NSDictionary(contentsOfFile: plist),
                   let bid = dict["CFBundleIdentifier"] as? String {
                    map[bid] = path
                }
            }
        }
        bundleIDToPath = map
    }

    private func extractBundleID(from url: String) -> String? {
        guard let colon = url.firstIndex(of: ":") else { return nil }
        let s = String(url[url.index(after: colon)...])
        let bid = s.split(separator: "?").first.map(String.init) ?? s
        return bid.isEmpty ? nil : bid
    }
}
