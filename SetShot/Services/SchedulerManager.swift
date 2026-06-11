import Foundation

enum SnapshotSchedule {
    case interval(minutes: Int)
    case daily(hour: Int, minute: Int)
    case weekly(weekday: Int, hour: Int, minute: Int)
    case monthly(day: Int, hour: Int, minute: Int)
}

struct SchedulerManager {
    static let label = "com.tidbits.SetShot.daily-snapshot"

    private static var launchAgentsDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents")
    }

    static var plistURL: URL {
        launchAgentsDir.appendingPathComponent("\(label).plist")
    }

    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    static func installedSchedule() -> SnapshotSchedule? {
        guard isInstalled,
              let plist = NSDictionary(contentsOf: plistURL) else { return nil }

        if let seconds = plist["StartInterval"] as? Int {
            return .interval(minutes: max(1, seconds / 60))
        }

        if let cal = plist["StartCalendarInterval"] as? [String: Int] {
            let hour = cal["Hour"] ?? 8
            let minute = cal["Minute"] ?? 0
            if let weekday = cal["Weekday"] {
                return .weekly(weekday: weekday, hour: hour, minute: minute)
            }
            if let day = cal["Day"] {
                return .monthly(day: day, hour: hour, minute: minute)
            }
            return .daily(hour: hour, minute: minute)
        }

        return nil
    }

    static func install(schedule: SnapshotSchedule) throws {
        let executablePath = Bundle.main.executablePath!
        var plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [executablePath, "--background-snapshot"],
            "StandardOutPath": "/tmp/setshot-daily.log",
            "StandardErrorPath": "/tmp/setshot-daily.log",
            "AssociatedBundleIdentifiers": "com.tidbits.SetShot",
        ]

        switch schedule {
        case .interval(let minutes):
            plist["StartInterval"] = minutes * 60
        case .daily(let hour, let minute):
            plist["StartCalendarInterval"] = ["Hour": hour, "Minute": minute]
        case .weekly(let weekday, let hour, let minute):
            plist["StartCalendarInterval"] = ["Weekday": weekday, "Hour": hour, "Minute": minute]
        case .monthly(let day, let hour, let minute):
            plist["StartCalendarInterval"] = ["Day": day, "Hour": hour, "Minute": minute]
        }

        try FileManager.default.createDirectory(at: launchAgentsDir, withIntermediateDirectories: true)
        if isInstalled { try? unload() }
        (plist as NSDictionary).write(to: plistURL, atomically: true)
        try load()
    }

    static func uninstall() throws {
        guard isInstalled else { return }
        try? unload()
        try FileManager.default.removeItem(at: plistURL)
    }

    // MARK: - Private

    private static func load() throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = ["load", plistURL.path]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try p.run()
        p.waitUntilExit()
    }

    private static func unload() throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = ["unload", plistURL.path]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try p.run()
        p.waitUntilExit()
    }
}
