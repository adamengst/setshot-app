import Foundation

/// Decides what a launch of the SetShot binary is for, from its `--` flags.
///
/// Kept out of main.swift so the decision can be tested: top-level code there runs
/// only as the program's entry point, which a unit test never reaches.
enum LaunchArguments {

    /// Written into the LaunchAgent by `SchedulerManager`. Handled by the app itself
    /// (headless, no window), so it must reach `SetShotApp.main()` rather than being
    /// claimed or rejected here.
    static let backgroundSnapshot = "--background-snapshot"

    /// Flags the app lifecycle handles after `SetShotApp.main()`.
    static let appFlags: Set<String> = [backgroundSnapshot]

    /// Flags handled before the SwiftUI lifecycle so these invocations never connect
    /// to the WindowServer. Without that, the hundreds of per-plist calls setshot.sh
    /// used to make would each briefly touch the Dock, causing visible vibration.
    static let cliModes: [String: () -> Void] = [
        "--flatten-plist-batch": PlistFlattener.runBatch, // plist paths on stdin -> stdout
        "--flatten-plist": PlistFlattener.run,            // one plist on stdin -> stdout
        "--default-handlers": DefaultHandlers.run,        // -> stdout
        "--explain-diff": DiffExplainer.run,              // two snapshot paths in argv
        "--background-items": BackgroundItems.run,        // -> stdout
    ]

    enum Resolution: Equatable {
        case cli(String)
        case app
        case unrecognised(String)
    }

    static func resolve(_ arguments: [String]) -> Resolution {
        // Order matters: --flatten-plist-batch has to be tested before --flatten-plist
        // would be, so match on the longest flag present rather than on argument order.
        let requested = arguments
            .filter { $0.hasPrefix("--") }
            .sorted { $0.count > $1.count }

        if let flag = requested.first(where: { cliModes[$0] != nil }) {
            return .cli(flag)
        }

        // An unrecognised `--flag` must fail rather than fall through to the app.
        // setshot.sh calls this binary with flags that a different build may not
        // have, and silently launching the GUI instead left the script waiting on a
        // process that never exits -- it hung a capture for ten minutes rather than
        // reporting anything.
        //
        // Only `--` flags are checked: AppKit and Xcode pass their own single-dash
        // arguments (-NSDocumentRevisionsDebugMode, -ApplePersistenceIgnoreState) on
        // a normal launch.
        if let unknown = requested.first(where: { !appFlags.contains($0) }) {
            return .unrecognised(unknown)
        }
        return .app
    }
}
