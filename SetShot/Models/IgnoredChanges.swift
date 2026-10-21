import Foundation

/// A group of recognized settings the user can choose not to see, each one switch in
/// Settings → Ignored Changes.
///
/// A group names its settings by domain and key rather than by KB entry, because
/// journal entries record only the domain and key. That lets one test hide a fresh
/// comparison's rows and the journal entries recorded before the switch was turned on.
///
/// To add a group, add a case and give it a title, an explanation and its settings.
enum IgnoredChangeGroup: String, CaseIterable, Identifiable {
    case soundDevices
    case screenshotMode
    case dnsFromNetwork

    var id: String { rawValue }

    var title: String {
        switch self {
        case .soundDevices: return "Ignore changes to sound input and output devices"
        case .screenshotMode: return "Ignore screenshot settings changes"
        case .dnsFromNetwork: return "Ignore DNS changes from switching networks"
        }
    }

    var explanation: String {
        switch self {
        case .soundDevices:
            return "macOS switches the microphone and speakers, including FaceTime's "
                + "microphone, whenever AirPods or other headphones connect or disconnect, "
                + "so these changes can appear repeatedly."
        case .screenshotMode:
            return "The Screenshot tool remembers whether you last took a screenshot or a "
                + "screen recording, and whether you captured the whole screen, a window, or a "
                + "selection, so using it can change these settings frequently."
        case .dnsFromNetwork:
            return "Each network you join assigns its own DNS servers and search domains, "
                + "so moving between networks changes them. DNS servers set manually for a "
                + "connection are still reported."
        }
    }

    /// The settings this group hides, as domain and key.
    var settings: [(domain: String, key: String)] {
        switch self {
        case .soundDevices:
            return [
                // The devices in use, read from coreaudiod by the snapshot script.
                ("sound", "outputDevice"),
                ("sound", "inputDevice"),
                // The preferred devices macOS keeps on disk, which move with them.
                ("com.apple.audio.SystemSettings", "preferred devices.output[0].uid"),
                ("com.apple.audio.SystemSettings", "preferred devices.input[0].uid"),
                ("com.apple.audio.SystemSettings", "preferred devices.system output[0].uid"),
                // FaceTime follows the same switch to and from AirPods.
                ("com.apple.FaceTime", "PreferredAudioInputDeviceUID"),
            ]
        case .screenshotMode:
            return [
                // Screenshot or screen recording, and whole screen, window or selection.
                // Where captures are saved and the other Options stay reported: those
                // are choices made once, not a side effect of taking a screenshot.
                ("com.apple.screencapture", "video"),
                ("com.apple.screencapture", "style"),
            ]
        case .dnsFromNetwork:
            return [
                ("dns", "domain"),
            ]
        }
    }

    /// Settings this group hides by key prefix, for those recorded as numbered lists.
    var settingPrefixes: [(domain: String, prefix: String)] {
        switch self {
        case .dnsFromNetwork:
            // The resolvers in use, whatever supplied them. Manually set servers are
            // captured separately as dns-manual and are not covered.
            return [
                ("dns", "nameserver["),
                ("dns", "searchdomain["),
            ]
        default:
            return []
        }
    }

    var defaultsKey: String { "IgnoreChanges.\(rawValue)" }
}

/// The groups the user has turned on, read from UserDefaults. Scheduled snapshots run
/// in a separate process, so this is read at the point of use rather than passed in.
struct IgnoredChanges {
    private let settings: Set<String>
    private let prefixes: [(domain: String, prefix: String)]

    init(groups: [IgnoredChangeGroup]) {
        settings = Set(groups.flatMap { $0.settings.map { "\($0.domain)|\($0.key)" } })
        prefixes = groups.flatMap(\.settingPrefixes)
    }

    static func current(_ defaults: UserDefaults = .standard) -> IgnoredChanges {
        IgnoredChanges(groups: IgnoredChangeGroup.allCases.filter { defaults.bool(forKey: $0.defaultsKey) })
    }

    var isEmpty: Bool { settings.isEmpty && prefixes.isEmpty }

    func covers(domain: String, key: String) -> Bool {
        settings.contains("\(domain)|\(key)")
            || prefixes.contains { $0.domain == domain && key.hasPrefix($0.prefix) }
    }
}
