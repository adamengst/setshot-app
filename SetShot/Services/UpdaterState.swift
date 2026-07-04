import Sparkle
import Combine

// Holds the Sparkle controller and KVO-observes canCheckForUpdates so SwiftUI
// can reactively enable/disable "Check for Updates". Without KVO, the disabled()
// modifier evaluates once and stays greyed out while Sparkle's auto-check runs.
//
// Must be held as @StateObject (not a plain stored property) in the App struct so
// SwiftUI owns the lifetime. A plain stored property on a value-type App struct can
// be released and recreated across body evaluations, tearing down Sparkle mid-run.
final class UpdaterState: ObservableObject {
    @Published var canCheckForUpdates = false
    let controller: SPUStandardUpdaterController
    private var observation: NSKeyValueObservation?

    // False in debug/test builds so Sparkle's XPC services aren't invoked without
    // the correct signing identity. True in release builds. Exposed for testing.
    static let startsInRelease: Bool = {
        #if DEBUG
        return false
        #else
        return true
        #endif
    }()

    init() {
        // Gate auto-downloads at the allowsAutomaticUpdates level so Sparkle never
        // silently installs. This also removes the "automatically download" checkbox
        // from the update dialog. Without this, a prior Sparkle run that wrote
        // SUAutomaticallyUpdate=true to UserDefaults can override per-launch intent.
        UserDefaults.standard.set(false, forKey: "SUAllowsAutomaticUpdates")
        controller = SPUStandardUpdaterController(
            startingUpdater: Self.startsInRelease,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        observation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            DispatchQueue.main.async { self?.canCheckForUpdates = updater.canCheckForUpdates }
        }
        // Force a background check on every launch so a pending update re-shows
        // immediately. Without this, Sparkle gates checks against SULastCheckTime +
        // SUScheduledCheckInterval and won't check (or show any dialog) until the
        // timer fires. Using checkForUpdatesInBackground (not checkForUpdates) keeps
        // it silent when there is no update. The async dispatch ensures this runs
        // after Sparkle's own deferred startUpdateCycle, avoiding a session collision,
        // and within the 3-second appNearUpdaterInitialization window that makes
        // Sparkle show the dialog immediately with focus.
        if Self.startsInRelease {
            DispatchQueue.main.async { [controller] in
                controller.updater.checkForUpdatesInBackground()
            }
        }
    }
}
