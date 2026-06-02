import Foundation

struct SettingsPaneOrder {
    // Rank values match the System Settings sidebar order in macOS Sequoia 15.
    // Gaps between values leave room for insertions without renumbering.
    private static let order: [String: Int] = [
        // Apple Account / iCloud / Family
        "com.apple.settings.AppleIDSettings":              100,
        "com.apple.Family-Settings.extension":             110,
        // Connectivity
        "com.apple.WiFi-Settings.extension":               200,
        "com.apple.BluetoothSettings":                     210,
        "com.apple.Network-Settings.extension":            220,
        "com.apple.VPN-Settings.extension":                230,
        // Battery
        "com.apple.Battery-Settings.extension":            300,
        // Notifications & Focus
        "com.apple.Notifications-Settings.extension":      400,
        "com.apple.Sound-Settings.extension":              410,
        "com.apple.preference.sound":                      410,
        "com.apple.Focus-Settings.extension":              420,
        "com.apple.Screen-Time-Settings.extension":        430,
        "com.apple.ScreenTime-Settings.extension":         430,
        // Appearance & system
        "com.apple.Appearance-Settings.extension":         500,
        "com.apple.Accessibility-Settings.extension":      510,
        "com.apple.ControlCenter-Settings.extension":      520,
        "com.apple.Siri-Settings.extension":               530,
        "com.apple.Spotlight-Settings.extension":          540,
        "com.apple.settings.PrivacySecurity.extension":    550,
        "com.apple.preference.security":                   550,
        // Desktop & display
        "com.apple.Desktop-Settings.extension":            600,
        "com.apple.Displays-Settings.extension":           610,
        "com.apple.Wallpaper-Settings.extension":          620,
        "com.apple.ScreenSaver-Settings.extension":        630,
        "com.apple.Lock-Screen-Settings.extension":        640,
        // Accounts
        "com.apple.Internet-Accounts-Settings.extension":  700,
        "com.apple.Passwords-Settings.extension":          710,
        "com.apple.Wallet-Settings.extension":             720,
        // Region & sharing
        "com.apple.Game-Center-Settings.extension":        800,
        "com.apple.Localization-Settings.extension":       810,
        "com.apple.Date-Time-Settings.extension":          820,
        "com.apple.Sharing-Settings.extension":            830,
        "com.apple.Time-Machine-Settings.extension":       840,
        "com.apple.AirDrop-Handoff-Settings.extension":    850,
        // Input
        "com.apple.Keyboard-Settings.extension":           900,
        "com.apple.Mouse-Settings.extension":              910,
        "com.apple.Trackpad-Settings.extension":           920,
        "com.apple.Print-Scan-Settings.extension":         930,
        // Login & software
        "com.apple.Users-Groups-Settings.extension":      1000,
        "com.apple.LoginItems-Settings.extension":        1010,
        "com.apple.Software-Update-Settings.extension":   1020,
        "com.apple.Startup-Disk-Settings.extension":      1030,
        "com.apple.Touch-ID-Settings.extension":          1040,
        "com.apple.preferences.password":                 1040,
        // ClassKit (appears when profile is installed)
        "com.apple.ClassKit-Settings.extension":          1100,
    ]

    // App-settings entries (no settings_url or non-pane bundle) sort after all
    // System Settings panes, alphabetically by description within each domain.
    static let appSettingsRank = 9000

    static func rank(forSettingsURL url: String?) -> Int {
        guard let url,
              let colon = url.firstIndex(of: ":") else { return appSettingsRank }
        let afterColon = String(url[url.index(after: colon)...])
        let bundleID = String(afterColon.split(separator: "?").first ?? Substring(afterColon))
        return order[bundleID] ?? appSettingsRank
    }
}
