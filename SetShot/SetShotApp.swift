import SwiftUI
import Sparkle

@main
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
                    .task { await appModel.loadKB() }
                    .task { await appModel.loadSnapshots() }
                    .task { await appModel.loadJournal() }
            }
        }
        .defaultSize(width: 800, height: 600)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    updaterController.updater.checkForUpdates()
                }
                .disabled(!updaterController.updater.canCheckForUpdates)
            }
            HelpCommands()
        }

        WindowGroup("SetShot Help", id: "help") {
            HelpView()
                .background(WindowFrameSaver(name: "SetShotHelpWindow"))
        }
        .defaultSize(width: 620, height: 600)
        .commandsRemoved()
    }
}

private struct HelpCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .help) {
            Button("SetShot Help") {
                openWindow(id: "help")
            }
            .keyboardShortcut("?", modifiers: .command)
        }
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

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--background-snapshot") {
            NSApp.setActivationPolicy(.prohibited)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard CommandLine.arguments.contains("--background-snapshot") else { return }
        Task {
            do {
                let snapshot = try await SnapshotRunner().run()
                _ = try await SnapshotStore.shared.save(snapshot.rawOutput, takenAt: snapshot.takenAt)
            } catch {}
            await MainActor.run { NSApp.terminate(nil) }
        }
    }
}
