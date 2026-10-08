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

    var id: String { rawValue }

    var title: String {
        switch self {
        case .soundDevices: return "Ignore changes to sound input and output devices"
        }
    }

    var explanation: String {
        switch self {
        case .soundDevices:
            return "macOS switches the microphone and speakers whenever AirPods or other "
                + "headphones connect or disconnect, so these changes can appear repeatedly."
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
            ]
        }
    }

    var defaultsKey: String { "IgnoreChanges.\(rawValue)" }
}

/// The groups the user has turned on, read from UserDefaults. Scheduled snapshots run
/// in a separate process, so this is read at the point of use rather than passed in.
struct IgnoredChanges {
    private let settings: Set<String>

    init(groups: [IgnoredChangeGroup]) {
        settings = Set(groups.flatMap { $0.settings.map { "\($0.domain)|\($0.key)" } })
    }

    static func current(_ defaults: UserDefaults = .standard) -> IgnoredChanges {
        IgnoredChanges(groups: IgnoredChangeGroup.allCases.filter { defaults.bool(forKey: $0.defaultsKey) })
    }

    var isEmpty: Bool { settings.isEmpty }

    func covers(domain: String, key: String) -> Bool {
        settings.contains("\(domain)|\(key)")
    }
}
