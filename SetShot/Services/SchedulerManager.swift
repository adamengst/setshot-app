import Foundation

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

    static func installedTime() -> Date? {
        guard isInstalled,
              let plist = NSDictionary(contentsOf: plistURL),
              let interval = plist["StartCalendarInterval"] as? [String: Int],
              let hour = interval["Hour"],
              let minute = interval["Minute"]
        else { return nil }
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: .now)
        comps.hour = hour
        comps.minute = minute
        return Calendar.current.date(from: comps)
    }

    static func install(hour: Int, minute: Int) throws {
        // Run the executable directly so TCC attributes permission requests to
        // SetShot's bundle ID. Using `open` makes `open` the responsible process,
        // which causes TCC to prompt on every defaults read instead of remembering.
        let executablePath = Bundle.main.executablePath!
        let plist: NSDictionary = [
            "Label": label,
            "ProgramArguments": [executablePath, "--background-snapshot"],
            "StartCalendarInterval": ["Hour": hour, "Minute": minute],
            "StandardOutPath": "/tmp/setshot-daily.log",
            "StandardErrorPath": "/tmp/setshot-daily.log",
        ]

        try FileManager.default.createDirectory(at: launchAgentsDir, withIntermediateDirectories: true)
        if isInstalled { try? unload() }
        plist.write(to: plistURL, atomically: true)
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
