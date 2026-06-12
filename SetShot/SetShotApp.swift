import SwiftUI
import Sparkle
import UserNotifications

struct SetShotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appModel = AppModel()
    // Don't start the updater in debug builds: the local signing identity
    // doesn't re-sign Sparkle's XPC services, causing a spurious error dialog.
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: {
            #if DEBUG
            return false
            #else
            return true
            #endif
        }(),
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

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
                    .background(WindowFrameSaver(name: "SetShotMainWindow"))
                    .task { await appModel.start(); PingService.pingIfNeeded() }
            }
        }
        .defaultSize(width: 750, height: 600)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About SetShot") {
                    AboutWindowController.shared.show(appModel: appModel)
                }
            }
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    updaterController.updater.checkForUpdates()
                }
                .disabled(!updaterController.updater.canCheckForUpdates)
            }
            CommandGroup(replacing: .help) {}
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
        if CommandLine.arguments.contains("--background-snapshot") {
            runBackgroundSnapshot()
        } else {
            UNUserNotificationCenter.current().delegate = self
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
                let previous = existing.sorted { $0.date < $1.date }.last
                let snapshot = try await SnapshotRunner().run()
                let stored = try await SnapshotStore.shared.save(snapshot.rawOutput, takenAt: snapshot.takenAt)
                if let previous {
                    let (kb, _) = await KBFetcher.shared.fetchIfNeeded()
                    if let b = try? await SnapshotStore.shared.load(previous),
                       let a = try? await SnapshotStore.shared.load(stored),
                       let result = try? await DiffEngine().diff(
                           before: Snapshot(takenAt: previous.date, rawOutput: b),
                           after: Snapshot(takenAt: stored.date, rawOutput: a),
                           kb: kb) {
                        let r = result.recognized.count
                        let u = result.unrecognized.count
                        let autoDelete = UserDefaults.standard.bool(forKey: "AutoDeleteEmptyScheduledSnapshots")
                        if autoDelete && r == 0 && u == 0 {
                            try? await SnapshotStore.shared.delete(stored)
                        } else {
                            try? await SnapshotStore.shared.saveMeta(for: stored, recognized: r, unrecognized: u, scheduled: true)
                            _ = await JournalStore.shared.add(recognized: result.recognized, afterSnapshot: stored)
                            if r > 0 || u > 0 {
                                await postSnapshotNotification(result: result, previous: previous, stored: stored)
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
}
