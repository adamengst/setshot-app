import Foundation
import IOKit
import MusicKit

enum SupportKind: String, CaseIterable, Encodable {
    case bug
    case question
    case suggestion

    var label: String {
        switch self {
        case .bug:        return "Bug Report"
        case .question:   return "Question"
        case .suggestion: return "Suggestion"
        }
    }
}

/// What Help → Contact Support sends. The worker files it as an issue in the private
/// submissions repository, labelled `support`.
struct SupportRequest: Encodable {
    let kind: SupportKind
    let message: String
    /// For the greeting in a reply. Omitted from the JSON when nil.
    let name: String?
    /// Omitted from the JSON when nil, which tells the worker no reply is wanted.
    let email: String?
    let diagnostics: SupportDiagnostics?

    /// Trims what was typed and drops an empty name or address, so a field left blank
    /// or holding only spaces is not sent as a value that fails validation.
    init(kind: SupportKind, message: String, name: String = "", email: String,
         diagnostics: SupportDiagnostics?) {
        self.kind = kind
        self.message = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.name = trimmedName.isEmpty ? nil : trimmedName
        let address = email.trimmingCharacters(in: .whitespacesAndNewlines)
        self.email = address.isEmpty ? nil : address
        self.diagnostics = diagnostics
    }
}

/// The facts about this Mac that most support questions turn on. The sheet shows
/// every one of them before anything is sent, and the sender can leave them out.
struct SupportDiagnostics: Encodable, Equatable {
    let appVersion: String
    let kbVersion: String
    let macOSVersion: String
    let macModel: String
    let chip: String
    let fullDiskAccess: String
    let mediaAccess: String

    enum CodingKeys: String, CodingKey {
        case appVersion = "app_version"
        case kbVersion = "kb_version"
        case macOSVersion = "macos_version"
        case macModel = "mac_model"
        case chip
        case fullDiskAccess = "full_disk_access"
        case mediaAccess = "media_access"
    }

    /// The rows as the sheet shows them, in the order the worker writes them.
    var rows: [(label: String, value: String)] {
        [("SetShot", appVersion),
         ("Knowledge base", kbVersion),
         ("macOS", macOSVersion),
         ("Mac model", macModel),
         ("Chip", chip),
         ("Full Disk Access", fullDiskAccess),
         ("Media & Apple Music", mediaAccess)]
    }

    /// Reads the current values. Opening the privacy database can block, so call this
    /// off the main thread.
    static func current() -> SupportDiagnostics {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        var macOS = "\(os.majorVersion).\(os.minorVersion)"
        if os.patchVersion > 0 { macOS += ".\(os.patchVersion)" }
        if let build = sysctlString("kern.osversion") { macOS += " (\(build))" }

        return SupportDiagnostics(
            appVersion: SubmissionService.appVersion,
            kbVersion: SubmissionService.kbVersion,
            macOSVersion: macOS,
            macModel: macModelName(),
            chip: sysctlString("machdep.cpu.brand_string") ?? "unknown",
            fullDiskAccess: SnapshotRunner.canReadSystemTCC() ? "Granted" : "Not granted",
            mediaAccess: mediaAccessDescription(MusicAuthorization.currentStatus))
    }

    /// The Mac's marketing name, such as "MacBook Pro (14-inch, Nov 2024)", rather than
    /// a model identifier like Mac16,8 that has to be looked up. Falls back to the
    /// identifier when no name can be found.
    static func macModelName() -> String {
        deviceTreeProductName()
            ?? systemInformationName()
            ?? sysctlString("hw.model")
            ?? "unknown"
    }

    /// Apple silicon Macs carry their marketing name in the device tree, the same text
    /// About This Mac shows. Intel Macs have no such entry.
    private static func deviceTreeProductName() -> String? {
        let entry = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/product")
        guard entry != 0 else { return nil }
        defer { IOObjectRelease(entry) }
        guard let data = IORegistryEntryCreateCFProperty(
            entry, "product-name" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? Data
        else { return nil }
        let name = String(decoding: data.prefix { $0 != 0 }, as: UTF8.self)
            .trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : name
    }

    /// On Intel Macs, the name System Information looked up from Apple and cached. It is
    /// there only once About This Mac or System Information has been opened.
    private static func systemInformationName() -> String? {
        let names = UserDefaults(suiteName: "com.apple.SystemProfiler")?
            .dictionary(forKey: "CPU Names") as? [String: String]
        return names?.values.first { !$0.isEmpty }
    }

    static func mediaAccessDescription(_ status: MusicAuthorization.Status) -> String {
        switch status {
        case .authorized:    return "Granted"
        case .denied:        return "Denied"
        case .restricted:    return "Restricted"
        case .notDetermined: return "Not requested"
        @unknown default:    return "Unknown"
        }
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }
}
