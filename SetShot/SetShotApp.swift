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
            CommandGroup(replacing: .help) {
                Button("SetShot Help") {
                    (NSApp.delegate as? AppDelegate)?.openHelpWindow()
                }
                .keyboardShortcut("?", modifiers: .command)
            }
        }
    }
}

private struct WindowFrameSaver: NSViewRepresentable {
    let name: String

    func makeNSView(context: Context) -> FrameSaverView { FrameSaverView(name: name) }
    func updateNSView(_ nsView: FrameSaverView, context: Context) {}

    class FrameSaverView: NSView {
        let name: String
        init(name: String) { self.name = name; super.init(frame: .zero) }
        required init?(coder: NSCoder) { fatalError() }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.setFrameAutosaveName(name)
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var helpWindow: NSWindow?

    func openHelpWindow() {
        if helpWindow == nil {
            let controller = NSHostingController(rootView: HelpView())
            let window = NSWindow(contentViewController: controller)
            window.title = "SetShot Help"
            window.styleMask = NSWindow.StyleMask([.titled, .closable, .resizable, .miniaturizable])
            window.setFrameAutosaveName("SetShotHelpWindow")
            window.center()
            helpWindow = window
        }
        helpWindow?.makeKeyAndOrderFront(nil)
    }

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
