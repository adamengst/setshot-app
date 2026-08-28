import Foundation
import AppKit

// Reports the app currently handling each URL scheme SetShot tracks.
// Invoked by setshot.sh as: SetShot --default-handlers
//
// com.apple.launchservices.secure.plist records only *overrides*, so a Mac that
// has never changed its default browser has no handler entry at all and the
// section came out empty. LaunchServices answers for the effective handler
// whether or not an override was ever written, which is what the snapshot wants.
enum DefaultHandlers {
    /// Scheme to emitted domain. The order fixes the order of the output lines.
    private static let schemes: [(scheme: String, domain: String, probe: String)] = [
        ("http",   "default-browser",      "http://example.com"),
        ("https",  "default-browser-https", "https://example.com"),
        ("mailto", "default-mail-client",  "mailto:someone@example.com"),
        ("webcal", "default-calendar-app", "webcal://example.com/calendar.ics"),
        ("feed",   "default-rss-reader",   "feed://example.com/feed.xml"),
    ]

    static func run() {
        var out = ""
        var resolved: [String: String] = [:]
        for entry in schemes {
            guard let url = URL(string: entry.probe),
                  let app = NSWorkspace.shared.urlForApplication(toOpen: url),
                  let id = Bundle(url: app)?.bundleIdentifier
            else { continue }
            resolved[entry.scheme] = id
        }

        // http and https are one control in System Settings, so reporting both meant
        // two rows for every browser change. https is emitted only when it disagrees,
        // which is the case actually worth seeing.
        if let http = resolved["http"] {
            out += "default-browser :: handler = \(http)\n"
            if let https = resolved["https"], https != http {
                out += "default-browser-https :: handler = \(https)\n"
            }
        } else if let https = resolved["https"] {
            out += "default-browser :: handler = \(https)\n"
        }
        for entry in schemes where entry.scheme != "http" && entry.scheme != "https" {
            if let id = resolved[entry.scheme] {
                out += "\(entry.domain) :: handler = \(id)\n"
            }
        }

        if !out.isEmpty { FileHandle.standardOutput.write(Data(out.utf8)) }
        exit(0)
    }
}
