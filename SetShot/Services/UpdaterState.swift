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

    /// Whether this launch should run the updater at all. Not in a headless scheduled
    /// snapshot: that process quits within seconds, so a check there would only fetch
    /// the appcast on every snapshot and could find an update with no window to show it.
    static func startsUpdater(arguments: [String], release: Bool = startsInRelease) -> Bool {
        release && !arguments.contains(LaunchArguments.backgroundSnapshot)
    }

    init() {
        // Gate auto-downloads at the allowsAutomaticUpdates level so Sparkle never
        // silently installs. This also removes the "automatically download" checkbox
        // from the update dialog. Without this, a prior Sparkle run that wrote
        // SUAutomaticallyUpdate=true to UserDefaults can override per-launch intent.
        UserDefaults.standard.set(false, forKey: "SUAllowsAutomaticUpdates")
        let starts = Self.startsUpdater(arguments: CommandLine.arguments)
        controller = SPUStandardUpdaterController(
            startingUpdater: starts,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        observation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            DispatchQueue.main.async { self?.canCheckForUpdates = updater.canCheckForUpdates }
        }
        // Check on every launch, rather than waiting for SULastCheckTime plus
        // SUScheduledCheckInterval, so a waiting update shows as soon as SetShot opens.
        // checkForUpdatesInBackground stays silent when there is nothing new.
        //
        // It has to be called here, before this run loop turn ends. Starting the
        // updater queues Sparkle's own start of its update cycle for the next turn, and
        // that marks a session in progress while it works out when the next scheduled
        // check is due; a check requested while a session is in progress is refused.
        // The call used to be dispatched async to run after that start, so Sparkle
        // refused it on every launch and nothing checked until Check for Updates was
        // chosen by hand. Called now, the check is the session, Sparkle skips its own
        // start, and once the check finishes it schedules the next one at the usual
        // interval. Sparkle leaves this turn free for exactly this.
        //
        // Gated on automaticallyChecksForUpdates (SUEnableAutomaticChecks) so turning
        // off "Check for updates automatically" in Settings stops this too.
        if starts && controller.updater.automaticallyChecksForUpdates {
            controller.updater.checkForUpdatesInBackground()
        }
    }
}
