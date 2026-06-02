import Foundation

// Handle --flatten-plist before the SwiftUI lifecycle so we never connect to the
// WindowServer. Without this, each of the hundreds of per-plist invocations
// from setshot.sh would briefly touch the Dock, causing visible vibration.
if CommandLine.arguments.contains("--flatten-plist") {
    PlistFlattener.run() // reads stdin, writes stdout, calls exit(0)
}

SetShotApp.main()
