import Foundation

// Every CLI mode is handled before the SwiftUI lifecycle so these invocations never
// connect to the WindowServer. Without that, the hundreds of per-plist calls
// setshot.sh used to make would each briefly touch the Dock, causing visible
// vibration.
let cliModes: [String: () -> Void] = [
    "--flatten-plist-batch": PlistFlattener.runBatch, // plist paths on stdin -> stdout
    "--flatten-plist": PlistFlattener.run,            // one plist on stdin -> stdout
    "--default-handlers": DefaultHandlers.run,        // -> stdout
    "--explain-diff": DiffExplainer.run,              // two snapshot paths in argv
]

// Order matters: --flatten-plist-batch has to be tested before --flatten-plist would
// be, so match on the longest flag present rather than on argument order.
let requested = CommandLine.arguments
    .filter { $0.hasPrefix("--") }
    .sorted { $0.count > $1.count }

if let flag = requested.first(where: { cliModes[$0] != nil }) {
    cliModes[flag]!() // each writes stdout and calls exit(0)
}

// An unrecognised `--flag` must fail rather than fall through to the app. setshot.sh
// calls this binary with flags that a different build may not have, and silently
// launching the GUI instead left the script waiting on a process that never exits --
// it hung a capture for ten minutes rather than reporting anything. Exiting here
// turns a version mismatch into an error the caller can see.
//
// Only `--` flags are checked: AppKit and Xcode pass their own single-dash arguments
// (-NSDocumentRevisionsDebugMode, -ApplePersistenceIgnoreState) on a normal launch.
if let unknown = requested.first {
    FileHandle.standardError.write(Data("""
        SetShot: unrecognised option \(unknown)
        Available: \(cliModes.keys.sorted().joined(separator: ", "))

        """.utf8))
    exit(64) // EX_USAGE
}

SetShotApp.main()
