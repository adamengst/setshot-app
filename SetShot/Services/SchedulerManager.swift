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

    static func install(hour: Int, minute: Int) throws {
        let scriptPath = Bundle.main.bundlePath + "/Contents/Resources/setshot.sh"
        let snapshotsDir = SnapshotStore.shared.directory.path
        let command = """
            "\(scriptPath)" snapshot "\(snapshotsDir)/setshot_$(date +%Y-%m-%d_%H%M).txt.gz" 2>/dev/null; true
            """

        let plist: NSDictionary = [
            "Label": label,
            "ProgramArguments": ["/bin/bash", "-c", command],
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
