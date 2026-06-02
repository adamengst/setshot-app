import AppKit

actor SettingsPaneIconProvider {
    static let shared = SettingsPaneIconProvider()
    private init() {}

    private var bundleIDToPath: [String: String]?
    private var iconCache: [String: NSImage] = [:]

    // Legacy / renamed bundle IDs that don't appear in ExtensionKit
    private let aliases: [String: String] = [
        "com.apple.preference.security":        "com.apple.settings.PrivacySecurity.extension",
        "com.apple.preferences.password":       "com.apple.Touch-ID-Settings.extension",
        "com.apple.preference.sound":           "com.apple.Sound-Settings.extension",
        // KB entries use this ID but the actual bundle uses a hyphen between Screen and Time
        "com.apple.ScreenTime-Settings.extension": "com.apple.Screen-Time-Settings.extension",
    ]

    // Extension bundles whose pane icon is a named image in Assets.car or a
    // standalone file — only used for panes with ISTypeIdentifier (system-rendered)
    // icons that have no equivalent SF symbol. Maps bundle ID → asset name.
    private let namedAssets: [String: String] = [
        "com.apple.BluetoothSettings":               "BluetoothIcon",
        "com.apple.Displays-Settings.extension":     "DisplaysPrefIcon",
        "com.apple.Focus-Settings.extension":        "SettingsIcon",
        "com.apple.Accessibility-Settings.extension": "UniversalAccessPref",
        "com.apple.Time-Machine-Settings.extension": "TimeMachineSettingsIcon",
    ]

    // Panes whose icon is defined as an SF Symbol + enclosure color in
    // ISGraphicIconConfiguration. Colors match the ISEnclosureColor values.
    private let sfSymbolFallbacks: [String: (symbol: String, r: CGFloat, g: CGFloat, b: CGFloat)] = [
        // Gray enclosures
        "com.apple.Battery-Settings.extension":           ("bolt.fill",                             0.30, 0.72, 0.35),
        "com.apple.Trackpad-Settings.extension":          ("rectangle.and.hand.point.up.left.fill", 0.55, 0.55, 0.60),
        "com.apple.Mouse-Settings.extension":             ("magicmouse.fill",                       0.55, 0.55, 0.60),
        "com.apple.Software-Update-Settings.extension":   ("gear.badge",                            0.55, 0.55, 0.60),
        "com.apple.ControlCenter-Settings.extension":     ("switch.2",                              0.55, 0.55, 0.60),
        "com.apple.Startup-Disk-Settings.extension":      ("internaldrive.fill",                    0.55, 0.55, 0.60),
        "com.apple.Sharing-Settings.extension":           ("figure.walk.diamond.fill",              0.55, 0.55, 0.60),
        "com.apple.LoginItems-Settings.extension":        ("list.bullet",                           0.55, 0.55, 0.60),
        "com.apple.Print-Scan-Settings.extension":        ("printer.fill",                          0.55, 0.55, 0.60),
        "com.apple.Keyboard-Settings.extension":          ("keyboard.fill",                         0.55, 0.55, 0.60),
        // Blue enclosures
        "com.apple.Network-Settings.extension":           ("network",                               0.20, 0.54, 0.90),
        "com.apple.Date-Time-Settings.extension":         ("calendar.badge.clock",                  0.20, 0.54, 0.90),
        "com.apple.Internet-Accounts-Settings.extension": ("at",                                    0.20, 0.54, 0.90),
        "com.apple.Localization-Settings.extension":      ("globe",                                 0.20, 0.54, 0.90),
        "com.apple.Users-Groups-Settings.extension":      ("person.2.fill",                         0.20, 0.54, 0.90),
        // Cyan enclosures
        "com.apple.ScreenSaver-Settings.extension":       ("moon.stars.fill",                       0.28, 0.80, 0.85),
        "com.apple.Wallpaper-Settings.extension":         ("photo.fill",                            0.28, 0.80, 0.85),
        // Black enclosures
        "com.apple.Appearance-Settings.extension":        ("circle.lefthalf.filled",                0.07, 0.07, 0.10),
        "com.apple.Lock-Screen-Settings.extension":       ("dots.below.lock.fill",                  0.07, 0.07, 0.10),
        // Other / ISTypeIdentifier approximations
        "com.apple.Sound-Settings.extension":             ("speaker.wave.3.fill",                   0.84, 0.24, 0.24),
        "com.apple.AirDrop-Handoff-Settings.extension":   ("dot.radiowaves.left.and.right",         0.20, 0.60, 0.90),
        "com.apple.settings.PrivacySecurity.extension":   ("hand.raised.fill",                      0.22, 0.50, 0.90),
        "com.apple.Touch-ID-Settings.extension":          ("touchid",                               0.85, 0.30, 0.55),
        "com.apple.Desktop-Settings.extension":           ("menubar.dock.rectangle",                0.20, 0.45, 0.85),
        "com.apple.Notifications-Settings.extension":     ("bell.badge.fill",                       0.85, 0.20, 0.22),
        // macOS 15.7.7 replaced the real icons for these panes with generic placeholders
        "com.apple.Siri-Settings.extension":              ("waveform",                               0.40, 0.20, 0.80),
        "com.apple.Spotlight-Settings.extension":         ("magnifyingglass",                        0.33, 0.10, 0.75),
        // Apple Account pane — covers Find My, iCloud, etc.
        "com.apple.settings.AppleIDSettings":             ("person.crop.circle.fill",               0.20, 0.54, 0.90),
    ]

    func icon(forSettingsURL urlString: String?, domain: String, iconBundleID: String? = nil) async -> NSImage? {
        let resolvedID: String?
        if let iconBundleID {
            resolvedID = iconBundleID
        } else if let urlString, let extracted = extractBundleID(from: urlString) {
            resolvedID = aliases[extracted] ?? extracted
        } else {
            resolvedID = nil
        }

        if let resolvedID {
            if let cached = iconCache[resolvedID] { return cached }
            ensureBundleMap()
            if let path = bundleIDToPath?[resolvedID] {
                // Curated SF-symbol fallbacks take priority over any icon.icns in the bundle —
                // macOS 15.7.7 replaced real extension icons with a generic 495 KB placeholder
                // across Battery, AirDrop, Network, Screen Saver, and others.
                if let fb = sfSymbolFallbacks[resolvedID] {
                    let img = await MainActor.run { self.renderedSFSymbol(fb.symbol, r: fb.r, g: fb.g, b: fb.b) }
                    iconCache[resolvedID] = img
                    return img
                }
                // Try file-based icon (namedAssets, CFBundleIconFile, icon.icns).
                if let img = iconFromBundle(path: path, bundleID: resolvedID) {
                    iconCache[resolvedID] = img
                    return img
                }
            }
            // Not an ExtensionKit bundle — try as a regular app (e.g. com.apple.screenshot.launcher)
            if let url = await MainActor.run(body: { NSWorkspace.shared.urlForApplication(withBundleIdentifier: resolvedID) }) {
                let img = await MainActor.run { NSWorkspace.shared.icon(forFile: url.path) }
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

    // Loads a pane icon directly from an extension bundle, bypassing NSWorkspace
    // which doesn't reliably surface icons for .appex bundles.
    private func iconFromBundle(path: String, bundleID: String) -> NSImage? {
        let resources = (path as NSString).appendingPathComponent("Contents/Resources")

        // 1. Named asset — try as a standalone file first, then via Bundle API
        //    for compiled asset catalogs.
        if let name = namedAssets[bundleID] {
            for ext in ["icns", "png", "tiff"] {
                let filePath = (resources as NSString).appendingPathComponent("\(name).\(ext)")
                if let img = NSImage(contentsOfFile: filePath) { return img }
            }
            if let bundle = Bundle(path: path),
               let img = bundle.image(forResource: NSImage.Name(name)) { return img }
        }

        // 2. Explicit CFBundleIconFile — load the .icns directly by path.
        if let dict = NSDictionary(contentsOfFile: (path as NSString).appendingPathComponent("Contents/Info.plist")),
           let iconFile = dict["CFBundleIconFile"] as? String {
            let stem = iconFile.hasSuffix(".icns") ? iconFile : "\(iconFile).icns"
            let filePath = (resources as NSString).appendingPathComponent(stem)
            if let img = NSImage(contentsOfFile: filePath) { return img }
        }

        // 3. Fallback: icon.icns in Resources.
        let fallback = (resources as NSString).appendingPathComponent("icon.icns")
        if let img = NSImage(contentsOfFile: fallback) { return img }

        return nil
    }

    // Renders an SF Symbol centred on a rounded-rectangle background, matching
    // the System Settings sidebar icon style for panes that have no file icon.
    // nonisolated so it can be dispatched to the main thread via MainActor.run
    // (NSImage.lockFocus must be called on the main thread).
    nonisolated private func renderedSFSymbol(_ symbol: String, r: CGFloat, g: CGFloat, b: CGFloat) -> NSImage? {
        let px: CGFloat = 256
        let color = NSColor(srgbRed: r, green: g, blue: b, alpha: 1)

        guard let sym = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(
                NSImage.SymbolConfiguration(pointSize: px * 0.48, weight: .medium)
                    .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
            )
        else { return nil }

        let result = NSImage(size: NSSize(width: px, height: px))
        result.lockFocus()

        let rect = NSRect(x: 0, y: 0, width: px, height: px)
        let path = NSBezierPath(roundedRect: rect, xRadius: px * 0.22, yRadius: px * 0.22)
        color.setFill()
        path.fill()

        let symSize = sym.size
        let symRect = NSRect(x: (px - symSize.width) / 2, y: (px - symSize.height) / 2,
                             width: symSize.width, height: symSize.height)
        sym.draw(in: symRect, from: .zero, operation: .sourceOver, fraction: 1,
                 respectFlipped: true, hints: nil)

        result.unlockFocus()
        return result
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
