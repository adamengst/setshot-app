import SwiftUI
import Sparkle
import UserNotifications

struct SetShotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appModel = AppModel()
    @StateObject private var updaterState = UpdaterState()

    private static let isBackgroundLaunch =
        CommandLine.arguments.contains("--background-snapshot")

    var body: some Scene {
        WindowGroup {
            if Self.isBackgroundLaunch {
                // Headless mode: AppDelegate handles the snapshot; show nothing.
                EmptyView().frame(width: 0, height: 0)
            } else {
                ContentView()
                    .environmentObject(appModel)
                    .environmentObject(updaterState)
                    .background(WindowFrameSaver(name: "SetShotMainWindow"))
                    .task { await appModel.start(); PingService.pingIfNeeded() }
                    .task { await SettingsPaneIconProvider.shared.prewarm() }
            }
        }
        .defaultSize(width: 750, height: 760)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About SetShot") {
                    let flags = NSEvent.modifierFlags
                    if flags.contains(.control) && flags.contains(.option) && flags.contains(.command) {
                        FactoryReset.confirmAndRun()
                    } else {
                        AboutWindowController.shared.show(appModel: appModel)
                    }
                }
            }
            CommandGroup(after: .appInfo) {
                // Settings is a tab in the main window rather than its own window, so
                // the command tells the window to switch rather than opening anything.
                Button("Settings…") {
                    NotificationCenter.default.post(name: .setshotOpenSettings, object: nil)
                }
                .keyboardShortcut(",", modifiers: .command)

                // Also unavailable under translocation: Sparkle cannot replace an app
                // running from a read-only mount at a path that is not where it lives,
                // so the check would only ever end in a failure the user can do nothing
                // about from here.
                Button("Check for Updates…") {
                    updaterState.controller.updater.checkForUpdates()
                }
                .disabled(!updaterState.canCheckForUpdates || Translocation.isActive)
            }
            // The View menu offers the user nothing here. Its toolbar items act on the
            // only toolbar in the app -- the Export menu in a comparison window -- where
            // hiding it removes the sole way to export with no visible way back, and
            // "Customize Toolbar…" is inert because that toolbar has no customisable
            // items. Suppressing both groups leaves AppKit's own additions -- Enter Full
            // Screen, which the green traffic-light button already offers, and the window
            // tabbing pair -- so AppDelegate removes what remains.
            CommandGroup(replacing: .toolbar) { }
            CommandGroup(replacing: .sidebar) { }

            CommandGroup(replacing: .help) {
                Button("Release Notes") {
                    ReleaseNotesWindowController.shared.show()
                }
            }
        }

        WindowGroup(for: UUID.self) { $id in
            if let id, let record = appModel.comparisons[id] {
                ResultsView(diff: record.diff, before: record.before, after: record.after)
            } else {
                StaleComparisonDismisser()
            }
        }
        .defaultSize(width: 720, height: 540)

    }
}

final class ReleaseNotesWindowController {
    static let shared = ReleaseNotesWindowController()
    private var window: NSWindow?

    func show() {
        if let window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            return
        }
        let hosting = NSHostingController(rootView: ReleaseNotesView())
        let win = NSWindow(contentViewController: hosting)
        win.title = "Release Notes"
        win.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        win.isReleasedWhenClosed = false
        win.setContentSize(NSSize(width: 680, height: 560))
        win.alphaValue = 0
        win.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async {
            if let main = NSApp.windows.first(where: { $0.title == "SetShot" && $0.isVisible }) {
                let mf = main.frame
                let wf = win.frame
                win.setFrameOrigin(NSPoint(
                    x: mf.midX - wf.width / 2,
                    y: mf.midY - wf.height / 2
                ))
            } else {
                win.center()
            }
            win.alphaValue = 1
        }
        self.window = win
    }
}

final class AboutWindowController {
    static let shared = AboutWindowController()
    private var window: NSWindow?

    func show(appModel: AppModel) {
        if let window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            return
        }
        let hosting = NSHostingController(rootView: AboutPanelView().environmentObject(appModel))
        let win = NSWindow(contentViewController: hosting)
        win.title = "About SetShot"
        win.styleMask = [.titled, .closable]
        win.isReleasedWhenClosed = false
        win.alphaValue = 0
        win.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async {
            if let main = NSApp.windows.first(where: { $0.title == "SetShot" && $0.isVisible }) {
                let mf = main.frame
                let wf = win.frame
                win.setFrameOrigin(NSPoint(
                    x: mf.midX - wf.width / 2,
                    y: mf.midY - wf.height / 2
                ))
            } else {
                win.center()
            }
            win.alphaValue = 1
        }
        self.window = win
    }
}

private struct WindowFrameSaver: NSViewRepresentable {
    let name: String

    func makeNSView(context: Context) -> FrameSaverView { FrameSaverView(name: name) }
    func updateNSView(_ nsView: FrameSaverView, context: Context) {}

    class FrameSaverView: NSView {
        let name: String
        private var observers: [NSObjectProtocol] = []
        private static var initializedWindowIDs: Set<ObjectIdentifier> = []

        init(name: String) { self.name = name; super.init(frame: .zero) }
        required init?(coder: NSCoder) { fatalError() }

        private var key: String { "WindowFrame.\(name)" }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            let wid = ObjectIdentifier(window)
            guard !Self.initializedWindowIDs.contains(wid) else { return }
            Self.initializedWindowIDs.insert(wid)

            // Hide immediately so repositioning is invisible to the user.
            window.alphaValue = 0

            let savedKey = key
            var readyToSave = false

            observers.append(NotificationCenter.default.addObserver(
                forName: NSWindow.didMoveNotification, object: window, queue: .main
            ) { [weak window] _ in
                guard readyToSave, let window else { return }
                UserDefaults.standard.set(NSStringFromRect(window.frame), forKey: savedKey)
            })

            // didEndLiveResizeNotification only fires for user-driven resizes.
            observers.append(NotificationCenter.default.addObserver(
                forName: NSWindow.didEndLiveResizeNotification, object: window, queue: .main
            ) { [weak window] _ in
                guard let window else { return }
                UserDefaults.standard.set(NSStringFromRect(window.frame), forKey: savedKey)
            })

            observers.append(NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification, object: window, queue: .main
            ) { _ in Self.initializedWindowIDs.remove(wid) })

            // Let SwiftUI finish its layout pass, then apply the saved frame
            // and fade in. The window is invisible throughout, so there is no jump.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak window] in
                guard let window else { return }
                if let str = UserDefaults.standard.string(forKey: savedKey) {
                    let frame = NSRectFromString(str)
                    if frame.width > 0, frame.height > 0 {
                        window.setFrame(frame, display: false)
                    }
                }
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.15
                    window.animator().alphaValue = 1
                }
                readyToSave = true
            }
        }

        deinit {
            observers.forEach { NotificationCenter.default.removeObserver($0) }
        }
    }
}

// Closes a restored comparison window whose UUID is no longer in appModel.comparisons.
private struct StaleComparisonDismisser: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.alphaValue = 0
            window.close()
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    func applicationWillFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--background-snapshot") {
            NSApp.setActivationPolicy(.prohibited)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        migrateAutoDeleteDefault()
        if CommandLine.arguments.contains("--background-snapshot") {
            runBackgroundSnapshot()
        } else {
            UNUserNotificationCenter.current().delegate = self
            // SwiftUI finishes building the main menu after this point, so the empty
            // View menu does not exist yet.
            DispatchQueue.main.async {
                Self.hideViewMenu()
                Self.warnIfTranslocated()
            }
        }
    }

    /// Offers to move SetShot into Applications when it is running translocated.
    ///
    /// Sparkle's own handling of this states the problem and leaves the user to act;
    /// most Mac apps that deal with it at all offer the move instead, which is the
    /// thing the user wants either way. Moving relaunches from the new location and
    /// quits this copy.
    ///
    /// Continuing is allowed on purpose. Snapshots and comparisons work perfectly well
    /// translocated -- only scheduling and updating do not -- so shutting the app down
    /// over it would be heavier than the problem.
    private static func warnIfTranslocated() {
        guard Translocation.isActive else { return }

        let alert = NSAlert()
        alert.messageText = "Move SetShot to your Applications folder"
        alert.informativeText = Translocation.advice
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Move to Applications Folder")  // default, first
        alert.addButton(withTitle: "Continue Anyway")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        moveToApplications(replacingExisting: false)
    }

    private static func moveToApplications(replacingExisting: Bool) {
        do {
            let moved = try Translocation.moveToApplications(replacingExisting: replacingExisting)
            relaunch(at: moved)
        } catch Translocation.MoveFailure.alreadyThere(let existing) {
            // Worth a second question rather than a refusal: an older copy in
            // Applications is the ordinary case when someone is updating by hand.
            let ask = NSAlert()
            ask.messageText = "Replace the copy already in your Applications folder?"
            ask.informativeText = "There is already a SetShot at \(existing.path). "
                + "It will be moved to the Trash, so you can put it back if you need it."
            ask.alertStyle = .warning
            ask.addButton(withTitle: "Replace")
            ask.addButton(withTitle: "Cancel")
            guard ask.runModal() == .alertFirstButtonReturn else { return }
            moveToApplications(replacingExisting: true)
        } catch {
            // Falling back to the manual instructions rather than leaving the user
            // with only a failure: the drag still works when the move does not.
            let failed = NSAlert()
            failed.messageText = "SetShot could not move itself"
            failed.informativeText = error.localizedDescription + "\n\n" + Translocation.manualSteps
            failed.alertStyle = .warning
            failed.addButton(withTitle: "OK")
            failed.runModal()
        }
    }

    /// Opens the moved copy, then quits this one once it is actually running --
    /// terminating first would leave nothing to hand off to.
    private static func relaunch(at url: URL) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
            DispatchQueue.main.async {
                if let error {
                    let alert = NSAlert()
                    alert.messageText = "SetShot was moved but could not be reopened"
                    alert.informativeText = "It is now at \(url.path). Open it from there.\n\n"
                        + error.localizedDescription
                    alert.addButton(withTitle: "OK")
                    alert.runModal()
                }
                NSApp.terminate(nil)
            }
        }
    }

    /// Hides the View menu.
    ///
    /// It cannot be found by its contents. SwiftUI leaves it holding a single
    /// separator, and AppKit fills in Show Tab Bar, Show All Tabs and Enter Full
    /// Screen only while the menu is being tracked -- calling `update()` does not
    /// bring them forward. Nor by its title, which is localised: a Japanese system
    /// titles it 表示.
    ///
    /// The lone separator is the signature. A menu whose only content is a separator
    /// holds no commands, and nothing else here looks like that -- every other menu
    /// is populated by this point (App 11 items, File 4, Edit 16, Window 4, Help 1),
    /// so a menu carrying real commands is never caught by this.
    ///
    /// Hidden rather than removed because removing does not hold: SwiftUI puts the
    /// menu back, and the bar ends up showing an empty View again. `isHidden` sticks.
    private static func hideViewMenu() {
        guard let mainMenu = NSApp.mainMenu else { return }
        for item in mainMenu.items {
            guard let submenu = item.submenu,
                  submenu.items.count == 1,
                  submenu.items[0].isSeparatorItem
            else { continue }
            item.isHidden = true
            return
        }
    }

    // One-time migration: users who had the scheduler set up before this setting
    // existed were effectively at false (the old missing-key default). If the key
    // is still absent on their first post-b22 launch, preserve that by writing
    // false explicitly so the new default of true doesn't silently change behavior.
    // New users who enable the scheduler after this migration has run will get true.
    private func migrateAutoDeleteDefault() {
        let ud = UserDefaults.standard
        guard !ud.bool(forKey: "AutoDeleteMigrationDone") else { return }
        ud.set(true, forKey: "AutoDeleteMigrationDone")
        if ud.object(forKey: "AutoDeleteEmptyScheduledSnapshots") == nil,
           SchedulerManager.isInstalled {
            ud.set(false, forKey: "AutoDeleteEmptyScheduledSnapshots")
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        if let beforeID = info["beforeID"] as? String,
           let afterID = info["afterID"] as? String {
            UserDefaults.standard.set(beforeID, forKey: "PendingComparisonBeforeID")
            UserDefaults.standard.set(afterID, forKey: "PendingComparisonAfterID")
            NotificationCenter.default.post(
                name: .setshotOpenComparison,
                object: nil,
                userInfo: ["beforeID": beforeID, "afterID": afterID]
            )
        }
        completionHandler()
    }

    private func runBackgroundSnapshot() {
        Task {
            do {
                let existing = (try? await SnapshotStore.shared.list()) ?? []
                let sorted = existing.sorted { $0.date < $1.date }
                let previous = sorted.last
                let beforePrevious = sorted.dropLast().last
                let snapshot = try await SnapshotRunner().run()
                let stored = try await SnapshotStore.shared.save(snapshot.rawOutput, takenAt: snapshot.takenAt)
                if let previous {
                    let (kb, _) = await KBFetcher.shared.fetchIfNeeded()
                    if let previousRaw = try? await SnapshotStore.shared.load(previous),
                       let storedRaw = try? await SnapshotStore.shared.load(stored),
                       var result = try? await DiffEngine().diff(
                           before: Snapshot(takenAt: previous.date, rawOutput: previousRaw),
                           after: Snapshot(takenAt: stored.date, rawOutput: storedRaw),
                           kb: kb)
                           .filteringHardware(hasBattery: SnapshotRunner.hasBattery) {

                        var effectivePrevious = previous

                        // If `previous` only existed because of a transient spike (e.g. macOS
                        // briefly resetting a preference domain) and this snapshot undoes every
                        // one of those changes, discard `previous` as noise and recompute against
                        // whatever came before it — surfacing any real change left over.
                        if result.recognized.count + result.unrecognized.count > 0,
                           let beforePrevious,
                           let beforePreviousRaw = try? await SnapshotStore.shared.load(beforePrevious),
                           let justifyingResult = try? await DiffEngine().diff(
                               before: Snapshot(takenAt: beforePrevious.date, rawOutput: beforePreviousRaw),
                               after: Snapshot(takenAt: previous.date, rawOutput: previousRaw),
                               kb: kb)
                               .filteringHardware(hasBattery: SnapshotRunner.hasBattery),
                           DiffEngine.isFullReversal(of: result, reversing: justifyingResult) {
                            try? await SnapshotStore.shared.delete(previous)
                            _ = await JournalStore.shared.delete(afterSnapshotId: previous.id)
                            if let recomputed = try? await DiffEngine().diff(
                                before: Snapshot(takenAt: beforePrevious.date, rawOutput: beforePreviousRaw),
                                after: Snapshot(takenAt: stored.date, rawOutput: storedRaw),
                                kb: kb)
                                .filteringHardware(hasBattery: SnapshotRunner.hasBattery) {
                                result = recomputed
                                effectivePrevious = beforePrevious
                            }
                        }

                        let r = result.recognized.count
                        let u = result.unrecognized.count
                        let autoDelete = UserDefaults.standard.object(forKey: "AutoDeleteEmptyScheduledSnapshots") as? Bool ?? true
                        if autoDelete && r == 0 && u == 0 {
                            try? await SnapshotStore.shared.delete(stored)
                        } else {
                            try? await SnapshotStore.shared.saveMeta(for: stored, recognized: r, unrecognized: u, scheduled: true)
                            _ = await JournalStore.shared.add(recognized: result.recognized, afterSnapshot: stored)
                            if r > 0 || u > 0 {
                                await postSnapshotNotification(result: result, previous: effectivePrevious, stored: stored)
                            }
                        }
                    }
                }
            } catch {}
            await MainActor.run { NSApp.terminate(nil) }
        }
    }

    private func postSnapshotNotification(result: DiffResult, previous: StoredSnapshot, stored: StoredSnapshot) async {
        let center = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        let r = result.recognized.count
        let u = result.unrecognized.count
        if r > 0 && u > 0 {
            content.title = "SetShot: \(r) recognized change\(r == 1 ? "" : "s"), \(u) unrecognized change\(u == 1 ? "" : "s") detected"
        } else if r > 0 {
            content.title = "SetShot: \(r) recognized change\(r == 1 ? "" : "s") detected"
        } else {
            content.title = "SetShot: \(u) unrecognized change\(u == 1 ? "" : "s") detected"
        }
        content.body = "Click to compare with the previous snapshot."
        content.userInfo = ["beforeID": previous.id, "afterID": stored.id]
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        try? await center.add(request)
    }
}

extension Notification.Name {
    static let setshotOpenComparison = Notification.Name("com.tidbits.SetShot.openComparison")
    static let setshotOpenSettings = Notification.Name("com.tidbits.SetShot.openSettings")
}
