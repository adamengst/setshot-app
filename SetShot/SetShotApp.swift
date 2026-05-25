import SwiftUI
import Sparkle

@main
struct SetShotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appModel = AppModel()
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
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
                    .task { await appModel.loadKB() }
                    .task { await appModel.loadSnapshots() }
            }
        }
        .windowResizability(.contentSize)
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
                try await SnapshotStore.shared.save(snapshot.rawOutput, takenAt: snapshot.takenAt)
            } catch {}
            await MainActor.run { NSApp.terminate(nil) }
        }
    }
}
