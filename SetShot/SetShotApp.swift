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
        private var setupDone = false
        private var readyToSave = false

        init(name: String) { self.name = name; super.init(frame: .zero) }
        required init?(coder: NSCoder) { fatalError() }

        private var key: String { "WindowFrame.\(name)" }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, !setupDone else { return }
            setupDone = true

            // Save position when the user moves the window (guarded by readyToSave
            // so SwiftUI's initial positioning is not recorded).
            observers.append(NotificationCenter.default.addObserver(
                forName: NSWindow.didMoveNotification, object: window, queue: .main
            ) { [weak self, weak window] _ in
                guard let self, self.readyToSave, let window else { return }
                UserDefaults.standard.set(NSStringFromRect(window.frame), forKey: self.key)
            })

            // didEndLiveResizeNotification only fires for user-driven resizes, not
            // SwiftUI auto-sizing, so no guard is needed.
            observers.append(NotificationCenter.default.addObserver(
                forName: NSWindow.didEndLiveResizeNotification, object: window, queue: .main
            ) { [weak self, weak window] _ in
                guard let self, let window else { return }
                UserDefaults.standard.set(NSStringFromRect(window.frame), forKey: self.key)
            })

            // Restore the saved frame after SwiftUI finishes its layout pass.
            let savedKey = key
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self, weak window] in
                defer { self?.readyToSave = true }
                guard let window,
                      let str = UserDefaults.standard.string(forKey: savedKey) else { return }
                let frame = NSRectFromString(str)
                guard frame.width > 0, frame.height > 0 else { return }
                window.setFrame(frame, display: true)
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
