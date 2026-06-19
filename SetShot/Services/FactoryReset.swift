import AppKit
import Foundation

enum FactoryReset {

    static func confirmAndRun() {
        let alert = NSAlert()
        alert.messageText = "Reset SetShot to Factory Defaults?"
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Reset SetShot")
        alert.addButton(withTitle: "Cancel")

        let body = """
            This will:
              \u{2022} Move all snapshots and journal entries to the Trash
              \u{2022} Remove Full Disk Access and Media & Apple Music permissions
              \u{2022} Delete all preferences and settings

            SetShot will quit when the reset is complete. This cannot be undone.
            """
        let label = NSTextField(wrappingLabelWithString: body)
        label.alignment = .left
        label.frame = NSRect(x: 0, y: 0, width: 280, height: 1)
        label.sizeToFit()
        alert.accessoryView = label

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        run()
    }

    private static func run() {
        try? SchedulerManager.uninstall()

        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? fm.trashItem(at: appSupport.appendingPathComponent("SetShot"), resultingItemURL: nil)

        tccutil("reset", "SystemPolicyAllFiles", "com.tidbits.SetShot")
        tccutil("reset", "MediaLibrary", "com.tidbits.SetShot")

        UserDefaults.standard.removePersistentDomain(forName: "com.tidbits.SetShot")

        let prefPlist = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences/com.tidbits.SetShot.plist")
        try? fm.removeItem(at: prefPlist)

        NSApp.terminate(nil)
    }

    private static func tccutil(_ args: String...) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        task.arguments = args
        try? task.run()
        task.waitUntilExit()
    }
}
